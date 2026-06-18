//! PracticePlayer：精听播放引擎（内存 buffer 路径）。
//!
//! - 解码整段为 mono buffer（`BufferSource`）；
//! - cpal 输出流配在设备默认采样率，BufferSource 解码时重采样到该采样率；
//! - 进度线程每 50ms 推送 `practice-progress`：positionSec 为「听到的」位置
//!   （已扣输出缓冲延迟），并带 `emitMs` 发出时刻供前端对齐时钟；
//!   播完推送一次 `practice-ended`。
//!
//! 采样级区间播放 / AB 循环 / 变速在后续步骤加。

use anyhow::{anyhow, Context, Result};
use audioplayer::{BufferSource, OutputSink};
use cpal::traits::{DeviceTrait, HostTrait};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};

const PROGRESS_TICK_MS: u64 = 50;

pub struct PracticePlayer {
    source: Arc<BufferSource>,
    sink: OutputSink,
    should_exit: Arc<AtomicBool>,
    progress_handle: Option<JoinHandle<()>>,
}

impl PracticePlayer {
    pub fn open(path: &str, app: AppHandle) -> Result<Self> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| anyhow!("no output device"))?;
        let supported = device
            .default_output_config()
            .context("default_output_config")?;
        let output_rate = supported.sample_rate();

        let source = Arc::new(BufferSource::load_from_file_at_rate(
            path,
            Some(output_rate),
        )?);
        let config = cpal::StreamConfig {
            channels: supported.channels(),
            sample_rate: output_rate,
            buffer_size: cpal::BufferSize::Default,
        };

        let sink = OutputSink::new(&device, &config, source.clone())?;
        sink.pause().ok();

        log::info!(
            "PracticePlayer: output_rate={output_rate} channels={} dur={:.2}s",
            supported.channels(),
            source.duration_secs(),
        );

        // 进度推送线程
        let should_exit = Arc::new(AtomicBool::new(false));
        let p_source = source.clone();
        let p_exit = should_exit.clone();
        let p_clock = sink.clock();
        let p_rate = output_rate;
        let progress_handle = thread::Builder::new()
            .name("practice-progress".into())
            .spawn(move || {
                // 会话内单调时钟基准：emitMs 为本条事件发出时相对它的毫秒数。
                // 前端据此对齐两边时钟、测出传输延迟，无需写死补偿常量。
                let base = Instant::now();
                let mut ended = false;
                while !p_exit.load(Ordering::Acquire) {
                    thread::sleep(Duration::from_millis(PROGRESS_TICK_MS));

                    // 上报「听到的」位置：用播放时钟快照把“此刻”映射回样本位置，
                    // 消除输出缓冲延迟与 pos 按 block 阶梯前进的量化误差。
                    // 快照过期（刚 seek/变速、尚无回调）时退回 pos——彼时 pos 即权威。
                    let pos = p_source.position_samples();
                    let (heard_samples, heard_is_authoritative) = match p_clock.snapshot() {
                        Some(s) if s.end_sample() == pos => {
                            (s.heard_sample_at(Instant::now(), p_rate), true)
                        }
                        _ => (pos, false),
                    };
                    let heard_sec = heard_samples as f64 / p_rate as f64 * p_source.speed() as f64;

                    let emit_ms = base.elapsed().as_secs_f64() * 1000.0;
                    let _ = app.emit(
                        "practice-progress",
                        serde_json::json!({
                            "positionSec": heard_sec,
                            "emitMs": emit_ms,
                        }),
                    );

                    if p_source.is_finished()
                        && heard_is_authoritative
                        && p_source.is_finished_at_sample(heard_samples)
                    {
                        if !ended {
                            ended = true;
                            let _ = app.emit("practice-ended", serde_json::json!({}));
                        }
                    } else {
                        ended = false;
                    }
                }
            })
            .context("spawn practice-progress thread")?;

        Ok(Self {
            source,
            sink,
            should_exit,
            progress_handle: Some(progress_handle),
        })
    }

    pub fn play(&self) -> Result<()> {
        // 普通播放退出区间模式（loop 仍生效）
        self.source.clear_segment();
        // 已播完再点播放：从头开始
        if self.source.is_finished() {
            self.source.seek_to_secs(0.0);
        }
        self.sink.play()
    }

    pub fn pause(&self) -> Result<()> {
        self.sink.pause()
    }

    pub fn seek(&self, sec: f64) -> Result<()> {
        self.source.seek_to_secs(sec);
        Ok(())
    }

    /// 一次性播放区间 [start, end]，到 end 精确停止（忽略 loop）。
    pub fn play_segment(&self, start_sec: f64, end_sec: f64) -> Result<()> {
        self.source.play_segment(start_sec, end_sec);
        self.sink.play()
    }

    /// 设置/清除 AB 循环。`None` 清除。
    pub fn set_loop(&self, range: Option<(f64, f64)>) -> Result<()> {
        self.source.set_loop(range);
        Ok(())
    }

    /// 变速不变调（[0.5, 4.0]）。保持当前源位置，循环/区间边界自动按新速率换算。
    pub fn set_speed(&self, speed: f32) -> Result<()> {
        self.source.set_speed_async(speed)
    }

    pub fn duration_secs(&self) -> f64 {
        self.source.duration_secs()
    }
}

impl Drop for PracticePlayer {
    fn drop(&mut self) {
        self.should_exit.store(true, Ordering::Release);
        let _ = self.sink.pause();
        if let Some(h) = self.progress_handle.take() {
            let _ = h.join();
        }
        log::info!("PracticePlayer dropped");
    }
}
