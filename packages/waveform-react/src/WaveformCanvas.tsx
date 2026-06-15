import { useEffect, useRef, useCallback, useState } from "react";
import { useWebGL } from "./useWebGL";
import type { RenderData, ViewRange, WaveformColors, WaveformRegion } from "./types";
import { DEFAULT_COLORS } from "./types";

export interface WaveformCanvasProps {
  data: RenderData | null;
  viewRange: ViewRange;
  duration: number;
  playhead: number;
  /**
   * playhead 对应的墙钟时刻（performance.now 域，毫秒）。进度事件经时钟对齐扣除
   * 传输延迟后给出，以此为锚点外推可消除事件滞后；缺省/≤0 时退回当下时刻。
   */
  playheadWallMs?: number;
  /** 是否正在播放：决定播放头是否按速度逐帧平滑外推 */
  playing?: boolean;
  /** 当前播放速度，用于帧间外推播放头位置 */
  speed?: number;
  regions?: WaveformRegion[];
  colors?: Partial<WaveformColors>;
  loopRange?: [number, number] | null;
  onSeek: (sec: number) => void;
  onRegionSelected: (start: number, end: number) => void;
  onZoom: (delta: number, centerSec: number) => void;
  onScroll: (deltaSec: number) => void;
  onRegionEdgeDrag?: (id: string, edge: "start" | "end", newSec: number) => void;
}

const DRAG_THRESHOLD_PX = 6;
/** Region edge hit-test tolerance in CSS pixels. */
const EDGE_HIT_PX = 8;

type PointerMode =
  | { kind: "idle" }
  | { kind: "maybe-seek"; startX: number; startSec: number }
  | { kind: "region-drag"; startSec: number; currentSec: number }
  | { kind: "region-edge"; id: string; edge: "start" | "end" };

