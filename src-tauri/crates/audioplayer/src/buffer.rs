//! BufferSource：整段解码进内存的音源（mono / f32 / 输出采样率）。
//!
//! 适合精听这类「短片段、要采样级精确控制」的场景——和泛听的 ring 流式相反：
//! 整段在内存里，播放位置就是样本下标，因此 seek / 区间播放 / AB 循环都做到采样级精确。
//!
//! # 变速不变调
//!
//! 保留原始解码 buffer（`original`，输出采样率）。切换速率时用 [`AtempoFilter`] 把整段重渲染成
//! 「变速后的播放 buffer」（pitch 不变，长度变为 `原长/speed`），通过 `ArcSwap` 无锁热替换，
//! 音频线程下个 block 即采用新 buffer。所有对外的位置/区间/循环都以**源秒**为准，
//! 内部换算成当前播放 buffer 的样本下标——因此波形（按源时间绘制）始终对得上。
//!
//! 解码与重渲染都复用 [`AtempoFilter`](crate::AtempoFilter)，和泛听走同一条已验证路径。

use anyhow::{anyhow, Context, Result};
use arc_swap::ArcSwap;
use ffmpeg_next as ffmpeg;
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

use crate::atempo::AtempoFilter;
use crate::output::{FillInfo, SampleSource};

/// 命令线程维护的「源秒」级真值，用于速率切换时重新换算样本下标。
/// 仅命令线程访问，音频线程只读派生的 *_idx 原子。
#[derive(Default)]
struct Params {
    loop_range_sec: Option<(f64, f64)>,
    segment_end_sec: Option<f64>,
}

pub struct BufferSource {
    /// 原始解码样本（mono，源采样率），重渲染的输入，只读。
    original: Arc<Vec<f32>>,
    /// 当前播放 buffer（speed=1.0 时即指向 original 同一 Arc，不复制数据）。
    playback: ArcSwap<Vec<f32>>,
    sample_rate: u32,
    /// 当前速率（f32 bits）。
    speed_bits: AtomicU32,

    /// 当前读位置（播放 buffer 样本下标）。只在音频线程写。
    pos: AtomicU64,
    /// 待执行 seek 目标（播放 buffer 下标），-1 表示无。命令线程写，音频线程消费。
    seek_target: AtomicI64,
    /// 派生：AB 循环区间（播放 buffer 下标），loop_start<0 表示无循环。
    loop_start_idx: AtomicI64,
    loop_end_idx: AtomicI64,
    /// 派生：一次性区间播放终点（播放 buffer 下标），<0 表示无。
    segment_end_idx: AtomicI64,
    /// 每次变速请求递增；后台渲染完成时只应用最新一代。
    speed_generation: AtomicU64,
    /// 已渲染过的变速 buffer 缓存，key 为 speed.to_bits()。
    speed_cache: Mutex<HashMap<u32, Arc<Vec<f32>>>>,

    params: Mutex<Params>,
}

impl BufferSource {
    /// 把整个文件解码为 mono/f32/源采样率的内存 buffer。
    pub fn load_from_file(path: &str) -> Result<Self> {
        Self::load_from_file_at_rate(path, None)
    }

    /// 把整个文件解码为 mono/f32，并重采样到指定输出采样率。
    /// `output_sample_rate=None` 时沿用源音频采样率。
    pub fn load_from_file_at_rate(path: &str, output_sample_rate: Option<u32>) -> Result<Self> {
        ffmpeg::init().context("ffmpeg init")?;
        let mut ictx = ffmpeg::format::input(&path).with_context(|| format!("open: {path}"))?;

        let (stream_index, mut decoder, src_format, src_rate, src_layout) = {
            let s = ictx
                .streams()
                .best(ffmpeg::media::Type::Audio)
                .ok_or_else(|| anyhow!("no audio stream"))?;
            let idx = s.index();
            let codec_ctx = ffmpeg::codec::Context::from_parameters(s.parameters())?;
            let dec = codec_ctx.decoder().audio()?;
            let fmt = match dec.format() {
                ffmpeg::format::Sample::None => {
                    ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Planar)
                }
                f => f,
            };
            let rate = if dec.rate() > 0 { dec.rate() } else { 48000 };
            let layout = resolve_layout(&dec, &ictx, idx);
            (idx, dec, fmt, rate, layout)
        };

