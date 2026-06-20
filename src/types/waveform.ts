export type {
  AudioInfo,
  ChannelData,
  LoadingState,
  Peak,
  RenderData,
  RenderMode,
  ViewRange,
  WaveformColors,
} from "@owllisten/waveform-react";
export { DEFAULT_COLORS } from "@owllisten/waveform-react";

export interface LabelData {
  start: number;
  end: number;
  transcript: string;
  note: string;
  tags: string[];
}

/** 框选片段的转写状态（仅内存，不落盘） */
export type TranscriptStatus = "idle" | "loading" | "done" | "empty" | "error";

export interface Label {
  id: string;
  start: number;
  end: number;
  /** Whisper 转写文本，可编辑 */
  transcript: string;
  /** 用户备注 */
  note: string;
  /** 标签：没听懂 / 生词 / 连读 / 弱读 … */
  tags: string[];
  /** 即时转写状态 */
  transcriptStatus?: TranscriptStatus;
}

/** 备注标签预设 */
export const PRESET_TAGS = ["没听懂", "生词", "连读", "弱读", "失爆", "语速快"] as const;

export interface ListenSegment {
  index: number;
  /** ZIP 内的相对路径,e.g. "segments/0000.wav" */
  audio: string;
  start: number;
  end: number;
  /** Whisper 转写原文 */
  text: string;
  /** 标注时用户填写的备注 */
  label: string;
  /** 标签：没听懂 / 生词 / 连读 / 弱读 … */
  tags: string[];
}

export interface PackMetadata {
  version: number;
  segments: ListenSegment[];
}

export type SegmentStatus = "pending" | "done" | "flagged";

export interface SegmentState {
  status: SegmentStatus;
  /** 用户听写内容 */
  userText: string;
}
