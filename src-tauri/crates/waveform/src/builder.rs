use rayon::prelude::*;
use wide::f32x8;

use super::audio::{AudioBuffer, BuildOptions};
use super::peak::{ChannelPyramid, Peak, WaveformSummary};

/// 根据音频时长自动选 base_block_size
fn choose_base_block_size(duration_secs: f64) -> usize {
    if duration_secs <= 60.0 {
        64
    } else if duration_secs <= 600.0 {
        128
    } else {
        256
    }
}

/// 构建完整的多声道峰值金字塔
pub fn build_summary(audio: AudioBuffer, options: BuildOptions) -> WaveformSummary {
    let duration = audio.duration_secs();
    let base_block = options
        .base_block_size
        .filter(|size| *size > 0)
        .unwrap_or_else(|| choose_base_block_size(duration));
    let upper_block = options.upper_block_size.max(2);

    let channel_count = audio.channel_count();
    let sample_rate = audio.sample_rate();
    let total_samples = audio.samples_per_channel() as u64;
    log::debug!(
        "Building summary: duration={:.2}s, channels={}, base_block={}, upper_block={}",
        duration,
        channel_count,
        base_block,
        upper_block
    );

    // 各声道独立构建金字塔(声道之间也可并行)
    let channels: Vec<ChannelPyramid> = (0..channel_count)
        .into_par_iter()
        .map(|ch| {
            let samples = audio.channel(ch).expect("channel index in range");
            build_channel_pyramid(samples, base_block, upper_block)
        })
        .collect();

    WaveformSummary {
        channels,
        audio,
        sample_rate,
        total_samples,
        base_block_size: base_block,
        upper_block_size: upper_block,
    }
}

/// 单声道金字塔构建:Level 0 并行 + 上层串行
fn build_channel_pyramid(samples: &[f32], base_block: usize, upper_block: usize) -> ChannelPyramid {
    let level0 = build_level0_parallel(samples, base_block);
    log::debug!("  Level 0: {} peaks", level0.len());

    let mut levels = vec![level0];
    while levels.last().unwrap().len() > 1 {
        let prev = levels.last().unwrap();
        let next = build_upper_level(prev, upper_block);
        log::debug!("  Level {}: {} peaks", levels.len(), next.len());
        levels.push(next);
    }

    ChannelPyramid { levels }
}

/// Level 0:按 block_size 切分样本,rayon 并行计算每块的 [min, max, rms]
/// 块内使用 SIMD (wide::f32x8) 加速
fn build_level0_parallel(samples: &[f32], block_size: usize) -> Vec<Peak> {
    let total_peaks = samples.len().div_ceil(block_size);
    (0..total_peaks)
        .into_par_iter()
        .map(|i| {
            let start = i * block_size;
            let end = (start + block_size).min(samples.len());
            compute_peak_simd(&samples[start..end])
        })
        .collect()
}

/// 用 SIMD 计算一块样本的 min / max / rms
/// 跨平台:`wide` crate 在 x86 (SSE/AVX)、ARM (NEON,含 Apple Silicon)、WASM SIMD 上都自动启用
/// 不支持 SIMD 的目标平台会自动 fallback 为标量代码,不会编译失败
#[inline]
fn compute_peak_simd(slice: &[f32]) -> Peak {
    if slice.is_empty() {
        return Peak::zero();
    }

    let n = slice.len();
    let remainder_start = (n / 8) * 8;
    let has_simd = remainder_start > 0;

    let mut min_v = f32x8::splat(f32::INFINITY);
    let mut max_v = f32x8::splat(f32::NEG_INFINITY);
    let mut sum_sq_v = f32x8::splat(0.0);

    // 主循环:每次处理 8 个 f32
    // 用 chunks_exact 保证编译器能消除边界检查,也让代码不需要 unsafe
    let main = &slice[..remainder_start];
    for chunk in main.chunks_exact(8) {
        let arr: [f32; 8] = chunk.try_into().expect("chunks_exact yields exactly 8");
        let v = f32x8::new(arr);
        min_v = min_v.fast_min(v);
        max_v = max_v.fast_max(v);
        sum_sq_v += v * v;
    }

    // 横向归约 SIMD lanes → 标量
    // 若主循环没跑过,使用 ±Inf 哨兵让尾部循环正确接管
    let (mut mn, mut mx, mut sum_sq) = if has_simd {
        let min_arr = min_v.to_array();
        let max_arr = max_v.to_array();
        let sum_sq_arr = sum_sq_v.to_array();
        let mut mn = min_arr[0];
        let mut mx = max_arr[0];
        for k in 1..8 {
            if min_arr[k] < mn {
                mn = min_arr[k];
            }
            if max_arr[k] > mx {
                mx = max_arr[k];
            }
        }
        let sum_sq: f32 = sum_sq_arr.iter().sum();
        (mn, mx, sum_sq)
    } else {
        (f32::INFINITY, f32::NEG_INFINITY, 0.0_f32)
    };

    // 处理尾部不足 8 个的样本(也覆盖 n < 8 的全部样本)
    for &s in &slice[remainder_start..] {
        if s < mn {
            mn = s;
        }
        if s > mx {
            mx = s;
        }
        sum_sq += s * s;
    }

    // 兜底:理论上 slice 非空时 mn/mx 必然有限
    if !mn.is_finite() {
        mn = 0.0;
    }
    if !mx.is_finite() {
        mx = 0.0;
    }

    let rms = (sum_sq / n as f32).sqrt();

    Peak {
        min: mn,
        max: mx,
        rms,
        sample_count: n as u64,
    }
}

/// 上层:把下层 block_size 个 Peak 压缩为 1 个
/// - min/max:取区间 min/max
/// - rms:能量域加权(平方平均后开方),保证物理一致性
fn build_upper_level(prev: &[Peak], block_size: usize) -> Vec<Peak> {
    let total = prev.len().div_ceil(block_size);
    (0..total)
        .map(|i| {
            let start = i * block_size;
            let end = (start + block_size).min(prev.len());
            let slice = &prev[start..end];

            let mut mn = f32::INFINITY;
            let mut mx = f32::NEG_INFINITY;
            let mut weighted_sum_sq = 0.0_f64;
            let mut sample_count = 0_u64;
            for p in slice {
                if p.min < mn {
                    mn = p.min;
                }
                if p.max > mx {
                    mx = p.max;
                }
                weighted_sum_sq += p.rms as f64 * p.rms as f64 * p.sample_count as f64;
                sample_count += p.sample_count;
            }
            let rms = if sample_count == 0 {
                0.0
            } else {
                (weighted_sum_sq / sample_count as f64).sqrt() as f32
            };
            Peak {
                min: mn,
                max: mx,
                rms,
                sample_count,
            }
        })
        .collect()
}
