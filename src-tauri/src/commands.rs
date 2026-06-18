use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::State;

use crate::audiobook::remove_recent_book;
use crate::audiobook::{get_progress, set_progress, BookProgress};
use crate::audiobook::{get_recent_books, push_recent_book, RecentBook};
use crate::audiobook::{parse_audiobook, AudiobookMeta};

use tauri::Manager;
use tauri::{AppHandle, Emitter};

// ── AppState ──────────────────────────────────────────────────────────────────

pub struct AppState {
    pub whisper_ctx: Mutex<Option<(String, whisper_rs::WhisperContext)>>,
    /// 有声书播放引擎（最多一个活跃）
    pub playback: Mutex<Option<crate::audiobook::PlaybackEngine>>,
    /// 精听播放引擎（内存 buffer 路径，最多一个活跃）
    pub practice: Mutex<Option<crate::practice::PracticePlayer>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            whisper_ctx: Mutex::new(None),
            playback: Mutex::new(None),
            practice: Mutex::new(None),
        }
    }
}

// ── 数据类型 ──────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LabelDto {
    pub start: f64,
    pub end: f64,
    pub text: String,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ExportProgressDto {
    pub step: String,
    pub transcribed: usize,
    pub total: usize,
    pub output_path: Option<String>,
    pub error_msg: Option<String>,
}