        let output_rate = output_sample_rate.unwrap_or(src_rate).max(1);

        // 用 atempo(speed=1.0) 复用「降混到 mono/fltp/输出采样率」的逻辑
        let mut filter =
            AtempoFilter::new_with_output_rate(src_format, src_layout, src_rate, output_rate, 1.0)?;

        let mut samples: Vec<f32> = Vec::new();
        let mut decoded = ffmpeg::frame::Audio::empty();
        let mut filtered = ffmpeg::frame::Audio::empty();

        // 解码所有 packet
        for (s, p) in ictx.packets() {
            if s.index() != stream_index {
                continue;
            }
            decoder.send_packet(&p).ok();
            while decoder.receive_frame(&mut decoded).is_ok() {
                filter.send(&decoded)?;
                while filter.receive(&mut filtered)? {
                    append_mono(&filtered, &mut samples);
                }
            }
        }

        // flush 解码器
        decoder.send_eof().ok();
        while decoder.receive_frame(&mut decoded).is_ok() {
            filter.send(&decoded)?;
            while filter.receive(&mut filtered)? {
                append_mono(&filtered, &mut samples);
            }
        }

        // flush filter
        filter.send_eof()?;
        while filter.receive(&mut filtered)? {
            append_mono(&filtered, &mut samples);
        }

        if samples.is_empty() {
            return Err(anyhow!("decoded 0 samples: {path}"));
        }

        log::info!(
            "BufferSource loaded: {path} src_rate={src_rate} out_rate={output_rate} samples={} ({:.2}s)",
            samples.len(),
            samples.len() as f64 / output_rate as f64,
        );

        let original = Arc::new(samples);
        let mut speed_cache = HashMap::new();
        speed_cache.insert(1.0f32.to_bits(), original.clone());
        Ok(Self {
            playback: ArcSwap::new(original.clone()), // 1.0 时与 original 共享数据
            original,
            sample_rate: output_rate,
            speed_bits: AtomicU32::new(1.0f32.to_bits()),
            pos: AtomicU64::new(0),
            seek_target: AtomicI64::new(-1),
            loop_start_idx: AtomicI64::new(-1),
            loop_end_idx: AtomicI64::new(-1),
            segment_end_idx: AtomicI64::new(-1),
            speed_generation: AtomicU64::new(0),
            speed_cache: Mutex::new(speed_cache),
            params: Mutex::new(Params::default()),
        })
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn speed(&self) -> f32 {
        f32::from_bits(self.speed_bits.load(Ordering::Relaxed))
    }

    /// 源音频总时长（秒），与速率无关。
    pub fn duration_secs(&self) -> f64 {
        self.original.len() as f64 / self.sample_rate as f64
    }

    /// 当前播放位置（**源秒**，已按速率换算，与波形时间一致）。
    pub fn position_secs(&self) -> f64 {
        self.pos.load(Ordering::Relaxed) as f64 / self.sample_rate as f64 * self.speed() as f64
    }

    /// 当前播放位置（playback buffer 样本下标，与 FillInfo/ClockSnapshot 同坐标）。
    pub fn position_samples(&self) -> u64 {
        self.pos.load(Ordering::Relaxed)
    }

    /// 是否已播到末尾。循环激活时永不结束；区间播放时以 segment_end 为终点。
    pub fn is_finished(&self) -> bool {
        let p = self.pos.load(Ordering::Relaxed);
        self.is_finished_at_sample(p)
    }

    /// 指定播放 buffer 样本位置是否已经到达当前播放终点。
    /// 用于进度线程判断“可闻位置”是否真正播完，避免输出缓冲里的尾部还没发声就提前 ended。
    pub fn is_finished_at_sample(&self, sample: u64) -> bool {
        let seg = self.segment_end_idx.load(Ordering::Relaxed);
        if seg >= 0 {
            return sample >= seg as u64;
        }
        if self.loop_start_idx.load(Ordering::Relaxed) >= 0 {
            return false;
        }
        sample >= self.playback.load().len() as u64
    }

