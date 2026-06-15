use super::peak::Peak;

/// 当前视图参数:时间区间 + 像素宽度
#[derive(Debug, Clone, Copy)]
pub struct ViewRange {
    pub start_sec: f64,
    pub end_sec: f64,
    pub pixel_width: usize,
}

impl ViewRange {
    pub fn duration(&self) -> f64 {
        self.end_sec - self.start_sec
    }

    /// 每个 pixel 对应多少个原始样本
    /// spp >= 1 → 包络模式;spp < 1 → 折线/采样点模式
    pub fn samples_per_pixel(&self, sample_rate: u32) -> f64 {
        self.duration() * sample_rate as f64 / self.pixel_width as f64
    }
}

/// 渲染模式:由 samples_per_pixel 和 base_block_size 共同决定
/// 模式选择逻辑由 extractor 内部完成,见 `extractor::extract`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RenderMode {
    /// spp >= base_block_size:从金字塔取 min/max + RMS,UI 画双层 bar
    Envelope,
    /// 1 <= spp < base_block_size:每个 pixel 多个样本,从原始样本取折线
    Polyline,
    /// spp < 1:折线 + 采样点圆点(stem plot),让用户看清离散采样点
    Stem,
}

/// 单声道渲染数据(三种模式之一)
#[derive(Debug, Clone)]
pub enum ChannelRenderData {
    /// 长度 == pixel_width
    Envelope(Vec<Peak>),
    /// 折线顶点序列:(x_pixel, sample_value)
    /// x_pixel 是浮点像素坐标,允许非整数(便于 UI 抗锯齿)
    Polyline(Vec<(f32, f32)>),
    /// 折线顶点 + 暗示 UI 在每个顶点画圆点
    /// 数据结构与 Polyline 相同,语义上要求 UI 额外画点
    Stem(Vec<(f32, f32)>),
}

impl ChannelRenderData {
    pub fn mode(&self) -> RenderMode {
        match self {
            ChannelRenderData::Envelope(_) => RenderMode::Envelope,
            ChannelRenderData::Polyline(_) => RenderMode::Polyline,
            ChannelRenderData::Stem(_) => RenderMode::Stem,
        }
    }
}

/// 多声道渲染数据
#[derive(Debug, Clone)]
pub struct RenderData {
    pub mode: RenderMode,
    /// 与 WaveformSummary.channels 顺序一致
    pub channels: Vec<ChannelRenderData>,
    /// 透传给 UI,便于布局时复算坐标
    pub view: ViewRange,
}
