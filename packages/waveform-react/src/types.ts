export interface AudioInfo {
  duration: number;
  sampleRate: number;
  levelCount: number;
  channelCount: number;
}

export type RenderMode = "envelope" | "polyline" | "stem";

export interface Peak {
  min: number;
  max: number;
  rms: number;
}

export type ChannelData =
  | { kind: "envelope"; peaks: Peak[] }
  | { kind: "polyline"; points: Array<[number, number]> }
  | { kind: "stem"; points: Array<[number, number]> };

export interface RenderData {
  mode: RenderMode;
  channels: ChannelData[];
  pixelWidth: number;
}

export interface ViewRange {
  startSec: number;
  endSec: number;
}

export type LoadingState = "idle" | "decoding" | "ready" | "error";
export type ChannelMode = "auto" | "mono" | "stereo" | "preserve";

export interface WaveformOpenOptions {
  sampleRate?: number;
  channelMode?: ChannelMode;
}

export interface WaveformSession {
  sessionId: number;
  metadata: AudioInfo;
}

export interface WaveformRegion {
  id: string;
  startSec: number;
  endSec: number;
  selected?: boolean;
  overlapping?: boolean;
}

export interface WaveformColors {
  wave: string;
  waveRms: string;
  playhead: string;
  regionFill: string;
  regionBorder: string;
  selection: string;
  background: string;
  centerLine?: string;
  channelDivider?: string;
}

export const DEFAULT_COLORS: WaveformColors = {
  wave: "#2C4A8C",
  waveRms: "#2C4A8C",
  playhead: "#1F2937",
  regionFill: "#BFDBFE",
  regionBorder: "#3B82F6",
  selection: "#FDE68A",
  background: "#F0F2F8",
  centerLine: "#1F2937",
  channelDivider: "#1F2937",
};

export interface GlResources {
  gl: WebGL2RenderingContext;
  program: WebGLProgram;
  vao: WebGLVertexArrayObject;
  vbo: WebGLBuffer;
}
