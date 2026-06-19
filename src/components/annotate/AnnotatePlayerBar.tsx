import React, { useRef, useState, useCallback, useEffect } from "react";
import { PlayBtn } from "@/components/shared/Primitives";
import type { Label } from "@/types/waveform";

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75];

interface AnnotatePlayerBarProps {
  ready: boolean;
  playing: boolean;
  looping: boolean;
  currentTime: number;
  playheadWallMs?: number;
  duration: number;
  speed: number;
  labels?: Label[];
  selectedId?: string | null;
  onPlay: () => void;
  onPause: () => void;
  onToggleLoop: () => void;
  onSetSpeed: (speed: number) => void;
  onSeek: (sec: number) => void;
}

function formatTime(sec: number): string {
  if (!isFinite(sec) || sec < 0) sec = 0;
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  return `${m}:${s < 10 ? "0" : ""}${s.toFixed(2)}`;
}

export function AnnotatePlayerBar({
  ready,
  playing,
  looping,
  currentTime,
  playheadWallMs,
  duration,
  speed,
  labels = [],
  selectedId,
  onPlay,
  onPause,
  onToggleLoop,
  onSetSpeed,
  onSeek,
}: AnnotatePlayerBarProps) {
  const [displayTime, setDisplayTime] = useState(currentTime);
  const anchorSecRef = useRef(currentTime);
  const anchorWallRef = useRef(0);
  const startedRef = useRef(false);
  const speedRef = useRef(speed);
  speedRef.current = speed;

  useEffect(() => {
    anchorSecRef.current = currentTime;
    anchorWallRef.current =
      playheadWallMs && playheadWallMs > 0 ? playheadWallMs : performance.now();
    startedRef.current = true;
    setDisplayTime(currentTime);
  }, [currentTime, playheadWallMs]);

  useEffect(() => {
    if (!playing) {
      setDisplayTime(anchorSecRef.current);
      return;
    }

    // 与波形播放头使用同一套锚点外推，避免进度条 20Hz、波形 rAF 导致视觉错位。
    startedRef.current = false;
    let raf = 0;
    const tick = () => {
      const elapsed = (performance.now() - anchorWallRef.current) / 1000;
      const raw = startedRef.current
        ? anchorSecRef.current + elapsed * speedRef.current
        : anchorSecRef.current;
      const sec = duration > 0 ? Math.max(0, Math.min(raw, duration)) : raw;
      setDisplayTime(sec);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing, duration]);

  const shownTime = playing ? displayTime : currentTime;
  const frac = duration > 0 ? Math.min(1, Math.max(0, shownTime / duration)) : 0;

  const trackRef = useRef<HTMLDivElement>(null);
  const draggingRef = useRef(false);
  const [hover, setHover] = useState<{ x: number; time: number } | null>(null);
  const [markerHover, setMarkerHover] = useState<{
    label: Label;
    index: number;
    left: number;
  } | null>(null);

  // clientX → 源秒（夹在 [0, duration]）
  const secFromClientX = useCallback(
    (clientX: number) => {
      const el = trackRef.current;
      if (!el || duration <= 0) return 0;
      const rect = el.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
      return ratio * duration;
    },
    [duration],
  );

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (!ready || duration <= 0) return;
      draggingRef.current = true;
      onSeek(secFromClientX(e.clientX));
      const onMove = (ev: MouseEvent) => {
        if (draggingRef.current) onSeek(secFromClientX(ev.clientX));
      };
      const onUp = () => {
        draggingRef.current = false;
        window.removeEventListener("mousemove", onMove);
        window.removeEventListener("mouseup", onUp);
      };
      window.addEventListener("mousemove", onMove);
      window.addEventListener("mouseup", onUp);
    },
    [ready, duration, onSeek, secFromClientX],
  );

  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!ready || duration <= 0 || !trackRef.current) return;
      const rect = trackRef.current.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
      setHover({ x, time: secFromClientX(e.clientX) });
    },
    [ready, duration, secFromClientX],
  );

  return (
    <div style={s.shell}>
      {/* 进度行：当前时间 — 进度条 — 总时长 */}
      <div style={s.seekRow}>
        <span style={s.time}>{ready ? formatTime(shownTime) : "--:--"}</span>

        <div
          ref={trackRef}
          style={s.progressArea}
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseLeave={() => setHover(null)}
        >
          <div style={s.track}>
            <div style={{ ...s.trackFill, width: `${frac * 100}%` }} />
            {ready &&
              duration > 0 &&
              labels.map((label, idx) => {
                const mid = Math.max(
                  0,
                  Math.min(100, ((label.start + label.end) / 2 / duration) * 100),
                );
                const selected = label.id === selectedId;
                return (
                  <div
                    key={label.id}
                    style={{ ...s.markerHit, left: `${mid}%` }}
                    onMouseEnter={() => setMarkerHover({ label, index: idx + 1, left: mid })}
                    onMouseLeave={() =>
                      setMarkerHover((h) => (h?.label.id === label.id ? null : h))
                    }
                  >
                    <span style={{ ...s.marker, ...(selected ? s.markerSelected : null) }} />
                  </div>
                );
              })}
            {ready && <div style={{ ...s.thumb, left: `${frac * 100}%` }} />}

            {/* 片段三角悬浮卡：编号 · 时间区间 · 备注 */}
            {markerHover && (
              <div style={{ ...s.markerTip, left: `${markerHover.left}%` }}>
                <div style={s.markerTipHead}>
                  <span style={s.markerTipNum}>
                    片段 {String(markerHover.index).padStart(2, "0")}
                  </span>
                  <span style={s.markerTipTime}>
                    {formatTime(markerHover.label.start)} → {formatTime(markerHover.label.end)}
                  </span>
                </div>
                {markerHover.label.text.trim() ? (
                  <div style={s.markerTipNote}>{markerHover.label.text.trim()}</div>
                ) : (
                  <div style={s.markerTipEmpty}>（无备注）</div>
                )}
              </div>
            )}
          </div>

          {hover && !markerHover && (
            <div style={{ ...s.tooltip, left: hover.x }}>{formatTime(hover.time)}</div>
          )}
        </div>

        <span style={{ ...s.time, ...s.timeMuted }}>{ready ? formatTime(duration) : "--:--"}</span>
      </div>

      {/* 控制行：左 回环 / 中 播放 / 右 变速 */}
      <div style={s.controls}>
        <div style={{ ...s.zone, ...s.zoneLeft }}>
          <button
            disabled={!ready}
            onClick={onToggleLoop}
            role="switch"
            aria-checked={looping}
            title="AB 回环（当前/最近片段）"
            style={{
              ...s.loop,
              ...(looping ? s.loopActive : null),
              ...(!ready ? s.loopDisabled : null),
            }}
          >
            <span>句段回环</span>
            <span style={{ ...s.switch, ...(looping ? s.switchActive : null) }} aria-hidden="true">
              <span style={{ ...s.knob, ...(looping ? s.knobActive : null) }} />
            </span>
          </button>
        </div>

        <div style={{ ...s.zone, ...s.zoneCenter }}>
          <PlayBtn
            playing={playing}
            disabled={!ready}
            size={44}
            onClick={playing ? onPause : onPlay}
          />
        </div>

        <div style={{ ...s.zone, ...s.zoneRight }}>
          <span style={s.speedLabel}>慢听速度</span>
          <div style={s.speedGroup}>
            {SPEEDS.map((sp) => {
              const active = Math.abs(speed - sp) < 1e-3;
              return (
                <button
                  key={sp}
                  disabled={!ready}
                  onClick={() => onSetSpeed(sp)}
                  style={{
                    ...s.speedBtn,
                    ...(active ? s.speedBtnActive : null),
                    ...(!ready ? s.speedBtnDisabled : null),
                  }}
                >
                  {sp}×
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

const s: Record<string, React.CSSProperties> = {
  shell: {
    flexShrink: 0,
    background: "var(--color-paper)",
    borderTop: `0.5px solid var(--color-border)`,
    boxShadow: "0 -1px 0 rgba(26,39,68,0.04)",
    paddingBottom: 10,
    userSelect: "none",
  },

  // ── 进度行 ──────────────────────────────────────────────────────────────
  seekRow: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    padding: "9px 18px 4px",
  },
  time: {
    fontFamily: "var(--font-mono)",
    fontSize: 13,
    color: "var(--color-ink-2)",
    letterSpacing: "-0.02em",
    flexShrink: 0,
    minWidth: 56,
  },
  timeMuted: {
    color: "var(--color-ink-3)",
    textAlign: "right",
  },
  progressArea: {
    flex: 1,
    height: 20,
    display: "flex",
    alignItems: "center",
    position: "relative",
    cursor: "pointer",
  },
  track: {
    flex: 1,
    height: 5,
    background: "var(--color-paper-2)",
    position: "relative",
    borderRadius: 2,
    overflow: "visible",
  },
  trackFill: {
    height: "100%",
    background: "var(--color-brand)",
    borderRadius: 2,
    pointerEvents: "none",
  },
  // 片段标记命中区：放大的透明热区，悬在进度条上方、便于鼠标移上去触发 tooltip
  markerHit: {
    position: "absolute",
    top: -12,
    transform: "translateX(-50%)",
    width: 16,
    height: 13,
    display: "flex",
    justifyContent: "center",
    alignItems: "flex-start",
    cursor: "default",
  },
  // 朝下的小三角（▼），指向各片段中点
  marker: {
    width: 0,
    height: 0,
    borderLeft: "4px solid transparent",
    borderRight: "4px solid transparent",
    borderTop: "6px solid rgba(26, 78, 216, 0.45)",
    pointerEvents: "none",
  },
  markerSelected: {
    borderLeft: "5px solid transparent",
    borderRight: "5px solid transparent",
    borderTop: "7px solid var(--color-brand)",
  },
  // 片段三角悬浮卡
  markerTip: {
    position: "absolute",
    bottom: "calc(100% + 13px)",
    transform: "translateX(-50%)",
    background: "var(--color-paper)",
    border: `0.5px solid var(--color-border)`,
    borderRadius: 7,
    boxShadow: "0 6px 18px rgba(26,39,68,0.16)",
    padding: "7px 10px",
    minWidth: 134,
    maxWidth: 248,
    zIndex: 5,
    pointerEvents: "none",
    display: "flex",
    flexDirection: "column",
    gap: 4,
  },
  markerTipHead: {
    display: "flex",
    alignItems: "baseline",
    justifyContent: "space-between",
    gap: 10,
  },
  markerTipNum: {
    fontFamily: "var(--font-mono)",
    fontSize: 11,
    fontWeight: 600,
    color: "var(--color-brand)",
    whiteSpace: "nowrap",
  },
  markerTipTime: {
    fontFamily: "var(--font-mono)",
    fontSize: 11,
    color: "var(--color-ink-3)",
    whiteSpace: "nowrap",
  },
  markerTipNote: {
    fontSize: 12,
    lineHeight: 1.4,
    color: "var(--color-ink-2)",
    whiteSpace: "pre-wrap",
    wordBreak: "break-word",
  },
  markerTipEmpty: {
    fontSize: 12,
    fontStyle: "italic",
    color: "var(--color-ink-3)",
  },
  thumb: {
    position: "absolute",
    top: "50%",
    transform: "translate(-50%, -50%)",
    width: 12,
    height: 12,
    borderRadius: "50%",
    background: "var(--color-brand)",
    boxShadow: "0 0 0 2px var(--color-paper), 0 1px 3px rgba(26,39,68,0.2)",
    pointerEvents: "none",
  },
  tooltip: {
    position: "absolute",
    bottom: "calc(100% + 6px)",
    transform: "translateX(-50%)",
    background: "var(--color-brand)",
    color: "#fff",
    fontFamily: "var(--font-mono)",
    fontSize: 12,
    padding: "2px 6px",
    borderRadius: 4,
    whiteSpace: "nowrap",
    pointerEvents: "none",
  },

  // ── 控制行 ──────────────────────────────────────────────────────────────
  controls: {
    display: "flex",
    alignItems: "center",
    padding: "0 18px",
  },
  zone: { flex: 1 },
  zoneLeft: { display: "flex", alignItems: "center", justifyContent: "flex-start" },
  zoneCenter: { flex: "0 0 auto", display: "flex", alignItems: "center", gap: 14 },
  zoneRight: { display: "flex", alignItems: "center", justifyContent: "flex-end" },

  // 回环开关（label + iOS 风格滑动开关）
  loop: {
    display: "inline-flex",
    alignItems: "center",
    gap: 8,
    border: "none",
    background: "transparent",
    cursor: "pointer",
    fontFamily: "var(--font-mono)",
    fontSize: 12,
    color: "var(--color-ink-3)",
    padding: "4px 2px",
  },
  loopActive: { color: "var(--color-brand)" },
  loopDisabled: { opacity: 0.5, cursor: "not-allowed" },
  switch: {
    position: "relative",
    width: 30,
    height: 16,
    borderRadius: "var(--radius-full)",
    background: "var(--color-border-2)",
    flexShrink: 0,
    transition: "background var(--duration-fast) var(--ease-out)",
  },
  switchActive: { background: "var(--color-brand)" },
  knob: {
    position: "absolute",
    top: 2,
    left: 2,
    width: 12,
    height: 12,
    borderRadius: "50%",
    background: "#fff",
    boxShadow: "0 1px 2px rgba(26,39,68,0.25)",
    transition: "transform var(--duration-fast) var(--ease-out)",
  },
  knobActive: { transform: "translateX(14px)" },

  // 变速不变调
  speedLabel: {
    fontFamily: "var(--font-mono)",
    fontSize: 12,
    color: "var(--color-ink-3)",
    marginRight: 8,
  },
  speedGroup: {
    display: "flex",
    gap: 2,
    background: "var(--color-paper-2)",
    padding: 2,
    borderRadius: 7,
    border: `0.5px solid var(--color-border-2)`,
  },
  speedBtn: {
    fontFamily: "var(--font-mono)",
    fontSize: 13,
    color: "var(--color-ink-3)",
    background: "transparent",
    border: "none",
    borderRadius: 5,
    padding: "3px 8px",
    cursor: "pointer",
  },
  speedBtnActive: {
    color: "var(--color-brand)",
    background: "var(--color-brand-soft)",
    fontWeight: 600,
  },
  speedBtnDisabled: { opacity: 0.5, cursor: "not-allowed" },
};
