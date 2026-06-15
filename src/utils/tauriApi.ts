import { invoke } from "@tauri-apps/api/core";
import type { Label, LabelData } from "@/types/waveform";

/** 保存标记文件(Audacity 格式) */
export async function saveLabels(labels: Label[], path: string): Promise<void> {
  const data: LabelData[] = labels.map((l) => ({
    start: l.start,
    end: l.end,
    text: l.text,
  }));
  await invoke("save_labels", { labels: data, path });
}

/** 加载标记文件 */
export async function loadLabels(path: string): Promise<Label[]> {
  const raw = await invoke<LabelData[]>("load_labels", { path });
  return raw.map((r, i) => ({
    id: crypto.randomUUID(),
    start: r.start,
    end: r.end,
    text: r.text ?? `段落 ${i + 1}`,
  }));
}

export interface ExportOptions {
  /** 源音频文件路径 */
  audioPath: string;
  /** 标记列表 */
  labels: LabelData[];
  /** 导出 ZIP 保存路径 */
  outputPath: string;
  /** Whisper 模型大小,默认 "small" */
  whisperModel?: string;
}

export interface TranscribeProgressEvent {
  transcribed: number;
  total: number;
}

/**
 * 切割音频片段
 * 返回切割出的片段文件路径列表(临时目录)
 */
export async function splitAudio(
  audioPath: string,
  labels: LabelData[],
  outputDir: string,
): Promise<string[]> {
  return await invoke<string[]>("split_audio", {
    audioPath,
    labels,
    outputDir,
  });
}

/**
 * 对已切割的片段运行 Whisper 转写
 * 返回转写文本列表(与 segmentPaths 一一对应)
 */
export async function transcribeSegments(
  segmentPaths: string[],
  model: string = "small",
): Promise<string[]> {
  return await invoke<string[]>("transcribe_segments", {
    segmentPaths,
    model,
  });
}

/**
 * 打包:将片段、metadata.json 压缩为 ZIP
 */
export async function buildZip(
  segmentPaths: string[],
  labels: LabelData[],
  transcriptions: string[],
  outputPath: string,
): Promise<void> {
  await invoke("build_zip", {
    segmentPaths,
    labels,
    transcriptions,
    outputPath,
  });
}

export async function getTempDir(): Promise<string> {
  return await invoke<string>("get_temp_dir");
}