    /// 源秒 → 当前播放 buffer 的样本下标。
    fn sec_to_idx(&self, sec: f64) -> i64 {
        let len = self.playback.load().len() as i64;
        let idx = (sec.max(0.0) * self.sample_rate as f64 / self.speed() as f64) as i64;
        idx.clamp(0, len)
    }

    /// 命令线程调用：seek 到某源秒。下一个 block 生效（带淡入）。手动 seek 退出区间模式。
    pub fn seek_to_secs(&self, sec: f64) {
        {
            let mut params = self.params.lock().unwrap();
            params.segment_end_sec = None;
        }
        self.segment_end_idx.store(-1, Ordering::Release);
        let idx = self.sec_to_idx(sec);
        // 直接更新 pos：暂停态下没有 fill 消费 seek_target，直接写 pos 才能让进度/波形游标立即反映
        self.pos.store(idx as u64, Ordering::Relaxed);
        self.seek_target.store(idx, Ordering::Release);
    }

    /// 设置/清除 AB 循环区间（源秒）。`None` 或非法区间清除。不改变当前播放位置。
    pub fn set_loop(&self, range: Option<(f64, f64)>) {
        let mut params = self.params.lock().unwrap();
        match range {
            Some((a, b)) if b > a => {
                params.loop_range_sec = Some((a, b));
                self.loop_start_idx
                    .store(self.sec_to_idx(a), Ordering::Release);
                self.loop_end_idx
                    .store(self.sec_to_idx(b), Ordering::Release);
            }
            _ => {
                params.loop_range_sec = None;
                self.loop_start_idx.store(-1, Ordering::Release);
                self.loop_end_idx.store(-1, Ordering::Release);
            }
        }
    }

    /// 一次性播放区间 [start, end]（源秒）：seek 到 start，到 end 精确停止，期间忽略 loop。
    pub fn play_segment(&self, start_sec: f64, end_sec: f64) {
        {
            let mut params = self.params.lock().unwrap();
            params.segment_end_sec = Some(end_sec);
        }
        let s = self.sec_to_idx(start_sec);
        let e = self.sec_to_idx(end_sec).max(s);
        self.segment_end_idx.store(e, Ordering::Release);
        self.pos.store(s as u64, Ordering::Relaxed);
        self.seek_target.store(s, Ordering::Release);
    }

    /// 退出区间播放模式（普通播放时调用；保留 loop 设置）。
    pub fn clear_segment(&self) {
        {
            let mut params = self.params.lock().unwrap();
            params.segment_end_sec = None;
        }
        self.segment_end_idx.store(-1, Ordering::Release);
    }

    /// 变速不变调：把原始 buffer 按 `speed` 重渲染并热替换。保持当前源位置。
    /// `speed` 建议 [0.5, 4.0]。speed≈1.0 时直接复用 original，不重渲染。
    pub fn set_speed(&self, speed: f32) -> Result<()> {
        let clamped = speed.clamp(0.5, 4.0);
        if (self.speed() - clamped).abs() < 1e-4 {
            return Ok(());
        }
        let generation = self.speed_generation.fetch_add(1, Ordering::AcqRel) + 1;

        // 快照当前源位置，重渲染后 seek 回去
        let cur_src_sec = self.position_secs();
        let new_buf = self.cached_or_render_speed_buffer(clamped)?;
        self.apply_speed_buffer(clamped, new_buf, cur_src_sec, generation);
        log::info!("BufferSource set_speed → {clamped} @ {cur_src_sec:.2}s");
        Ok(())
    }

