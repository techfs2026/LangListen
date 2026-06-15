use std::path::Path;

use anyhow::{bail, Context, Result};
use ffmpeg::{codec, format, frame, media, software::resampling};
use ffmpeg_next as ffmpeg;

use crate::{AudioBuffer, AudioDecoder, ChannelMode, DecodeOptions};

#[derive(Debug, Clone, Copy, Default)]
pub struct FfmpegDecoder;

impl AudioDecoder for FfmpegDecoder {
    fn decode_file(&self, path: &Path, options: &DecodeOptions) -> Result<AudioBuffer> {
        if options.sample_rate == 0 {
            bail!("decode sample rate must be greater than zero");
        }
        ffmpeg::init().context("failed to initialize FFmpeg")?;

        let path_display = path.display();
        let mut input =
            format::input(path).with_context(|| format!("cannot open file: {path_display}"))?;
        let stream = input
            .streams()
            .best(media::Type::Audio)
            .context("no audio stream found")?;
        let stream_index = stream.index();
        let codec = codec::Context::from_parameters(stream.parameters())
            .context("cannot create codec context")?;
        let mut decoder = codec
            .decoder()
            .audio()
            .context("cannot open audio decoder")?;

        let source_layout = resolve_channel_layout(&decoder, &input, stream_index);
        let source_rate = decoder.rate();
        let source_channels = source_layout.channels() as usize;
        let target_layout = match options.channel_mode {
            ChannelMode::Auto if source_channels == 1 => {
                ffmpeg::channel_layout::ChannelLayout::MONO
            }
            ChannelMode::Auto => ffmpeg::channel_layout::ChannelLayout::STEREO,
            ChannelMode::Mono => ffmpeg::channel_layout::ChannelLayout::MONO,
            ChannelMode::Stereo => ffmpeg::channel_layout::ChannelLayout::STEREO,
            ChannelMode::Preserve if source_channels == 1 => {
                ffmpeg::channel_layout::ChannelLayout::MONO
            }
            ChannelMode::Preserve => source_layout,
        };
        let target_channels = target_layout.channels() as usize;

        let estimated = estimate_samples(&input, stream_index, options.sample_rate);
        let mut channels = (0..target_channels)
            .map(|_| Vec::with_capacity(estimated))
            .collect::<Vec<_>>();
        let mut decoded = frame::Audio::empty();
        let mut resampled = frame::Audio::empty();
        let mut resampler = None;

        for (stream, packet) in input.packets() {
            if stream.index() != stream_index {
                continue;
            }
            decoder.send_packet(&packet).ok();
            while decoder.receive_frame(&mut decoded).is_ok() {
                normalize_frame_metadata(&mut decoded, source_layout, source_rate);
                resample_frame(
                    &decoded,
                    &mut resampled,
                    &mut resampler,
                    target_layout,
                    options.sample_rate,
                    &mut channels,
                )?;
            }
        }

        decoder.send_eof().ok();
        while decoder.receive_frame(&mut decoded).is_ok() {
            normalize_frame_metadata(&mut decoded, source_layout, source_rate);
            resample_frame(
                &decoded,
                &mut resampled,
                &mut resampler,
                target_layout,
                options.sample_rate,
                &mut channels,
            )?;
        }
        if let Some(resampler) = resampler.as_mut() {
            while resampler.flush(&mut resampled).is_ok() {
                if resampled.samples() == 0 {
                    break;
                }
                append_planar(&resampled, &mut channels);
            }
        }

        AudioBuffer::new(channels, options.sample_rate)
    }
}

fn resample_frame(
    decoded: &frame::Audio,
    resampled: &mut frame::Audio,
    resampler: &mut Option<resampling::Context>,
    target_layout: ffmpeg::channel_layout::ChannelLayout,
    target_rate: u32,
    channels: &mut [Vec<f32>],
) -> Result<()> {
    let context = match resampler {
        Some(context) => context,
        None => resampler.insert(
            resampling::Context::get(
                decoded.format(),
                decoded.channel_layout(),
                decoded.rate(),
                ffmpeg::format::Sample::F32(ffmpeg::format::sample::Type::Planar),
                target_layout,
                target_rate,
            )
            .context("cannot create resampler")?,
        ),
    };
    context
        .run(decoded, resampled)
        .context("audio resampling failed")?;
    append_planar(resampled, channels);
    Ok(())
}

fn normalize_frame_metadata(
    frame: &mut frame::Audio,
    fallback_layout: ffmpeg::channel_layout::ChannelLayout,
    fallback_rate: u32,
) {
    if frame.channel_layout().bits() == 0 {
        frame.set_channel_layout(fallback_layout);
    }
    if frame.rate() == 0 {
        frame.set_rate(fallback_rate);
    }
}

fn estimate_samples(
    input: &format::context::Input,
    stream_index: usize,
    target_rate: u32,
) -> usize {
    let stream = input.stream(stream_index).expect("stream index is valid");
    let duration = stream.duration() as f64 * f64::from(stream.time_base());
    if duration > 0.0 {
        (duration * target_rate as f64 * 1.05) as usize
    } else {
        target_rate as usize * 60
    }
}

fn append_planar(frame: &frame::Audio, channels: &mut [Vec<f32>]) {
    let sample_count = frame.samples();
    if sample_count == 0 {
        return;
    }
    for (channel_index, channel) in channels.iter_mut().enumerate() {
        let data = frame.data(channel_index);
        let samples =
            unsafe { std::slice::from_raw_parts(data.as_ptr() as *const f32, sample_count) };
        channel.extend_from_slice(samples);
    }
}

fn resolve_channel_layout(
    decoder: &ffmpeg::decoder::Audio,
    input: &format::context::Input,
    stream_index: usize,
) -> ffmpeg::channel_layout::ChannelLayout {
    use ffmpeg::channel_layout::ChannelLayout;

    let layout = decoder.channel_layout();
    if layout.bits() != 0 {
        return layout;
    }

    let channels = unsafe {
        let stream = input.stream(stream_index).expect("stream index is valid");
        let parameters = stream.parameters().as_ptr();
        (*parameters).ch_layout.nb_channels.max(0) as u32
    };

    match channels {
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
