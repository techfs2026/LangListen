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