    /// 异步变速不变调：立即返回，后台渲染完成后热替换；重复速率走缓存。
    pub fn set_speed_async(self: &Arc<Self>, speed: f32) -> Result<()> {
        let clamped = speed.clamp(0.5, 4.0);
        if (self.speed() - clamped).abs() < 1e-4 {
            return Ok(());
        }

        let generation = self.speed_generation.fetch_add(1, Ordering::AcqRel) + 1;
        let cur_src_sec = self.position_secs();
        let key = clamped.to_bits();

        if let Some(cached) = self.speed_cache.lock().unwrap().get(&key).cloned() {
            self.apply_speed_buffer(clamped, cached, cur_src_sec, generation);
            return Ok(());
        }

        let source = self.clone();
        thread::Builder::new()
            .name(format!("practice-speed-{clamped:.2}"))
            .spawn(
                move || match render_atempo(&source.original, source.sample_rate, clamped) {
                    Ok(rendered) => {
                        let rendered = Arc::new(rendered);
                        source
                            .speed_cache
                            .lock()
                            .unwrap()
                            .insert(key, rendered.clone());
                        if source.speed_generation.load(Ordering::Acquire) == generation {
                            let apply_src_sec = source.position_secs();
                            source.apply_speed_buffer(clamped, rendered, apply_src_sec, generation);
                            log::info!(
                                "BufferSource set_speed_async → {clamped} @ {apply_src_sec:.2}s"
                            );
                        } else {
                            log::info!("BufferSource cached stale speed render → {clamped}");
                        }
                    }
                    Err(err) => {
                        log::warn!("BufferSource set_speed_async {clamped} failed: {err}");
                    }
                },
            )
            .context("spawn practice speed render")?;
        Ok(())
    }

    fn cached_or_render_speed_buffer(&self, speed: f32) -> Result<Arc<Vec<f32>>> {
        let key = speed.to_bits();
        if let Some(cached) = self.speed_cache.lock().unwrap().get(&key).cloned() {
            return Ok(cached);
        }
        let rendered = Arc::new(render_atempo(&self.original, self.sample_rate, speed)?);
        self.speed_cache
            .lock()
            .unwrap()
            .insert(key, rendered.clone());
        Ok(rendered)
    }

    fn apply_speed_buffer(
        &self,
        clamped: f32,
        new_buf: Arc<Vec<f32>>,
        cur_src_sec: f64,
        generation: u64,
    ) {
        if self.speed_generation.load(Ordering::Acquire) != generation {
            return;
        }
        // 先换 buffer 和速率，再据新速率重算所有派生下标与 seek 目标。
        // 顺序：buffer→speed→边界→seek_target（seek_target 最后写，确保下个 block 落到正确位置）。
        self.playback.store(new_buf);
        self.speed_bits.store(clamped.to_bits(), Ordering::Release);
        self.recompute_indices();
        let idx = self.sec_to_idx(cur_src_sec);
        self.pos.store(idx as u64, Ordering::Relaxed);
        self.seek_target.store(idx, Ordering::Release);
    }

    /// 速率变化后，据 params（源秒真值）重算 loop/segment 的播放 buffer 下标。
    fn recompute_indices(&self) {
        let params = self.params.lock().unwrap();
        match params.loop_range_sec {
            Some((a, b)) => {
                self.loop_start_idx
                    .store(self.sec_to_idx(a), Ordering::Release);
                self.loop_end_idx
                    .store(self.sec_to_idx(b), Ordering::Release);
            }
            None => {
                self.loop_start_idx.store(-1, Ordering::Release);
                self.loop_end_idx.store(-1, Ordering::Release);
            }
        }
        match params.segment_end_sec {
            Some(e) => self
                .segment_end_idx
                .store(self.sec_to_idx(e), Ordering::Release),
            None => self.segment_end_idx.store(-1, Ordering::Release),
        }
    }
}

