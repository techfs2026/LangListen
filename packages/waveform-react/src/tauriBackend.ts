import { invoke } from "@tauri-apps/api/core";
import type { WaveformBackend } from "./backend";
import type {
  RenderData,
  ViewRange,
  WaveformOpenOptions,
  WaveformSession,
} from "./types";

export function createTauriWaveformBackend(): WaveformBackend {
  return {
    open(path: string, options?: WaveformOpenOptions): Promise<WaveformSession> {
      return invoke("waveform_open", {
        request: { path, options: options ?? null },
      });
    },

    query(sessionId: number, view: ViewRange, pixelWidth: number): Promise<RenderData> {
      return invoke("waveform_query", {
        request: {
          sessionId,
          view: {
            startSec: view.startSec,
            endSec: view.endSec,
            pixelWidth,
          },
        },
      });
    },

    close(sessionId: number): Promise<void> {
      return invoke("waveform_close", { sessionId });
    },
  };
}