// ── 已有命令 ──────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn save_labels(labels: Vec<LabelDto>, path: String) -> Result<(), String> {
    use std::io::Write;
    let mut f = std::fs::File::create(&path).map_err(|e| e.to_string())?;
    let mut sorted = labels;
    sorted.sort_by(|a, b| a.start.total_cmp(&b.start));
    for l in &sorted {
        let text = sanitize_label_text(&l.text);
        writeln!(f, "{:.6}\t{:.6}\t{}", l.start, l.end, text).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn load_labels(path: String) -> Result<Vec<LabelDto>, String> {
    let content = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let mut labels = Vec::new();
    for line in content.lines() {
        let parts: Vec<&str> = line.splitn(3, '\t').collect();
        if parts.len() >= 2 {
            let start: f64 = parts[0].trim().parse().unwrap_or(0.0);
            let end: f64 = parts[1].trim().parse().unwrap_or(0.0);
            let text = parts.get(2).unwrap_or(&"").trim().to_string();
            if end - start >= 0.05 {
                labels.push(LabelDto { start, end, text });
            }
        }
    }
    labels.sort_by(|a, b| a.start.total_cmp(&b.start));
    Ok(labels)
}

fn sanitize_label_text(text: &str) -> String {
    text.replace(['\t', '\r', '\n'], " ")
}

fn split_audio(
    audio_path: String,
    labels: Vec<LabelDto>,
    output_dir: String,
) -> Result<Vec<String>, String> {
    let out_dir = Path::new(&output_dir);
    if out_dir.exists() {
        std::fs::remove_dir_all(out_dir).map_err(|e| e.to_string())?;
    }
    std::fs::create_dir_all(out_dir).map_err(|e| e.to_string())?;

    let target_sr: u32 = 16000;
    let audio = crate::audio::decode_audio(&audio_path, target_sr)
        .map_err(|e| format!("decode {audio_path}: {e}"))?;
    let sr = audio.sample_rate() as f64;
    let mono = downmix_to_mono(&audio);
    let total = mono.len();

    let mut segment_paths = Vec::with_capacity(labels.len());

    for (i, label) in labels.iter().enumerate() {
        let out_path = out_dir.join(format!("{:04}.mp3", i));
        let start_sample = ((label.start * sr).round() as usize).min(total);
        let end_sample = ((label.end * sr).round() as usize)
            .min(total)
            .max(start_sample);

        let slice = &mono[start_sample..end_sample];
        write_mp3(&out_path, slice, target_sr).map_err(|e| format!("Segment {i}: {e}"))?;
        segment_paths.push(out_path.to_string_lossy().into_owned());
    }

    Ok(segment_paths)
}

fn downmix_to_mono(audio: &crate::audio::DecodedAudio) -> Vec<f32> {
    let channels = audio.channel_count();
    if channels == 1 {
        return audio.channel(0).expect("ch 0").to_vec();
    }
    let len = audio.samples_per_channel();
    let mut out = Vec::with_capacity(len);
    let inv = 1.0 / channels as f32;
    for i in 0..len {
        let mut sum = 0.0_f32;
        for ch in 0..channels {
            sum += audio.channel(ch).expect("ch in range")[i];
        }
        out.push(sum * inv);
    }
    out
}

fn write_mp3(path: &Path, samples: &[f32], sample_rate: u32) -> anyhow::Result<()> {
    use anyhow::Context;
    use ffmpeg::format::sample::Type as SampleType;
    use ffmpeg::format::Sample;
    use ffmpeg::util::frame::audio::Audio as AudioFrame;
    use ffmpeg::ChannelLayout;
    use ffmpeg_next as ffmpeg;

    ffmpeg::init().context("FFmpeg init")?;

    let mut output =
        ffmpeg::format::output(path).with_context(|| format!("open output {}", path.display()))?;

    let codec = ffmpeg::encoder::find(ffmpeg::codec::Id::MP3)
        .ok_or_else(|| anyhow::anyhow!("MP3 encoder not found"))?;

    let mut encoder = ffmpeg::codec::context::Context::new_with_codec(codec)
        .encoder()
        .audio()
        .context("create audio encoder")?;

    encoder.set_rate(sample_rate as i32);
    encoder.set_format(Sample::F32(SampleType::Packed));
    encoder.set_channel_layout(ChannelLayout::MONO); // 隐式推断 channels = 1
    encoder.set_bit_rate(128_000);

    let mut encoder = encoder.open_as(codec).context("open encoder")?;

    // stream 只用于 set_parameters + 取 time_base，块作用域结束后立即 drop，
    // 避免与后续 output.write_header / write_interleaved 产生借用冲突
    let stream_time_base = {
        let mut stream = output.add_stream(codec).context("add stream")?;
        stream.set_parameters(&encoder);
        stream.time_base()
    };

    output.write_header().context("write_header")?;

    let frame_size = encoder.frame_size() as usize;
    let time_base = ffmpeg::Rational::new(1, sample_rate as i32);
    let mut pts: i64 = 0;

    for chunk in samples.chunks(frame_size) {
        let mut frame = AudioFrame::new(
            Sample::F32(SampleType::Packed),
            chunk.len(),
            ChannelLayout::MONO,
        );
        frame.set_rate(sample_rate);
        frame.set_pts(Some(pts));

        let plane = frame.plane_mut::<f32>(0);
        plane[..chunk.len()].copy_from_slice(chunk);

        pts += chunk.len() as i64;

        encoder.send_frame(&frame).context("send_frame")?;
        loop {
            let mut packet = ffmpeg::Packet::empty();
            match encoder.receive_packet(&mut packet) {
                Ok(_) => {
                    packet.rescale_ts(time_base, stream_time_base);
                    packet.set_stream(0);
                    packet
                        .write_interleaved(&mut output)
                        .context("write_interleaved")?;
                }
                Err(ffmpeg::Error::Other {
                    errno: ffmpeg::error::EAGAIN,
                }) => break,
                Err(e) => return Err(anyhow::anyhow!(e)).context("receive_packet"),
            }
        }
    }

    encoder.send_eof().context("send_eof")?;
    loop {
        let mut packet = ffmpeg::Packet::empty();
        match encoder.receive_packet(&mut packet) {
            Ok(_) => {
                packet.rescale_ts(time_base, stream_time_base);
                packet.set_stream(0);
                packet
                    .write_interleaved(&mut output)
                    .context("write_interleaved")?;
            }
            Err(ffmpeg::Error::Eof) => break,
            Err(ffmpeg::Error::Other {
                errno: ffmpeg::error::EAGAIN,
            }) => break,
            Err(e) => return Err(anyhow::anyhow!(e)).context("receive_packet"),
        }
    }

    output.write_trailer().context("write_trailer")?;
    Ok(())
}

fn get_or_load_whisper_ctx<'a>(
    app: &AppHandle,
    state: &'a State<AppState>,
    model: &str,
) -> Result<std::sync::MutexGuard<'a, Option<(String, whisper_rs::WhisperContext)>>, String> {
    use whisper_rs::{WhisperContext, WhisperContextParameters};

    let mut guard = state.whisper_ctx.lock().unwrap();

    // 已经加载且型号匹配 → 直接返回
    let needs_load = match &*guard {
        Some((cached_model, _)) if cached_model == model => false,
        _ => true,
    };

    if needs_load {
        let model_path = model_path_for(&app, model);
        if !model_path.exists() {
            return Err(format!(
                "Whisper 模型不存在：{}\n（模型随应用打包在 Resources/whisper-models/，无需用户自行下载；开发环境请将 ggml-{}.en.bin 放入 src-tauri/whisper-models/）",
                model_path.display(),
                model
            ));
        }

        log::info!(
            "Loading Whisper model: {} from {}",
            model,
            model_path.display()
        );
        let ctx = WhisperContext::new_with_params(
            model_path.to_str().ok_or("model path is not valid UTF-8")?,
            WhisperContextParameters::default(),
        )
        .map_err(|e| format!("Load whisper model: {e}"))?;

        *guard = Some((model.to_string(), ctx));
    }

    Ok(guard)
}

