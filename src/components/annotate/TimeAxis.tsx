import { useMemo } from "react";

interface TimeAxisProps {
  viewRange: { startSec: number; endSec: number };
  width: number; // container px width (used to choose tick density)
  /** 放在波形上方还是下方：上方时刻度朝下、标签在上、分隔线在底部 */
  placement?: "top" | "bottom";
}

function formatTime(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  if (m === 0) return `${s.toFixed(1)}s`;
  return `${m}:${s < 10 ? "0" : ""}${s.toFixed(0)}`;
}

/** 根据视图时长自动选合适的刻度间隔 */
function chooseTick(dur: number): number {
  const targets = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
  // 目标约 8~12 个刻度
  const ideal = dur / 10;
  return targets.reduce((prev, cur) =>
    Math.abs(cur - ideal) < Math.abs(prev - ideal) ? cur : prev,
  );
}

export function TimeAxis({ viewRange, width, placement = "bottom" }: TimeAxisProps) {
  const { startSec, endSec } = viewRange;
  const dur = endSec - startSec;
  const isTop = placement === "top";

  const ticks = useMemo(() => {
    if (dur <= 0 || width <= 0) return [];
    const interval = chooseTick(dur);
    const first = Math.ceil(startSec / interval) * interval;
    const result: number[] = [];
    for (let t = first; t <= endSec + 1e-9; t += interval) {
      result.push(parseFloat(t.toFixed(6)));
    }
    return result;
  }, [startSec, endSec, dur, width]);

  return (
    <div
      style={{
        position: "relative",
        height: 24,
        ...(isTop
          ? { borderBottom: `0.5px solid var(--color-border)` }
          : { borderTop: `0.5px solid var(--color-border)` }),
        background: "var(--color-paper)",
        boxShadow: isTop
          ? "inset 0 -1px 0 rgba(26,39,68,0.02)"
          : "inset 0 1px 0 rgba(26,39,68,0.02)",
        flexShrink: 0,
      }}
    >
      {ticks.map((t) => {
        const pct = ((t - startSec) / dur) * 100;
        if (pct < 0 || pct > 100) return null;
        return (
          <div
            key={t}
            style={{
              position: "absolute",
              left: `${pct}%`,
              [isTop ? "bottom" : "top"]: 0,
              display: "flex",
              flexDirection: isTop ? "column-reverse" : "column",
              alignItems: "center",
              transform: "translateX(-50%)",
            }}
          >
            <div style={{ width: 0.5, height: 5, background: "var(--color-ink-3)" }} />
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 9,
                color: "var(--color-ink-3)",
                [isTop ? "marginBottom" : "marginTop"]: 2,
                whiteSpace: "nowrap",
                userSelect: "none",
              }}
            >
              {formatTime(t)}
            </span>
          </div>
        );
      })}
    </div>
  );
}
