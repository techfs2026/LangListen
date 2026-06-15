//! Reusable waveform decoding, analysis, and viewport extraction.
//!
//! The waveform algorithm only depends on [`AudioBuffer`]. File decoding is
//! provided by pluggable [`AudioDecoder`] implementations, with FFmpeg enabled
//! by default through the `ffmpeg` Cargo feature.

mod audio;
mod builder;
mod extractor;
mod peak;
mod view;

#[cfg(feature = "ffmpeg")]
pub mod ffmpeg;

use std::path::Path;

use anyhow::{bail, Result};

pub use audio::{
    AudioBuffer, AudioDecoder, BuildOptions, ChannelMode, DecodeOptions, WaveformOptions,
};
pub use peak::Peak;
pub use view::{ChannelRenderData, RenderData, RenderMode, ViewRange};

use peak::WaveformSummary;

pub const MAX_QUERY_PIXEL_WIDTH: usize = 32_768;

/// An analyzed waveform containing raw samples and a multilevel peak pyramid.
pub struct Waveform {
    summary: WaveformSummary,
}

impl Waveform {
    /// Decode a local file with the default FFmpeg decoder and analyze it.
    #[cfg(feature = "ffmpeg")]
    pub fn open(path: impl AsRef<Path>, options: WaveformOptions) -> Result<Self> {
        Self::open_with_decoder(path, &ffmpeg::FfmpegDecoder, options)
    }

    /// Decode a local file with a caller-provided decoder and analyze it.
    pub fn open_with_decoder(
        path: impl AsRef<Path>,
        decoder: &dyn AudioDecoder,
        options: WaveformOptions,
    ) -> Result<Self> {
        let audio = decoder.decode_file(path.as_ref(), &options.decode)?;
        Ok(Self::from_audio_buffer(audio, options.build))
    }

    /// Analyze caller-provided planar floating-point PCM samples.
    pub fn from_audio_buffer(audio: AudioBuffer, options: BuildOptions) -> Self {
        Self {
            summary: builder::build_summary(audio, options),
        }
    }

    pub fn metadata(&self) -> WaveformMetadata {
        WaveformMetadata {
            duration_secs: self.summary.duration_secs(),
            sample_rate: self.summary.sample_rate,
            channel_count: self.summary.channel_count(),
            level_count: self.summary.level_count(),
        }
    }