#[tauri::command]
pub fn transcribe_recording(
    app: AppHandle,
    audio_bytes: Vec<u8>,
    extension: String,
    model: Option<String>,
    state: State<AppState>,
) -> Result<String, String> {
    use std::io::Write;

    let model = model.unwrap_or_else(|| "small".to_string());

    if audio_bytes.is_empty() {
        return Err("Empty audio data".into());
    }

    // 1. 写到临时文件
    let dir = std::env::temp_dir().join("langlisten_recordings");
    std::fs::create_dir_all(&dir).map_err(|e| format!("create tmp dir: {e}"))?;

    // 用纳秒级时间戳避免并发冲突
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let safe_ext = extension.trim_start_matches('.').to_lowercase();
    let tmp_path = dir.join(format!("rec_{timestamp}.{safe_ext}"));

    {
        let mut f =
            std::fs::File::create(&tmp_path).map_err(|e| format!("create tmp file: {e}"))?;
        f.write_all(&audio_bytes)
            .map_err(|e| format!("write tmp file: {e}"))?;
    }

    // 2. 复用 transcribe_one（内部走 decode_audio + downmix_to_mono + Whisper）
    let result = {
        let guard = get_or_load_whisper_ctx(&app, &state, &model)?;
        let (_, ctx) = guard.as_ref().expect("ctx is loaded");
        transcribe_one(ctx, tmp_path.to_str().ok_or("tmp path not utf-8")?)
            .map_err(|e| format!("transcribe: {e}"))
    };

    // 3. 删除临时文件（不影响主流程，失败仅记日志）
    if let Err(e) = std::fs::remove_file(&tmp_path) {
        log::warn!("Remove tmp recording {} failed: {}", tmp_path.display(), e);
    }

    result
}

fn model_path_for(app: &AppHandle, model: &str) -> PathBuf {
    // 1. bundle 后：<app>.app/Contents/Resources/whisper-models/
    //    dev 模式：tauri.conf.json 里配置的 resourceDir（通常是项目根）
    let resource_base = app
        .path()
        .resource_dir()
        .ok()
        .map(|p| p.join("whisper-models"))
        .filter(|p| p.exists());

    // 2. dev 回退：可执行文件往上两级找（兼容 target/debug/xxx）
    let dev_base = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(PathBuf::from))
        .map(|exe_dir| exe_dir.join("../../whisper-models"))
        .filter(|p| p.exists());

    let base_dir = resource_base
        .or(dev_base)
        .unwrap_or_else(|| PathBuf::from("whisper-models"));

    base_dir.join(format!("ggml-{model}.en.bin"))
}

fn transcribe_one(ctx: &whisper_rs::WhisperContext, wav_path: &str) -> anyhow::Result<String> {
    use anyhow::Context;
    use whisper_rs::{FullParams, SamplingStrategy};

    let audio = crate::audio::decode_audio(wav_path, 16000)
        .with_context(|| format!("decode {wav_path}"))?;
    let samples = downmix_to_mono(&audio);

    let mut state = ctx.create_state().context("create state")?;
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_language(Some("en"));
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);

    state.full(params, &samples).context("whisper full")?;

    let n_segs = state.full_n_segments();
    let mut text = String::new();
    for i in 0..n_segs {
        if let Some(seg) = state.get_segment(i) {
            text.push_str(seg.to_str_lossy().unwrap_or_default().trim());
            text.push(' ');
        }
    }

    Ok(text.trim().to_string())
}

#[derive(Serialize)]
struct MetadataSegment {
    index: usize,
    audio: String,
    start: f64,
    end: f64,
    text: String,
    label: String,
}

