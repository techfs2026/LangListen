import type {
  RenderData,
  ViewRange,
  WaveformOpenOptions,
  WaveformSession,
} from "./types";

export interface WaveformBackend {
  open(path: string, options?: WaveformOpenOptions): Promise<WaveformSession>;
  query(sessionId: number, view: ViewRange, pixelWidth: number): Promise<RenderData>;
  close(sessionId: number): Promise<void>;
}
