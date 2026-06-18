//! AtempoFilter：FFmpeg filter graph 封装，变速不变调。
//!
//! 输入：解码器输出的 PCM 帧（任意采样率/布局/格式）。
//! 输出：变速后的 PCM 帧（mono / fltp / 指定输出采样率，样本数可能不同）。
//!
//! rate=1.0 时 atempo 仍然存在，但近似透明（轻微的 phase vocoder 处理开销）。
//! 为了 1.0 时绝对零开销，可以加一个 bypass 分支，但当前实现简单一致。

use anyhow::{anyhow, Context, Result};
use ffmpeg_next as ffmpeg;

pub struct AtempoFilter {
    graph: ffmpeg::filter::Graph,
}

impl AtempoFilter {
    pub fn new(
        src_format: ffmpeg::format::Sample,
        src_layout: ffmpeg::channel_layout::ChannelLayout,
        src_rate: u32,
        speed: f32,
    ) -> Result<Self> {
        Self::new_with_output_rate(src_format, src_layout, src_rate, src_rate, speed)
    }

    pub fn new_with_output_rate(
        src_format: ffmpeg::format::Sample,
        src_layout: ffmpeg::channel_layout::ChannelLayout,
        src_rate: u32,
        out_rate: u32,
        speed: f32,
    ) -> Result<Self> {
        // atempo 单段 0.5~100，我们的 [0.5, 1.75] 完全覆盖，不需要级联
        let speed = speed.clamp(0.5, 100.0);

        let mut graph = ffmpeg::filter::Graph::new();

        let in_args = format!(
            "time_base=1/{rate}:sample_rate={rate}:sample_fmt={fmt}:channel_layout=0x{layout:x}",
            rate = src_rate,
            fmt = sample_fmt_name(src_format),
            layout = src_layout.bits(),
        );

        graph
            .add(
                &ffmpeg::filter::find("abuffer").ok_or_else(|| anyhow!("abuffer not found"))?,
                "in",
                &in_args,
            )
            .with_context(|| format!("add abuffer: {in_args}"))?;

        graph
            .add(
                &ffmpeg::filter::find("abuffersink")
                    .ok_or_else(|| anyhow!("abuffersink not found"))?,
                "out",
                "",
            )
            .context("add abuffersink")?;

        // 拼接：in → atempo=rate=X → 降混为单声道 fltp（并重采样到输出采样率）→ out
        // aformat 里把 channel_layouts 定为 mono，让滤镜图自动插入降混，
        // 这样输出帧就是 mono/fltp/输出采样率，可直接送入 cpal。
        let spec = format!(
            "[in]atempo={speed},aformat=sample_fmts=fltp:sample_rates={rate}:channel_layouts=0x{mono:x}[out]",
            speed = speed,
            rate = out_rate,
            mono = ffmpeg::channel_layout::ChannelLayout::MONO.bits(),
        );
        graph.output("in", 0)?.input("out", 0)?.parse(&spec)?;
        graph.validate().context("filter graph validate")?;

        Ok(Self { graph })
    }

    pub fn send(&mut self, frame: &ffmpeg::frame::Audio) -> Result<()> {
        self.graph
            .get("in")
            .ok_or_else(|| anyhow!("in not found"))?
            .source()
            .add(frame)
            .map_err(|e| anyhow!("atempo add: {e}"))
    }

    pub fn send_eof(&mut self) -> Result<()> {
        // 通过给 source filter 发空帧（None）触发 EOF flush
        self.graph
            .get("in")
            .ok_or_else(|| anyhow!("in not found"))?
            .source()
            .flush()
            .map_err(|e| anyhow!("atempo flush: {e}"))
    }

    /// 返回 true 表示成功取到一帧，false 表示需要更多输入（EAGAIN）
    pub fn receive(&mut self, frame: &mut ffmpeg::frame::Audio) -> Result<bool> {
        match self
            .graph
            .get("out")
            .ok_or_else(|| anyhow!("out not found"))?
            .sink()
            .frame(frame)
        {
            Ok(_) => Ok(true),
            Err(ffmpeg::Error::Other { errno }) if errno == ffmpeg::error::EAGAIN => Ok(false),
            Err(ffmpeg::Error::Eof) => Ok(false),
            Err(e) => Err(anyhow!("atempo receive: {e}")),
        }
    }
}

fn sample_fmt_name(fmt: ffmpeg::format::Sample) -> &'static str {
    use ffmpeg::format::sample::Type;
    use ffmpeg::format::Sample;
    match fmt {
        Sample::U8(Type::Packed) => "u8",
        Sample::U8(Type::Planar) => "u8p",
        Sample::I16(Type::Packed) => "s16",
        Sample::I16(Type::Planar) => "s16p",
        Sample::I32(Type::Packed) => "s32",
        Sample::I32(Type::Planar) => "s32p",
        Sample::F32(Type::Packed) => "flt",
        Sample::F32(Type::Planar) => "fltp",
        Sample::F64(Type::Packed) => "dbl",
        Sample::F64(Type::Planar) => "dblp",
        _ => "fltp",
    }
}