#[derive(Serialize)]
struct Metadata {
    version: u32,
    segments: Vec<MetadataSegment>,
}

fn build_zip(
    segment_paths: Vec<String>,
    labels: Vec<LabelDto>,
    transcriptions: Vec<String>,
    output_path: String,
) -> Result<(), String> {
    use std::io::{Read, Write};
    use zip::{write::FileOptions, CompressionMethod, ZipWriter};

    let file = std::fs::File::create(&output_path).map_err(|e| e.to_string())?;
    let mut zip = ZipWriter::new(file);
    let opts: FileOptions<()> = FileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .unix_permissions(0o644);

    let segments: Vec<MetadataSegment> = segment_paths
        .iter()
        .enumerate()
        .map(|(i, _)| MetadataSegment {
            index: i,
            audio: format!("segments/{:04}.mp3", i),
            start: labels.get(i).map(|l| l.start).unwrap_or(0.0),
            end: labels.get(i).map(|l| l.end).unwrap_or(0.0),
            text: transcriptions.get(i).cloned().unwrap_or_default(),
            label: labels.get(i).map(|l| l.text.clone()).unwrap_or_default(),
        })
        .collect();

    let metadata = Metadata {
        version: 1,
        segments,
    };
    let json = serde_json::to_string_pretty(&metadata).map_err(|e| e.to_string())?;

    zip.start_file("metadata.json", opts)
        .map_err(|e| e.to_string())?;
    zip.write_all(json.as_bytes()).map_err(|e| e.to_string())?;

    for (i, seg_path) in segment_paths.iter().enumerate() {
        let file_name = format!("segments/{:04}.mp3", i);
        zip.start_file(&file_name, opts)
            .map_err(|e| e.to_string())?;

        let mut seg_file =
            std::fs::File::open(seg_path).map_err(|e| format!("Open segment {seg_path}: {e}"))?;
        let mut buf = Vec::new();
        seg_file.read_to_end(&mut buf).map_err(|e| e.to_string())?;
        zip.write_all(&buf).map_err(|e| e.to_string())?;
    }

    zip.finish().map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn export_listening_pack(
    app: AppHandle,
    state: State<AppState>,
    audio_path: String,
    labels: Vec<LabelDto>,
    output_path: String,
    model: Option<String>,
) -> Result<(), String> {
    let export_labels = normalized_export_labels(labels)?;
    let total = export_labels.len();
    let model = model.unwrap_or_else(|| "small".to_string());
    let workspace = unique_export_workspace()?;
    let segments_dir = workspace.join("segments");
    let cleanup_workspace = workspace.clone();

    let result: Result<(), String> = (|| {
        emit_export_progress(&app, "splitting", 0, total, None, None);

        let segment_paths = split_audio(
            audio_path,
            export_labels.clone(),
            segments_dir.to_string_lossy().into_owned(),
        )?;

        emit_export_progress(&app, "transcribing", 0, total, None, None);
        let transcriptions = {
            let guard = get_or_load_whisper_ctx(&app, &state, &model)?;
            let (_, ctx) = guard.as_ref().expect("ctx is loaded");
            let mut results = Vec::with_capacity(segment_paths.len());
            for (index, path) in segment_paths.iter().enumerate() {
                let text = transcribe_one(ctx, path).unwrap_or_else(|e| {
                    log::warn!("Transcribe {path} failed: {e}");
                    String::new()
                });
                results.push(text);
                emit_export_progress(&app, "transcribing", index + 1, total, None, None);
            }
            results
        };

        emit_export_progress(&app, "zipping", total, total, None, None);
        build_zip(
            segment_paths,
            export_labels,
            transcriptions,
            output_path.clone(),
        )?;
        emit_export_progress(&app, "done", total, total, Some(output_path), None);
        Ok(())
    })();

    if let Err(e) = std::fs::remove_dir_all(&cleanup_workspace) {
        log::warn!(
            "Remove export workspace {} failed: {}",
            cleanup_workspace.display(),
            e
        );
    }

    if let Err(error) = result {
        emit_export_progress(&app, "error", 0, total, None, Some(error.clone()));
        return Err(error);
    }

    Ok(())
}

fn normalized_export_labels(mut labels: Vec<LabelDto>) -> Result<Vec<LabelDto>, String> {
    labels.retain(|label| label.end - label.start >= 0.05);
    labels.sort_by(|a, b| a.start.total_cmp(&b.start));
    if labels.is_empty() {
        return Err("没有可导出的标记片段。".into());
    }
    Ok(labels)
}

fn unique_export_workspace() -> Result<PathBuf, String> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("owllisten-export-{timestamp}"));
    std::fs::create_dir_all(&dir).map_err(|e| format!("create export workspace: {e}"))?;
    Ok(dir)
}