    pub fn query(&self, view: ViewRange) -> Result<RenderData> {
        if !view.start_sec.is_finite() || !view.end_sec.is_finite() {
            bail!("waveform view times must be finite");
        }
        if view.end_sec <= view.start_sec {
            bail!("waveform view end_sec must be greater than start_sec");
        }
        if view.pixel_width == 0 || view.pixel_width > MAX_QUERY_PIXEL_WIDTH {
            bail!("pixel_width must be between 1 and {MAX_QUERY_PIXEL_WIDTH}");
        }
        Ok(extractor::extract(&self.summary, &view))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WaveformMetadata {
    pub duration_secs: f64,
    pub sample_rate: u32,
    pub channel_count: usize,
    pub level_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine_buffer(sample_rate: u32, seconds: f64, channels: usize) -> AudioBuffer {
        let len = (sample_rate as f64 * seconds) as usize;
        let samples = (0..len)
            .map(|i| {
                let phase = i as f32 / sample_rate as f32 * std::f32::consts::TAU * 440.0;
                phase.sin()
            })
            .collect::<Vec<_>>();
        AudioBuffer::new(
            (0..channels).map(|_| samples.clone()).collect(),
            sample_rate,
        )
        .unwrap()
    }

    #[test]
    fn builds_metadata_from_pcm() {
        let waveform =
            Waveform::from_audio_buffer(sine_buffer(1_000, 2.0, 2), BuildOptions::default());
        let metadata = waveform.metadata();

        assert_eq!(metadata.sample_rate, 1_000);
        assert_eq!(metadata.channel_count, 2);
        assert!((metadata.duration_secs - 2.0).abs() < f64::EPSILON);
        assert!(metadata.level_count > 0);
    }

    #[test]
    fn selects_all_render_modes() {
        let waveform =
            Waveform::from_audio_buffer(sine_buffer(1_000, 10.0, 1), BuildOptions::default());

        let envelope = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 10.0,
                pixel_width: 100,
            })
            .unwrap();
        let polyline = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 0.1,
                pixel_width: 10,
            })
            .unwrap();
        let stem = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 0.001,
                pixel_width: 10,
            })
            .unwrap();

        assert_eq!(envelope.mode, RenderMode::Envelope);
        assert_eq!(polyline.mode, RenderMode::Polyline);
        assert_eq!(stem.mode, RenderMode::Stem);
    }

    #[test]
    fn limits_polyline_point_count() {
        let waveform =
            Waveform::from_audio_buffer(sine_buffer(48_000, 1.0, 1), BuildOptions::default());
        let width = 100;
        let frame = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 0.1,
                pixel_width: width,
            })
            .unwrap();

        let ChannelRenderData::Polyline(points) = &frame.channels[0] else {
            panic!("expected polyline mode");
        };
        assert!(points.len() <= width * 4 + 1);
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn opens_a_wave_file_with_default_decoder() {
        let path =
            std::env::temp_dir().join(format!("waveform-decoder-{}.wav", std::process::id()));
        std::fs::write(&path, test_wave_bytes()).unwrap();

        let waveform = Waveform::open(
            &path,
            WaveformOptions {
                decode: DecodeOptions {
                    sample_rate: 8_000,
                    channel_mode: ChannelMode::Mono,
                },
                build: BuildOptions::default(),
            },
        )
        .unwrap();
        let metadata = waveform.metadata();

        let _ = std::fs::remove_file(path);
        assert_eq!(metadata.sample_rate, 8_000);
        assert_eq!(metadata.channel_count, 1);
        assert!((metadata.duration_secs - 0.1).abs() < 0.001);
    }

    #[test]
    fn preserves_transient_peaks_when_polyline_is_reduced() {
        let mut samples = vec![0.0; 500];
        samples[123] = 1.0;
        samples[321] = -1.0;
        let waveform = Waveform::from_audio_buffer(
            AudioBuffer::new(vec![samples], 1_000).unwrap(),
            BuildOptions::default(),
        );
        let frame = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 0.5,
                pixel_width: 10,
            })
            .unwrap();
        let ChannelRenderData::Polyline(points) = &frame.channels[0] else {
            panic!("expected polyline mode");
        };

        assert!(points.iter().any(|&(_, value)| value == 1.0));
        assert!(points.iter().any(|&(_, value)| value == -1.0));
        assert!(points.len() <= 40);
    }

    #[test]
    fn envelope_includes_the_last_partial_block() {
        let mut samples = vec![0.0; 130];
        samples[129] = 1.0;
        let waveform = Waveform::from_audio_buffer(
            AudioBuffer::new(vec![samples], 100).unwrap(),
            BuildOptions {
                base_block_size: Some(64),
                upper_block_size: 8,
            },
        );
        let frame = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 1.3,
                pixel_width: 1,
            })
            .unwrap();
        let ChannelRenderData::Envelope(peaks) = &frame.channels[0] else {
            panic!("expected envelope mode");
        };

        assert_eq!(peaks[0].max, 1.0);
    }

    #[test]
    fn rms_uses_real_sample_counts_for_partial_blocks() {
        let waveform = Waveform::from_audio_buffer(
            AudioBuffer::new(vec![vec![1.0, 1.0, 1.0, 1.0, 0.0]], 5).unwrap(),
            BuildOptions {
                base_block_size: Some(4),
                upper_block_size: 2,
            },
        );
        let frame = waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 1.0,
                pixel_width: 1,
            })
            .unwrap();
        let ChannelRenderData::Envelope(peaks) = &frame.channels[0] else {
            panic!("expected envelope mode");
        };

        assert!((peaks[0].rms - (4.0_f32 / 5.0).sqrt()).abs() < 1e-6);
        assert_eq!(peaks[0].sample_count, 5);
    }

    #[test]
    fn rejects_invalid_or_excessive_queries() {
        let waveform =
            Waveform::from_audio_buffer(sine_buffer(1_000, 1.0, 1), BuildOptions::default());

        assert!(waveform
            .query(ViewRange {
                start_sec: f64::NAN,
                end_sec: 1.0,
                pixel_width: 100,
            })
            .is_err());
        assert!(waveform
            .query(ViewRange {
                start_sec: 0.0,
                end_sec: 1.0,
                pixel_width: MAX_QUERY_PIXEL_WIDTH + 1,
            })
            .is_err());
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn auto_channel_mode_keeps_mono_files_mono() {
        let path =
            std::env::temp_dir().join(format!("waveform-auto-mono-{}.wav", std::process::id()));
        std::fs::write(&path, test_wave_bytes()).unwrap();

        let waveform = Waveform::open(&path, WaveformOptions::default()).unwrap();
        let _ = std::fs::remove_file(path);

        assert_eq!(waveform.metadata().channel_count, 1);
    }

    #[cfg(feature = "ffmpeg")]
    fn test_wave_bytes() -> Vec<u8> {
        let sample_rate = 8_000u32;
        let samples = 800u32;
        let data_size = samples * 2;
        let mut bytes = Vec::with_capacity((44 + data_size) as usize);
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&(36 + data_size).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&sample_rate.to_le_bytes());
        bytes.extend_from_slice(&(sample_rate * 2).to_le_bytes());
        bytes.extend_from_slice(&2u16.to_le_bytes());
        bytes.extend_from_slice(&16u16.to_le_bytes());
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&data_size.to_le_bytes());
        for index in 0..samples {
            let phase = index as f32 / sample_rate as f32 * std::f32::consts::TAU * 440.0;
            let sample = (phase.sin() * i16::MAX as f32 * 0.25) as i16;
            bytes.extend_from_slice(&sample.to_le_bytes());
        }
        bytes
    }
}
