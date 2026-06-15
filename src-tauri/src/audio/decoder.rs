use anyhow::{Context, Result};
use ffmpeg_next as ffmpeg;
use ffmpeg_next::{codec, format, frame, media, software::resampling};
use std::sync::Arc;

#[derive(Debug)]
pub struct RawSamples {
    pub channels: Vec<Vec<f32>>,
    pub sample_rate: u32,
}

impl RawSamples {
    pub fn channel_count(&self) -> usize {
        self.channels.len()
    }
    pub fn total_samples_per_channel(&self) -> usize {
        self.channels.first().map(|c| c.len()).unwrap_or(0)
    }
}

pub struct DecodedAudio {
    pub raw: Arc<RawSamples>,
}

impl DecodedAudio {
    pub fn channel_count(&self) -> usize {
        self.raw.channel_count()
    }
    pub fn sample_rate(&self) -> u32 {
        self.raw.sample_rate
    }
    pub fn samples_per_channel(&self) -> usize {
        self.raw.total_samples_per_channel()
    }
    pub fn channel(&self, ch: usize) -> Option<&[f32]> {
        self.raw.channels.get(ch).map(|v| v.as_slice())
    }
}

pub fn decode_audio(path: &str, target_sample_rate: u32) -> Result<DecodedAudio> {
    ffmpeg::init().context("Failed to init FFmpeg")?;

    let mut input = format::input(&path).with_context(|| format!("Cannot open file: {path}"))?;

    let stream = input
        .streams()
        .best(media::Type::Audio)
        .context("No audio stream found")?;

    let stream_index = stream.index();
    let codec_params = stream.parameters();

    let codec =
        codec::Context::from_parameters(codec_params).context("Cannot create codec context")?;
    let mut decoder = codec
        .decoder()
        .audio()
        .context("Cannot open audio decoder")?;

    let src_format = decoder.format();
    let src_rate = decoder.rate();

    // channel_layout 三级优先：decoder → ffi codecpar → 声道数推断
    let (src_layout, src_channel_count) = resolve_channel_layout(&decoder, &input, stream_index);

    log::debug!(
        "decode_audio: codec={:?} fmt={:?} rate={} layout_bits={:#x} channels={}",
        decoder.id(),
        src_format,
        src_rate,
        src_layout.bits(),
        src_channel_count,
    );

    if src_channel_count == 0 {
        anyhow::bail!("Cannot determine channel count for: {path}");
    }

    let target_layout = if src_channel_count == 1 {
        ffmpeg::channel_layout::ChannelLayout::MONO
    } else {
        ffmpeg::channel_layout::ChannelLayout::STEREO
    };
    let target_channel_count = target_layout.channels() as usize;

    let mut resampler = resampling::Context::get(
        src_format,
        src_layout,
        src_rate,
        ffmpeg_next::format::Sample::F32(ffmpeg_next::format::sample::Type::Planar),
        target_layout,
        target_sample_rate,
    )
    .context("Cannot create resampler")?;

    let estimated = estimate_samples_per_channel(&input, stream_index, target_sample_rate);
    let mut channels: Vec<Vec<f32>> = (0..target_channel_count)
        .map(|_| Vec::with_capacity(estimated))
        .collect();

    let mut decoded_frame = frame::Audio::empty();
    let mut resampled_frame = frame::Audio::empty();

    for (stream, packet) in input.packets() {
        if stream.index() != stream_index {
            continue;
        }
        decoder.send_packet(&packet).ok();
        while decoder.receive_frame(&mut decoded_frame).is_ok() {
            resampler
                .run(&decoded_frame, &mut resampled_frame)
                .context("Resampling failed")?;
            append_planar_samples(&resampled_frame, &mut channels, target_channel_count);
        }
    }

    decoder.send_eof().ok();
    while decoder.receive_frame(&mut decoded_frame).is_ok() {
        resampler
            .run(&decoded_frame, &mut resampled_frame)
            .context("Resampling failed")?;
        append_planar_samples(&resampled_frame, &mut channels, target_channel_count);
    }

    while resampler.flush(&mut resampled_frame).is_ok() {
        if resampled_frame.samples() == 0 {
            break;
        }
        append_planar_samples(&resampled_frame, &mut channels, target_channel_count);
    }

    log::debug!(
        "Decoded: {} ch x {} samples ({:.2}s) @ {} Hz",
        channels.len(),
        channels.first().map(|c| c.len()).unwrap_or(0),
        channels.first().map(|c| c.len()).unwrap_or(0) as f64 / target_sample_rate as f64,
        target_sample_rate,
    );

    Ok(DecodedAudio {
        raw: Arc::new(RawSamples {
            channels,
            sample_rate: target_sample_rate,
        }),
    })
}