fn emit_export_progress(
    app: &AppHandle,
    step: &str,
    transcribed: usize,
    total: usize,
    output_path: Option<String>,
    error_msg: Option<String>,
) {
    let _ = app.emit(
        "listening-pack-export-progress",
        ExportProgressDto {
            step: step.to_string(),
            transcribed,
            total,
            output_path,
            error_msg,
        },
    );
}

#[tauri::command]
pub fn reveal_in_finder(path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .args(["-R", &path])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .args(["/select,", &path])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "linux")]
    {
        let parent = Path::new(&path)
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or(path);
        std::process::Command::new("xdg-open")
            .arg(&parent)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 解析有声书元数据（章节列表、书名、作者、时长）
#[tauri::command]
pub fn load_audiobook(path: String) -> Result<AudiobookMeta, String> {
    parse_audiobook(&path).map_err(|e| e.to_string())
}

/// 读取播放进度
#[tauri::command]
pub fn get_audiobook_progress(app: AppHandle, book_path: String) -> BookProgress {
    let dir = app_data_dir(&app);
    get_progress(&dir, &book_path)
}

/// 保存播放进度（每隔几秒调用一次即可）
#[tauri::command]
pub fn save_audiobook_progress(
    app: AppHandle,
    book_path: String,
    chapter_index: usize,
    position_sec: f64,
) -> Result<(), String> {
    let dir = app_data_dir(&app);
    set_progress(
        &dir,
        &book_path,
        BookProgress {
            chapter_index,
            position_sec,
        },
    )
    .map_err(|e| e.to_string())
}

/// 获取最近打开的有声书列表
#[tauri::command]
pub fn get_recent_audiobooks(app: AppHandle) -> Vec<RecentBook> {
    let dir = app_data_dir(&app);
    get_recent_books(&dir)
}

/// 将一本书推入最近列表（openBook 时调用）
#[tauri::command]
pub fn push_recent_audiobook(
    app: AppHandle,
    book_path: String,
    title: String,
    author: String,
) -> Result<(), String> {
    let dir = app_data_dir(&app);
    push_recent_book(&dir, &book_path, &title, &author).map_err(|e| e.to_string())
}

fn app_data_dir(app: &AppHandle) -> String {
    app.path()
        .app_data_dir()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string()
}

/// 提取有声书内嵌封面，返回 base64 编码的图片数据和 MIME 类型
/// 如果没有封面返回 None
#[tauri::command]
pub fn get_audiobook_cover(path: String) -> Option<CoverDto> {
    extract_cover(&path).ok().flatten()
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoverDto {
    pub data: String,      // base64
    pub mime_type: String, // "image/jpeg" | "image/png"
}

fn extract_cover(path: &str) -> anyhow::Result<Option<CoverDto>> {
    use anyhow::Context;
    use ffmpeg_next as ffmpeg;

    ffmpeg::init().context("FFmpeg init")?;
    let input = ffmpeg::format::input(&path).with_context(|| format!("Cannot open: {path}"))?;

    // 优先找 ATTACHED_PIC 标志的流，其次找任意 Video 流
    // 用 parameters().medium() 而不是 codec().medium()（新版 ffmpeg-next API）
    let stream_index = input
        .streams()
        .find(|s| {
            use ffmpeg_next::format::stream::disposition::Disposition;
            s.disposition().contains(Disposition::ATTACHED_PIC)
        })
        .or_else(|| {
            input
                .streams()
                .find(|s| s.parameters().medium() == ffmpeg_next::media::Type::Video)
        })
        .map(|s| s.index());

    let stream_index = match stream_index {
        Some(i) => i,
        None => return Ok(None),
    };

    // 重新打开文件读 packet（避免生命周期问题）
    let mut input2 =
        ffmpeg::format::input(&path).with_context(|| format!("Cannot reopen: {path}"))?;

    for (stream, packet) in input2.packets() {
        if stream.index() != stream_index {
            continue;
        }
        let data = match packet.data() {
            Some(d) if !d.is_empty() => d,
            _ => break,
        };

        // 判断图片格式：JPEG = FF D8 FF，PNG = 89 50 4E 47
        let mime_type = if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
            "image/jpeg"
        } else if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
            "image/png"
        } else {
            "image/jpeg" // 兜底
        };

        use base64::{engine::general_purpose::STANDARD, Engine as _};
        return Ok(Some(CoverDto {
            data: STANDARD.encode(data),
            mime_type: mime_type.to_string(),
        }));
    }

    Ok(None)
}

