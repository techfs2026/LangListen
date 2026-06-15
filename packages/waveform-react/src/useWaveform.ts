import { useCallback, useEffect, useRef, useState } from "react";
import type { WaveformBackend } from "./backend";
import type {
  AudioInfo,
  LoadingState,
  RenderData,
  ViewRange,
  WaveformOpenOptions,
} from "./types";

export interface UseWaveformOptions {
  backend: WaveformBackend;
  minVisibleSeconds?: number;
  openOptions?: WaveformOpenOptions;
  initialView?: ViewRange;
}

export interface UseWaveformReturn {
  audioInfo: AudioInfo | null;
  loadingState: LoadingState;
  errorMessage: string;
  viewRange: ViewRange;
  loadFile: (path: string, initialView?: (duration: number) => ViewRange) => Promise<void>;
  close: () => Promise<void>;
  fetchPeaks: (pixelWidth: number) => Promise<RenderData | null>;
  setViewRange: (range: ViewRange) => void;
  zoomIn: (centerSec?: number) => void;
  zoomOut: (centerSec?: number) => void;
  zoomReset: () => void;
  scrollBy: (deltaSec: number) => void;
}

export function useWaveform({
  backend,
  minVisibleSeconds = 0.001,
  openOptions,
  initialView = { startSec: 0, endSec: 30 },
}: UseWaveformOptions): UseWaveformReturn {
  const [audioInfo, setAudioInfo] = useState<AudioInfo | null>(null);
  const [loadingState, setLoadingState] = useState<LoadingState>("idle");
  const [errorMessage, setErrorMessage] = useState("");
  const [viewRange, setViewRangeState] = useState<ViewRange>(initialView);
  const audioInfoRef = useRef<AudioInfo | null>(null);
  const sessionIdRef = useRef<number | null>(null);
  const sessionBackendRef = useRef<WaveformBackend | null>(null);
  const loadIdRef = useRef(0);
  const queryIdRef = useRef(0);

  const closeSession = useCallback(async () => {
    const sessionId = sessionIdRef.current;
    const sessionBackend = sessionBackendRef.current;
    sessionIdRef.current = null;
    sessionBackendRef.current = null;
    queryIdRef.current += 1;
    if (sessionId !== null && sessionBackend !== null) {
      await sessionBackend.close(sessionId).catch(() => {});
    }
  }, []);

  const close = useCallback(async () => {
    loadIdRef.current += 1;
    await closeSession();
    audioInfoRef.current = null;
    setAudioInfo(null);
    setErrorMessage("");
    setLoadingState("idle");
  }, [closeSession]);

  useEffect(() => {
    return () => {
      const sessionId = sessionIdRef.current;
      const sessionBackend = sessionBackendRef.current;
      sessionIdRef.current = null;
      sessionBackendRef.current = null;
      if (sessionId !== null && sessionBackend !== null) {
        void sessionBackend.close(sessionId).catch(() => {});
      }
    };
  }, []);

  const loadFile = useCallback(
    async (path: string, fitView?: (duration: number) => ViewRange) => {
      const loadId = ++loadIdRef.current;
      await closeSession();
      setLoadingState("decoding");
      setErrorMessage("");
      setAudioInfo(null);
      audioInfoRef.current = null;

      try {
        const session = await backend.open(path, openOptions);
        if (loadId !== loadIdRef.current) {
          await backend.close(session.sessionId).catch(() => {});
          return;
        }
        sessionIdRef.current = session.sessionId;
        sessionBackendRef.current = backend;
        audioInfoRef.current = session.metadata;
        setAudioInfo(session.metadata);

        const raw = fitView?.(session.metadata.duration) ?? {
          startSec: 0,
          endSec: session.metadata.duration,
        };
        const duration = Math.max(raw.endSec - raw.startSec, minVisibleSeconds);
        const start = Math.max(
          0,
          Math.min(raw.startSec, Math.max(0, session.metadata.duration - duration)),
        );
        setViewRangeState({
          startSec: start,
          endSec: Math.min(start + duration, session.metadata.duration),
        });
        setLoadingState("ready");
      } catch (error) {
        if (loadId !== loadIdRef.current) return;
        setErrorMessage(String(error));
        setLoadingState("error");
      }
    },
    [backend, closeSession, minVisibleSeconds, openOptions],
  );

  const fetchPeaks = useCallback(
    async (pixelWidth: number) => {
      const sessionId = sessionIdRef.current;
      const sessionBackend = sessionBackendRef.current;
      if (sessionId === null || sessionBackend === null) return null;
      const queryId = ++queryIdRef.current;
      const data = await sessionBackend.query(sessionId, viewRange, pixelWidth);
      if (queryId !== queryIdRef.current || sessionId !== sessionIdRef.current) return null;
      return data;
    },
    [viewRange],
  );

  const setViewRange = useCallback(
    (range: ViewRange) => {
      const total = audioInfoRef.current?.duration ?? Infinity;
      const duration = Math.max(range.endSec - range.startSec, minVisibleSeconds);
      const start = Math.max(0, Math.min(range.startSec, Math.max(0, total - duration)));
      setViewRangeState({ startSec: start, endSec: Math.min(start + duration, total) });
    },
    [minVisibleSeconds],
  );

  const zoomIn = useCallback(
    (centerSec?: number) => {
      setViewRangeState((previous) => {
        const duration = previous.endSec - previous.startSec;
        if (duration <= minVisibleSeconds) return previous;
        const center = centerSec ?? previous.startSec + duration * 0.5;
        const nextDuration = Math.max(duration * 0.6, minVisibleSeconds);
        const total = audioInfoRef.current?.duration ?? Infinity;
        const start = Math.max(
          0,
          Math.min(center - nextDuration * 0.5, Math.max(0, total - nextDuration)),
        );
        return { startSec: start, endSec: Math.min(start + nextDuration, total) };
      });
    },
    [minVisibleSeconds],
  );

  const zoomOut = useCallback((centerSec?: number) => {
    setViewRangeState((previous) => {
      const duration = previous.endSec - previous.startSec;
      const total = audioInfoRef.current?.duration ?? Infinity;
      if (duration >= total) return previous;
      const center = centerSec ?? previous.startSec + duration * 0.5;
      const nextDuration = Math.min(duration / 0.6, total);
      const start = Math.max(0, Math.min(center - nextDuration * 0.5, total - nextDuration));
      return { startSec: start, endSec: start + nextDuration };
    });
  }, []);

  const zoomReset = useCallback(() => {
    const duration = audioInfoRef.current?.duration;
    if (duration) setViewRangeState({ startSec: 0, endSec: duration });
  }, []);

  const scrollBy = useCallback((deltaSec: number) => {
    setViewRangeState((previous) => {
      const duration = previous.endSec - previous.startSec;
      const total = audioInfoRef.current?.duration ?? Infinity;
      const start = Math.max(
        0,
        Math.min(previous.startSec + deltaSec, Math.max(0, total - duration)),
      );
      return { startSec: start, endSec: start + duration };
    });
  }, []);

  return {
    audioInfo,
    loadingState,
    errorMessage,
    viewRange,
    loadFile,
    close,
    fetchPeaks,
    setViewRange,
    zoomIn,
    zoomOut,
    zoomReset,
    scrollBy,
  };
}
