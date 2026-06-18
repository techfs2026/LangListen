//! OutputSink：cpal 输出层。
//!
//! 负责设备输出流的构建、播放/暂停、淡入包络与 underrun 衰减，以及
//! 把 mono 样本写成 interleaved 的 N 声道。样本来源被抽象为 [`SampleSource`]，
//! 由调用方实现（泛听 = ring 流式，精听 = 内存 buffer），OutputSink 本身
//! 不关心数据怎么来。

use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, StreamTrait};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// 淡入步长：48kHz 下约 42ms 升满。音源切换（seek）后从 0 重新淡入，避免爆音。
const FADE_STEPS: f32 = 2000.0;

/// 一次 block 填充的结果。
pub struct FillInfo {
    /// 实际写入的有效 mono 样本数（从 0 起连续）。其余视为 underrun。
    pub produced: usize,
    /// 本 block 是否发生了不连续（seek / 换源），是则 OutputSink 重置淡入。
    pub discontinuity: bool,
    /// 本 block 末段连续区间首样本的源位置（无循环跳转时即 block 首样本位置）。
    /// 与 `run_offset` 一起供 OutputSink 记录播放时钟快照。
    pub run_start_sample: u64,
    /// 末段连续区间在本 block 内的起始偏移（AB 循环跳回会切出新区间，否则为 0）。
    pub run_offset: usize,
}

/// 音频回调时刻的播放进度快照：本 block 末段连续样本区间，及其首样本开始播放的时刻。
/// 「已送入」的位置按 block 阶梯前进且领先于扬声器一个输出缓冲，直接上报会比听到的
/// 声音系统性超前；用本快照把任意时刻线性映射回样本位置，即得真正的扬声器端进度。
#[derive(Clone, Copy)]
pub struct ClockSnapshot {
    /// start_sample 开始播放的时刻（回调时刻 + 设备上报的呈现延迟）
    play_start: Instant,
    /// 连续区间首样本的源位置
    start_sample: u64,
    /// 连续区间末尾（== 本次填充后的源位置）
    end_sample: u64,
    /// play_start 之前声音是否与本区间连续（是则允许向前外推到上一 block）
    extrapolate_back: bool,
}

impl ClockSnapshot {
    /// 本次填充后的源位置，等于音源此刻的 pos；不相等说明快照已过期（刚 seek/变速）。
    pub fn end_sample(&self) -> u64 {
        self.end_sample
    }

    /// t 时刻已经听到的样本位置（源位置坐标）。
    pub fn heard_sample_at(&self, t: Instant, sample_rate: u32) -> u64 {
        let dt = if t >= self.play_start {
            (t - self.play_start).as_secs_f64()
        } else {
            -(self.play_start - t).as_secs_f64()
        };
        let lo = if self.extrapolate_back {
            0.0
        } else {
            self.start_sample as f64
        };
        let aud = self.start_sample as f64 + dt * sample_rate as f64;
        aud.clamp(lo, self.end_sample as f64).round() as u64
    }
}

/// 播放时钟：音频回调每个 block 写入一份快照（try_lock，绝不阻塞回调线程），
/// 进度线程读取后可把「此刻」换算成真正听到的样本位置。
#[derive(Default)]
pub struct PlaybackClock {
    snap: Mutex<Option<ClockSnapshot>>,
}

impl PlaybackClock {
    fn store(&self, s: ClockSnapshot) {
        if let Ok(mut g) = self.snap.try_lock() {
            *g = Some(s);
        }
    }

    /// 最近一次音频回调的快照；尚无回调时为 None。
    pub fn snapshot(&self) -> Option<ClockSnapshot> {
        self.snap.lock().ok().and_then(|g| *g)
    }
}

/// 音频样本来源。OutputSink 的 cpal 回调每个 block 调用一次 [`fill`](Self::fill)。
///
/// `fill` 在实时音频回调线程中调用，**必须无锁、无阻塞、不分配**。
pub trait SampleSource: Send + Sync {
    /// 把本 block 的 mono 样本写入 `out`：
    /// - 写入 `out[0..produced]`，返回 `produced`；
    /// - 处理自身的 seek / 循环 / 区间逻辑；
    /// - 通过 `discontinuity` 告知 OutputSink 是否需要重置淡入。
    fn fill(&self, out: &mut [f32]) -> FillInfo;
}