#[tauri::command]
pub fn remove_recent_audiobook(app: AppHandle, book_path: String) -> Result<(), String> {
    let dir = app_data_dir(&app);
    remove_recent_book(&dir, &book_path).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn playback_open(
    app: AppHandle,
    state: State<AppState>,
    path: String,
    chapter_index: usize,
    position_sec: f64,
) -> Result<(), String> {
    use crate::audiobook::{parse_audiobook, PlaybackEngine};

    let meta = parse_audiobook(&path).map_err(|e| e.to_string())?;
    let engine = PlaybackEngine::open(&path, meta.chapters, chapter_index, position_sec, app)
        .map_err(|e| e.to_string())?;

    let mut guard = state.playback.lock().unwrap();
    *guard = Some(engine); // 旧的自动 drop
    Ok(())
}

#[tauri::command]
pub fn playback_play(state: State<AppState>) -> Result<(), String> {
    let guard = state.playback.lock().unwrap();
    let engine = guard.as_ref().ok_or("no playback engine")?;
    engine.play().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn playback_pause(state: State<AppState>) -> Result<(), String> {
    let guard = state.playback.lock().unwrap();
    let engine = guard.as_ref().ok_or("no playback engine")?;
    engine.pause().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn playback_close(state: State<AppState>) -> Result<(), String> {
    let mut guard = state.playback.lock().unwrap();
    *guard = None;
    Ok(())
}

#[tauri::command]
pub fn playback_seek(
    state: State<AppState>,
    chapter_index: usize,
    position_sec: f64,
) -> Result<(), String> {
    let guard = state.playback.lock().unwrap();
    let engine = guard.as_ref().ok_or("no playback engine")?;
    engine
        .seek_in_chapter(chapter_index, position_sec)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn playback_set_speed(state: State<AppState>, speed: f32) -> Result<(), String> {
    let guard = state.playback.lock().unwrap();
    let engine = guard.as_ref().ok_or("no playback engine")?;
    engine.set_speed(speed).map_err(|e| e.to_string())
}

// ── 精听播放（内存 buffer 路径）─────────────────────────────────────────────────

#[tauri::command]
pub fn practice_open(app: AppHandle, state: State<AppState>, path: String) -> Result<f64, String> {
    use crate::practice::PracticePlayer;

    let engine = PracticePlayer::open(&path, app).map_err(|e| e.to_string())?;
    let duration = engine.duration_secs();

    let mut guard = state.practice.lock().unwrap();
    *guard = Some(engine); // 旧的自动 drop
    Ok(duration)
}

#[tauri::command]
pub fn practice_play(state: State<AppState>) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    engine.play().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn practice_pause(state: State<AppState>) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    engine.pause().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn practice_seek(state: State<AppState>, position_sec: f64) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    engine.seek(position_sec).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn practice_play_segment(
    state: State<AppState>,
    start_sec: f64,
    end_sec: f64,
) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    engine
        .play_segment(start_sec, end_sec)
        .map_err(|e| e.to_string())
}

/// 设置/清除 AB 循环：start_sec/end_sec 同时为 Some 时设置，否则清除。
#[tauri::command]
pub fn practice_set_loop(
    state: State<AppState>,
    start_sec: Option<f64>,
    end_sec: Option<f64>,
) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    let range = match (start_sec, end_sec) {
        (Some(a), Some(b)) => Some((a, b)),
        _ => None,
    };
    engine.set_loop(range).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn practice_set_speed(state: State<AppState>, speed: f32) -> Result<(), String> {
    let guard = state.practice.lock().unwrap();
    let engine = guard.as_ref().ok_or("no practice engine")?;
    engine.set_speed(speed).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn practice_close(state: State<AppState>) -> Result<(), String> {
    let mut guard = state.practice.lock().unwrap();
    *guard = None;
    Ok(())
}