export function WaveformCanvas({
  data,
  viewRange,
  duration,
  playhead,
  playheadWallMs,
  playing = false,
  speed = 1,
  regions = [],
  colors: colorOverrides,
  loopRange,
  onSeek,
  onRegionSelected,
  onZoom,
  onScroll,
  onRegionEdgeDrag,
}: WaveformCanvasProps) {
  const { canvasRef, render } = useWebGL();
  const colors = { ...DEFAULT_COLORS, ...colorOverrides };

  const modeRef = useRef<PointerMode>({ kind: "idle" });
  const [dragDisplay, setDragDisplay] = useState<[number, number] | null>(null);
  const [cursor, setCursor] = useState<string>("crosshair");

  // ── 坐标转换 ──────────────────────────────────────────────────────────────

  const xToSec = useCallback(
    (x: number): number => {
      const canvas = canvasRef.current;
      if (!canvas) return 0;
      const rect = canvas.getBoundingClientRect();
      const ratio = (x - rect.left) / rect.width;
      return viewRange.startSec + ratio * (viewRange.endSec - viewRange.startSec);
    },
    [canvasRef, viewRange],
  );

  const secToRatio = useCallback(
    (sec: number): number => {
      const dur = viewRange.endSec - viewRange.startSec;
      if (dur <= 0) return 0;
      return (sec - viewRange.startSec) / dur;
    },
    [viewRange],
  );

  const secToPx = useCallback(
    (sec: number): number => {
      const canvas = canvasRef.current;
      if (!canvas) return 0;
      const rect = canvas.getBoundingClientRect();
      return rect.left + secToRatio(sec) * rect.width;
    },
    [canvasRef, secToRatio],
  );

  // ── 边缘 hit-test ──────────────────────────────────────────────────────────

  const hitTestEdge = useCallback(
    (clientX: number): { id: string; edge: "start" | "end" } | null => {
      for (const region of regions) {
        const startPx = secToPx(region.startSec);
        const endPx = secToPx(region.endSec);
        if (Math.abs(clientX - endPx) <= EDGE_HIT_PX) {
          return { id: region.id, edge: "end" };
        }
        if (Math.abs(clientX - startPx) <= EDGE_HIT_PX) {
          return { id: region.id, edge: "start" };
        }
      }
      return null;
    },
    [regions, secToPx],
  );

  // ── 鼠标事件 ──────────────────────────────────────────────────────────────

  const handleMouseDown = useCallback(
    (e: React.PointerEvent<HTMLCanvasElement>) => {
      if (e.button !== 0) return;
      e.currentTarget.setPointerCapture(e.pointerId);

      const hit = hitTestEdge(e.clientX);
      if (hit) {
        modeRef.current = { kind: "region-edge", id: hit.id, edge: hit.edge };
        setCursor("col-resize");
        return;
      }

      const sec = xToSec(e.clientX);
      modeRef.current = { kind: "maybe-seek", startX: e.clientX, startSec: sec };
    },
    [xToSec, hitTestEdge],
  );

  const handleMouseMove = useCallback(
    (e: React.PointerEvent<HTMLCanvasElement>) => {
      const mode = modeRef.current;

      if (mode.kind === "region-edge") {
        const sec = xToSec(e.clientX);
        onRegionEdgeDrag?.(mode.id, mode.edge, sec);
        return;
      }

      if (mode.kind === "maybe-seek") {
        const dx = Math.abs(e.clientX - mode.startX);
        if (dx >= DRAG_THRESHOLD_PX) {
          const sec = xToSec(e.clientX);
          modeRef.current = { kind: "region-drag", startSec: mode.startSec, currentSec: sec };
          const s = Math.min(mode.startSec, sec);
          const en = Math.max(mode.startSec, sec);
          setDragDisplay([secToRatio(s), secToRatio(en)]);
          setCursor("col-resize");
        }
        return;
      }

      if (mode.kind === "region-drag") {
        const sec = xToSec(e.clientX);
        modeRef.current = { ...mode, currentSec: sec };
        const s = Math.min(mode.startSec, sec);
        const en = Math.max(mode.startSec, sec);
        setDragDisplay([secToRatio(s), secToRatio(en)]);
        return;
      }

      // idle: hover hit-test → 更新光标
      const hit = hitTestEdge(e.clientX);
      setCursor(hit ? "col-resize" : "crosshair");
    },
    [xToSec, secToRatio, hitTestEdge, onRegionEdgeDrag],
  );

  const handleMouseUp = useCallback(
    (e: React.PointerEvent<HTMLCanvasElement>) => {
      const mode = modeRef.current;
      if (e.currentTarget.hasPointerCapture(e.pointerId)) {
        e.currentTarget.releasePointerCapture(e.pointerId);
      }

      if (mode.kind === "region-edge") {
        modeRef.current = { kind: "idle" };
        setCursor("crosshair");
        return;
      }

      if (mode.kind === "region-drag") {
        const sec = xToSec(e.clientX);
        const start = Math.min(mode.startSec, sec);
        const end = Math.max(mode.startSec, sec);
        if (end - start >= 0.05) onRegionSelected(start, end);
        modeRef.current = { kind: "idle" };
        setDragDisplay(null);
        setCursor("crosshair");
        return;
      }

      if (mode.kind === "maybe-seek") {
        onSeek(xToSec(e.clientX));
        modeRef.current = { kind: "idle" };
        setCursor("crosshair");
        return;
      }
    },
    [xToSec, onRegionSelected, onSeek],
  );

  const handlePointerLeave = useCallback(() => {
    const mode = modeRef.current;
    if (mode.kind === "idle") {
      setCursor("crosshair");
    }
  }, []);

  const handlePointerCancel = useCallback(() => {
    const mode = modeRef.current;
    if (mode.kind !== "idle") {
      if (mode.kind === "region-drag" || mode.kind === "maybe-seek") {
        setDragDisplay(null);
      }
      modeRef.current = { kind: "idle" };
      setCursor("crosshair");
    }
  }, []);

  const handleWheel = useCallback(
    (e: React.WheelEvent) => {
      e.preventDefault();
      const centerSec = xToSec(e.clientX);
      if (e.ctrlKey || e.metaKey) {
        onZoom(e.deltaY, centerSec);
      } else {
        const dur = viewRange.endSec - viewRange.startSec;
        onScroll((e.deltaY / 200) * dur);
      }
    },
    [xToSec, viewRange, onZoom, onScroll],
  );

  // ── 渲染 ──────────────────────────────────────────────────────────────────
  //
  // Rust 进度事件每 50ms 才来一次（20Hz），直接拿它画播放头会一格一格地跳、晃眼。
  // 这里改为：以最近一次权威进度为锚点，播放中用 rAF 按速度在帧间平滑外推播放头
  // 位置（仅驱动 WebGL 重绘，不触发 React 重渲染）；新进度到达时重新锚定。
  //
  // 锚点的墙钟时刻用 playheadWallMs（事件经时钟对齐扣掉传输延迟后的真实发出时刻），
  // 而非收到的当下，故 elapsed 自带那段延迟、外推不再滞后于真实进度。

  // Rebuild the draw closure so it always captures the latest viewport and overlays.
  const drawRef = useRef<(playheadSec: number) => void>(() => {});
  drawRef.current = (playheadSec: number) => {
    const playheadRatio = duration > 0 ? secToRatio(playheadSec) : -1;
    const normalizedRegions = regions.map((region) => ({
      start: secToRatio(region.startSec),
      end: secToRatio(region.endSec),
      selected: region.selected,
      overlapping: region.overlapping,
    }));
    const normalizedLoop = loopRange
      ? ([secToRatio(loopRange[0]), secToRatio(loopRange[1])] as [number, number])
      : null;
    render({
      data,
      playhead: playheadRatio,
      dragRange: dragDisplay,
      regions: normalizedRegions,
      colors,
      loopRange: normalizedLoop,
    });
  };

  // 锚点：每收到一次权威进度（playhead 变化）重新锚定，供帧间外推
  const anchorSecRef = useRef(playhead);
  const anchorWallRef = useRef(0);
  // 是否已收到“播放中”的首个真实进度：未收到前冻结播放头，避免用启动延迟外推。
  const startedRef = useRef(false);
  useEffect(() => {
    anchorSecRef.current = playhead;
    // 锚点墙钟取「该位置真实对应的时刻」（已扣传输延迟），外推从此刻起算即不再滞后。
    anchorWallRef.current =
      playheadWallMs && playheadWallMs > 0 ? playheadWallMs : performance.now();
    startedRef.current = true;
  }, [playhead, playheadWallMs]);

  // 速度用 ref 实时读取，避免变速时 rAF 副作用重启导致重锚跳动
  const speedRef = useRef(speed);
  speedRef.current = speed;

  // 播放中：rAF 按速度平滑外推播放头，逐帧重绘
  useEffect(() => {
    if (!playing) return;
    // Playback state may update before the backend actually emits progress.
    // Freeze at the anchor until the first authoritative progress sample arrives.
    startedRef.current = false;
    let raf = 0;
    const tick = () => {
      const elapsed = (performance.now() - anchorWallRef.current) / 1000;
      const sec = startedRef.current
        ? anchorSecRef.current + elapsed * speedRef.current
        : anchorSecRef.current;
      drawRef.current(sec);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing]);

  // 非播放态（暂停 / seek）或可视数据变化时：在锚点处静态重绘一次
  useEffect(() => {
    if (playing) return;
    drawRef.current(anchorSecRef.current);
  }, [
    playing,
    playhead,
    data,
    regions,
    dragDisplay,
    loopRange,
    secToRatio,
    duration,
  ]);

  return (
    <canvas
      ref={canvasRef}
      style={{
        width: "100%",
        height: "100%",
        display: "block",
        cursor,
        touchAction: "none",
      }}
      onPointerDown={handleMouseDown}
      onPointerMove={handleMouseMove}
      onPointerUp={handleMouseUp}
      onPointerLeave={handlePointerLeave}
      onPointerCancel={handlePointerCancel}
      onWheel={handleWheel}
    />
  );
}