impl SampleSource for BufferSource {
    fn fill(&self, out: &mut [f32]) -> FillInfo {
        // seek（含速率切换后的归位）→ 不连续，触发淡入
        let mut discontinuity = false;
        let t = self.seek_target.swap(-1, Ordering::AcqRel);
        if t >= 0 {
            self.pos.store(t as u64, Ordering::Relaxed);
            discontinuity = true;
        }

        let buf = self.playback.load(); // Arc guard，整个 block 复用一次
        let len = buf.len() as u64;
        let seg = self.segment_end_idx.load(Ordering::Relaxed);
        let ls = self.loop_start_idx.load(Ordering::Relaxed);
        let le = self.loop_end_idx.load(Ordering::Relaxed) as u64;

        let mut p = self.pos.load(Ordering::Relaxed);
        let mut produced = 0usize;
        // 播放时钟用：本 block 末段连续区间的起点（AB 循环跳回会切出新区间）
        let mut run_start_p = p;
        let mut run_offset = 0usize;
        for slot in out.iter_mut() {
            if seg >= 0 {
                // 区间播放：到 end 精确停止
                if p >= seg as u64 {
                    break;
                }
            } else if ls >= 0 && p >= le {
                // AB 循环：到 loop_end 采样级跳回 loop_start（连续，无淡入）
                p = ls as u64;
                run_start_p = p;
                run_offset = produced;
            }
            if p >= len {
                break;
            }
            *slot = buf[p as usize];
            p += 1;
            produced += 1;
        }
        self.pos.store(p, Ordering::Relaxed);

        FillInfo {
            produced,
            discontinuity,
            run_start_sample: run_start_p,
            run_offset,
        }
    }
}

/// 把原始 mono buffer 按 speed 用 atempo 重渲染成新 mono buffer（变速不变调）。
fn render_atempo(original: &[f32], sample_rate: u32, speed: f32) -> Result<Vec<f32>> {
    let layout = ffmpeg::channel_layout::ChannelLayout::MONO;
    let fmt = ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Planar);
    let mut filter = AtempoFilter::new(fmt, layout, sample_rate, speed)?;

    let mut out: Vec<f32> = Vec::with_capacity((original.len() as f32 / speed) as usize + 1024);
    let mut filtered = ffmpeg::frame::Audio::empty();

    const CHUNK: usize = 8192;
    let mut pts: i64 = 0;
    for chunk in original.chunks(CHUNK) {
        let mut frame = ffmpeg::frame::Audio::new(fmt, chunk.len(), layout);
        frame.set_rate(sample_rate);
        frame.set_pts(Some(pts));
        pts += chunk.len() as i64;

        // 写入 planar 单声道平面
        let dst = frame.data_mut(0);
        let dst_f32 =
            unsafe { std::slice::from_raw_parts_mut(dst.as_mut_ptr() as *mut f32, chunk.len()) };
        dst_f32.copy_from_slice(chunk);

        filter.send(&frame)?;
        while filter.receive(&mut filtered)? {
            append_mono(&filtered, &mut out);
        }
    }
    filter.send_eof()?;
    while filter.receive(&mut filtered)? {
        append_mono(&filtered, &mut out);
    }
    Ok(out)
}

/// 把 mono/fltp 帧的样本追加到 buffer。
fn append_mono(frame: &ffmpeg::frame::Audio, out: &mut Vec<f32>) {
    let n = frame.samples();
    if n == 0 {
        return;
    }
    let data = frame.data(0);
    let slice = unsafe { std::slice::from_raw_parts(data.as_ptr() as *const f32, n) };
    out.extend_from_slice(slice);
}

/// 解析声道布局：decoder 给的 layout 为 0 时，从流参数的声道数推断。
/// 逻辑同泛听 playback.rs 的 resolve_layout，保证两条解码路径一致。
fn resolve_layout(
    decoder: &ffmpeg::decoder::Audio,
    input: &ffmpeg::format::context::Input,
    stream_index: usize,
) -> ffmpeg::channel_layout::ChannelLayout {
    use ffmpeg::channel_layout::ChannelLayout;
    let layout = decoder.channel_layout();
    if layout.bits() != 0 {
        return layout;
    }
    let ch: u32 = unsafe {
        let stream = input.stream(stream_index).unwrap();
        let par = stream.parameters().as_ptr();
        let nb = (*par).ch_layout.nb_channels;
        if nb > 0 {
            nb as u32
        } else {
            0
        }
    };
    match ch {
        1 => ChannelLayout::MONO,
        3 => ChannelLayout::SURROUND,
        4 => ChannelLayout::_4POINT0,
        5 => ChannelLayout::_5POINT0,
        6 => ChannelLayout::_5POINT1,
        7 => ChannelLayout::_6POINT1,
        8 => ChannelLayout::_7POINT1,
        _ => ChannelLayout::STEREO,
    }
}