// ── channel layout 解析 ───────────────────────────────────────────────────────
//
// EAC3/Atmos 等格式：decoder.channel_layout() 返回 bits=0，
// 真实声道数存在 AVStream.codecpar.ch_layout.nb_channels（FFmpeg 5.1+）。

fn resolve_channel_layout(
    decoder: &ffmpeg::decoder::Audio,
    input: &format::context::Input,
    stream_index: usize,
) -> (ffmpeg::channel_layout::ChannelLayout, u32) {
    use ffmpeg::channel_layout::ChannelLayout;

    // 1. decoder 自带（AAC/MP3 通常有效）
    let layout = decoder.channel_layout();
    if layout.bits() != 0 {
        return (layout, layout.channels() as u32);
    }

    // 2. ffi 读 codecpar.ch_layout.nb_channels（i32，FFmpeg 5.1+）
    let ffi_channels: u32 = unsafe {
        let stream = input.stream(stream_index).expect("stream_index valid");
        let par = stream.parameters().as_ptr();
        let nb_ch = (*par).ch_layout.nb_channels; // i32
        if nb_ch > 0 {
            nb_ch as u32
        } else {
            0
        }
    };

    log::debug!("resolve_channel_layout via ffi: channels={}", ffi_channels);

    if ffi_channels > 0 {
        // ffmpeg-next 的 ChannelLayout 不支持从任意 u64 mask 构造，
        // 按声道数映射到最接近的标准 layout 即可（重采样器只需声道数正确）
        let resolved = match ffi_channels {
            1 => ChannelLayout::MONO,
            2 => ChannelLayout::STEREO,
            3 => ChannelLayout::SURROUND, // 3.0
            4 => ChannelLayout::_4POINT0,
            5 => ChannelLayout::_5POINT0,
            6 => ChannelLayout::_5POINT1, // EAC3 5.1 / Atmos base layer
            7 => ChannelLayout::_6POINT1,
            8 => ChannelLayout::_7POINT1,
            _ => ChannelLayout::STEREO,
        };
        return (resolved, ffi_channels);
    }

    // 3. 最终兜底
    log::warn!("Could not determine channel layout, assuming STEREO");
    (ChannelLayout::STEREO, 2)
}

// ── 私有辅助 ─────────────────────────────────────────────────────────────────

fn estimate_samples_per_channel(
    input: &format::context::Input,
    stream_index: usize,
    target_rate: u32,
) -> usize {
    let stream = input.stream(stream_index).unwrap();
    let duration = stream.duration() as f64 * f64::from(stream.time_base());
    if duration > 0.0 {
        (duration * target_rate as f64 * 1.05) as usize
    } else {
        target_rate as usize * 60
    }
}

fn append_planar_samples(
    frame: &frame::Audio,
    channels: &mut [Vec<f32>],
    expected_channels: usize,
) {
    let n = frame.samples();
    if n == 0 {
        return;
    }
    for ch in 0..expected_channels {
        let data = frame.data(ch);
        // SAFETY: planar f32，每 plane 是 n 个连续 f32
        let floats = unsafe { std::slice::from_raw_parts(data.as_ptr() as *const f32, n) };
        channels[ch].extend_from_slice(floats);
    }
}
