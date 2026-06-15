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
  text: string;
}

export interface Label {
  id: string;
  start: number;
  end: number;
  text: string;
}

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
