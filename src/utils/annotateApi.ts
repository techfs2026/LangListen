import { invoke } from "@tauri-apps/api/core";
import type { Label, LabelData } from "@/types/waveform";

/** 保存标记文件(JSON 格式) */
export async function saveLabels(labels: Label[], path: string): Promise<void> {
  const data: LabelData[] = labels.map((l) => ({
    start: l.start,
    end: l.end,
    transcript: l.transcript,
    note: l.note,
    tags: l.tags,
  }));
  await invoke("save_labels", { labels: data, path });
}

/** 加载标记文件(JSON;旧版 Audacity txt 由后端迁移为 note) */
export async function loadLabels(path: string): Promise<Label[]> {
  const raw = await invoke<LabelData[]>("load_labels", { path });
  return raw.map((r) => ({
    id: crypto.randomUUID(),
    start: r.start,
    end: r.end,
    transcript: r.transcript ?? "",
    note: r.note ?? "",
    tags: r.tags ?? [],
    transcriptStatus: (r.transcript ?? "").trim() ? ("done" as const) : ("idle" as const),
  }));
}

/** 进入精听界面时后台预热 Whisper 模型 */
export async function preloadWhisper(model = "small"): Promise<void> {
  await invoke("preload_whisper", { model });
}

/** 框选片段后即时转写 [start, end] 区间,返回转写文本。jobId 用于取消(通常传 label id) */
export async function transcribeSegment(
  audioPath: string,
  start: number,
  end: number,
  jobId: string,
  model = "small",
): Promise<string> {
  return invoke<string>("transcribe_segment", { audioPath, start, end, jobId, model });
}

/** 中止某个在途转写任务(真正打断 Whisper 推理) */
export async function cancelTranscribeJob(jobId: string): Promise<void> {
  await invoke("cancel_transcribe", { jobId });
}

export async function exportListeningPack(
  audioPath: string,
  labels: LabelData[],
  outputPath: string,
  model = "small",
): Promise<void> {
  await invoke("export_listening_pack", {
    audioPath,
    labels,
    outputPath,
    model,
  });
}
