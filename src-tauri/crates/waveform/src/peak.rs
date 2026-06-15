use super::audio::AudioBuffer;

/// 一段样本区间内的统计:
/// - min/max: 振幅包络(峰值)
/// - rms:     均方根(响度/能量)
#[derive(Clone, Copy, Debug, Default)]
#[repr(C)]
pub struct Peak {
    pub min: f32,
    pub max: f32,
    pub rms: f32,
    pub sample_count: u64,
}

impl Peak {
    /// 用于"空区间"占位的零值 Peak
    #[inline]
    pub const fn zero() -> Self {
        Self {
            min: 0.0,
            max: 0.0,
            rms: 0.0,
            sample_count: 0,
        }
    }
}

/// 单个声道的多级峰值金字塔
/// levels[0] 最细,levels[n] 最粗(收敛到 1 个 Peak 时停止)
#[derive(Debug)]
pub struct ChannelPyramid {
    pub levels: Vec<Vec<Peak>>,
}

impl ChannelPyramid {
    pub fn level_count(&self) -> usize {
        self.levels.len()
    }
}

/// 多声道峰值金字塔总容器
#[derive(Debug)]
pub struct WaveformSummary {
    /// 每声道一棵金字塔
    pub channels: Vec<ChannelPyramid>,
    /// 原始样本(共享所有权,服务于放大态的 Polyline / Stem 渲染)
    pub audio: AudioBuffer,
    pub sample_rate: u32,
    pub total_samples: u64,
    pub base_block_size: usize,
    pub upper_block_size: usize,
}

impl WaveformSummary {
    pub fn duration_secs(&self) -> f64 {
        self.total_samples as f64 / self.sample_rate as f64
    }

    pub fn is_valid(&self) -> bool {
        !self.channels.is_empty()
            && self.channels.iter().all(|c| !c.levels.is_empty())
            && self.total_samples > 0
    }

    pub fn channel_count(&self) -> usize {
        self.channels.len()
    }

    /// 第 level 层每个 Peak 对应的样本数
    pub fn samples_per_entry(&self, level: usize) -> u64 {
        let mut count = self.base_block_size as u64;
        for _ in 0..level {
            count *= self.upper_block_size as u64;
        }
        count
    }

    /// 第一个声道的层数(所有声道层数相同)
    pub fn level_count(&self) -> usize {
        self.channels.first().map(|c| c.level_count()).unwrap_or(0)
    }
}
