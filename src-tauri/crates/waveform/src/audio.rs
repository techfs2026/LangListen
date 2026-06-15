use std::path::Path;
use std::sync::Arc;

use anyhow::{bail, Result};

#[derive(Debug, Clone)]
pub struct AudioBuffer {
    channels: Arc<Vec<Vec<f32>>>,
    sample_rate: u32,
}

impl AudioBuffer {
    pub fn new(channels: Vec<Vec<f32>>, sample_rate: u32) -> Result<Self> {
        if sample_rate == 0 {
            bail!("sample rate must be greater than zero");
        }
        if channels.is_empty() {
            bail!("audio buffer must contain at least one channel");
        }
        let sample_count = channels[0].len();
        if sample_count == 0 {
            bail!("audio buffer must contain samples");
        }
        if channels.iter().any(|channel| channel.len() != sample_count) {
            bail!("all audio channels must have the same sample count");
        }
        Ok(Self {
            channels: Arc::new(channels),
            sample_rate,
        })
    }

    pub fn channel(&self, index: usize) -> Option<&[f32]> {
        self.channels.get(index).map(Vec::as_slice)
    }

    pub fn channels(&self) -> &[Vec<f32>] {
        self.channels.as_slice()
    }

    pub fn channel_count(&self) -> usize {
        self.channels.len()
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn samples_per_channel(&self) -> usize {
        self.channels[0].len()
    }

    pub fn duration_secs(&self) -> f64 {
        self.samples_per_channel() as f64 / self.sample_rate as f64
    }
}

pub trait AudioDecoder: Send + Sync {
    fn decode_file(&self, path: &Path, options: &DecodeOptions) -> Result<AudioBuffer>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelMode {
    Auto,
    Mono,
    Stereo,
    Preserve,
}

#[derive(Debug, Clone, Copy)]
pub struct DecodeOptions {
    pub sample_rate: u32,
    pub channel_mode: ChannelMode,
}

impl Default for DecodeOptions {
    fn default() -> Self {
        Self {
            sample_rate: 22_050,
            channel_mode: ChannelMode::Auto,
        }
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct WaveformOptions {
    pub decode: DecodeOptions,
    pub build: BuildOptions,
}

#[derive(Debug, Clone, Copy)]
pub struct BuildOptions {
    /// Number of PCM samples represented by each level-0 peak. When omitted,
    /// the builder selects a value from the audio duration.
    pub base_block_size: Option<usize>,
    /// Number of lower-level peaks aggregated into each upper-level peak.
    pub upper_block_size: usize,
}

impl Default for BuildOptions {
    fn default() -> Self {
        Self {
            base_block_size: None,
            upper_block_size: 8,
        }
    }
}