/// cpal 输出流的持有者。drop 时停止输出流。
pub struct OutputSink {
    stream: cpal::Stream,
    sample_rate: u32,
    channels: u16,
    clock: Arc<PlaybackClock>,
    /// play() 置位：刚从暂停恢复，暂停前后样本在时间上不连续，下个快照禁止向前外推
    resumed: Arc<AtomicBool>,
}

impl OutputSink {
    /// 用给定设备与配置构建输出流，从 `source` 拉取 mono 样本。
    /// 构建后需调用 [`play`](Self::play) 才开始输出。
    pub fn new(
        device: &cpal::Device,
        config: &cpal::StreamConfig,
        source: Arc<dyn SampleSource>,
    ) -> Result<Self> {
        let channels = config.channels as usize;
        let sample_rate = config.sample_rate;

        // 回调内的状态：淡入乘数、上一帧（underrun 衰减用）、mono 暂存 buffer
        let mut fade_mult = 0.0f32;
        let mut prev_sample = 0.0f32;
        let mut mono: Vec<f32> = Vec::new();

        let clock = Arc::new(PlaybackClock::default());
        let resumed = Arc::new(AtomicBool::new(false));
        let clock_cb = clock.clone();
        let resumed_cb = resumed.clone();
        let rate_f = sample_rate as f64;

        let stream = device
            .build_output_stream(
                config,
                move |out: &mut [f32], info: &cpal::OutputCallbackInfo| {
                    // 本批样本开始播放的时刻 = 回调时刻 + 设备上报的呈现延迟
                    let cb_now = Instant::now();
                    let ts = info.timestamp();
                    let latency = ts
                        .playback
                        .duration_since(&ts.callback)
                        .unwrap_or(Duration::ZERO);

                    let frames = out.len() / channels;
                    if mono.len() < frames {
                        mono.resize(frames, 0.0);
                    }

                    let fill = source.fill(&mut mono[..frames]);
                    if fill.discontinuity {
                        fade_mult = 0.0;
                        prev_sample = 0.0;
                    }

                    // 播放时钟快照：本 block 末段连续区间 [start, end) 从何时开始播放
                    let was_resumed = resumed_cb.swap(false, Ordering::Relaxed);
                    let run_len = fill.produced.saturating_sub(fill.run_offset) as u64;
                    clock_cb.store(ClockSnapshot {
                        play_start: cb_now
                            + latency
                            + Duration::from_secs_f64(fill.run_offset as f64 / rate_f),
                        start_sample: fill.run_start_sample,
                        end_sample: fill.run_start_sample + run_len,
                        extrapolate_back: !fill.discontinuity
                            && fill.run_offset == 0
                            && !was_resumed,
                    });

                    for fi in 0..frames {
                        let s = if fi < fill.produced {
                            if fade_mult < 1.0 {
                                fade_mult = (fade_mult + 1.0 / FADE_STEPS).min(1.0);
                            }
                            let v = mono[fi] * fade_mult;
                            prev_sample = v;
                            v
                        } else {
                            // underrun：衰减到静音 + 重置淡入
                            fade_mult = 0.0;
                            prev_sample *= 0.95;
                            if prev_sample.abs() < 1e-5 {
                                prev_sample = 0.0;
                            }
                            prev_sample
                        };

                        // 复制到所有声道（mono → N声道，interleaved）
                        for ch in 0..channels {
                            out[fi * channels + ch] = s;
                        }
                    }
                },
                |err| log::error!("cpal stream error: {err}"),
                None,
            )
            .context("build_output_stream")?;

        Ok(OutputSink {
            stream,
            sample_rate,
            channels: config.channels,
            clock,
            resumed,
        })
    }

    /// 播放时钟（时刻 → 听到的样本位置），供进度上报消除输出缓冲延迟与 block 量化误差。
    pub fn clock(&self) -> Arc<PlaybackClock> {
        self.clock.clone()
    }

    pub fn play(&self) -> Result<()> {
        self.resumed.store(true, Ordering::Relaxed);
        self.stream.play().map_err(|e| anyhow!("cpal play: {e}"))
    }

    pub fn pause(&self) -> Result<()> {
        self.stream.pause().map_err(|e| anyhow!("cpal pause: {e}"))
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn channels(&self) -> u16 {
        self.channels
    }
}
