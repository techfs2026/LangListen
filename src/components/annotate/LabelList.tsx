import React, { useEffect, useRef, useState } from "react";
import type { Label } from "@/types/waveform";

interface LabelListProps {
  labels: Label[];
  duration: number;
  selectedId: string | null;
  overlappingIds: Set<string>;
  onSelect: (id: string) => void;
  onRemove: (id: string) => void;
  onUpdateText: (id: string, text: string) => void;
}

export function LabelList({
  labels,
  selectedId,
  overlappingIds,
  onSelect,
  onRemove,
  onUpdateText,
}: LabelListProps) {
  const listRef = useRef<HTMLDivElement>(null);
  const selectedCardRef = useRef<HTMLDivElement | null>(null);

  // 选中卡片变化时（框选新增、←/→ 切换、点击定位都会改 selectedId），
  // 横向滚动让选中卡片进入可见区——否则新卡片会被挤到最右侧看不到。
  useEffect(() => {
    const el = selectedCardRef.current;
    const container = listRef.current;
    if (!el || !container) return;
    const elRect = el.getBoundingClientRect();
    const cRect = container.getBoundingClientRect();
    const PAD = 16;
    if (elRect.left < cRect.left) {
      container.scrollBy({ left: elRect.left - cRect.left - PAD, behavior: "smooth" });
    } else if (elRect.right > cRect.right) {
      container.scrollBy({ left: elRect.right - cRect.right + PAD, behavior: "smooth" });
    }
  }, [selectedId, labels.length]);

  return (
    <div ref={listRef} style={s.container}>
      {labels.length === 0 ? (
        <div style={s.empty}>
          <span style={s.emptyIcon}>+</span>
          <span style={s.emptyText}>在声纹上拖拽，添加第一段听写片段</span>
        </div>
      ) : (
        <>
          {labels.map((label, idx) => (
            <LabelCard
              key={label.id}
              label={label}
              index={idx + 1}
              selected={label.id === selectedId}
              cardRef={label.id === selectedId ? selectedCardRef : undefined}
              overlapping={overlappingIds.has(label.id)}
              onSelect={() => onSelect(label.id)}
              onRemove={() => onRemove(label.id)}
              onUpdateText={(text) => onUpdateText(label.id, text)}
            />
          ))}
          <div style={s.addHint}>
            <div style={s.addIcon}>+</div>
            <div style={s.addText}>
              拖拽添加
              <br />
              片段
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// ── 单张标注卡 ─────────────────────────────────────────────────────────────────

interface LabelCardProps {
  label: Label;
  index: number;
  selected: boolean;
  cardRef?: React.Ref<HTMLDivElement>;
  overlapping: boolean;
  onSelect: () => void;
  onRemove: () => void;
  onUpdateText: (text: string) => void;
}

function fmtTime(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  return `${m}:${s < 10 ? "0" : ""}${s.toFixed(2)}`;
}

function fmtDur(sec: number): string {
  return sec < 1 ? `${(sec * 1000).toFixed(0)}ms` : `${sec.toFixed(2)}s`;
}

function LabelCard({
  label,
  index,
  selected,
  cardRef,
  overlapping,
  onSelect,
  onRemove,
  onUpdateText,
}: LabelCardProps) {
  const [hovered, setHovered] = useState(false);
  const [closeHover, setCloseHover] = useState(false);

  const cardStyle: React.CSSProperties = {
    ...s.card,
    borderColor: overlapping
      ? "#FCA5A5"
      : selected
        ? "var(--color-brand)"
        : hovered
          ? "var(--color-border-2)"
          : "var(--color-border)",
    boxShadow: overlapping
      ? "0 0 0 2px #FEE2E2"
      : selected
        ? `0 0 0 3px var(--color-brand-soft), 0 6px 16px rgba(26,39,68,0.12)`
        : hovered
          ? "0 8px 20px rgba(26,39,68,0.10)"
          : "0 1px 3px rgba(26,39,68,0.05)",
    background: overlapping ? "#FFF5F5" : "var(--color-paper)",
    transform: selected ? "translateY(-2px)" : hovered ? "translateY(-1px)" : undefined,
  };

  return (
    <div
      ref={cardRef}
      style={cardStyle}
      onClick={onSelect}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* 选中态左侧强调条 */}
      {selected && !overlapping && <div style={s.accentBar} />}

      {/* 右上角删除叉号 */}
      <button
        style={{
          ...s.closeBtn,
          background: closeHover ? "var(--color-danger)" : "transparent",
          color: closeHover ? "#fff" : "var(--color-ink-3)",
        }}
        onMouseEnter={() => setCloseHover(true)}
        onMouseLeave={() => setCloseHover(false)}
        onClick={(e) => {
          e.stopPropagation();
          onRemove();
        }}
        title="删除片段"
        aria-label="删除片段"
      >
        ×
      </button>

      <div style={{ display: "flex", alignItems: "center", gap: 8, paddingRight: 28 }}>
        <div
          style={{
            ...s.cardNum,
            color: overlapping ? "#DC2626" : selected ? "var(--color-brand)" : "var(--color-ink-3)",
          }}
        >
          {String(index).padStart(2, "0")}
        </div>
        {overlapping && <div style={s.overlapBadge}>⚠ 重叠</div>}
      </div>
      <div style={s.cardTimes}>
        <span style={s.t}>{fmtTime(label.start)}</span>
        <span style={s.arrow}>→</span>
        <span style={s.t}>{fmtTime(label.end)}</span>
        <span style={s.dur}>{fmtDur(label.end - label.start)}</span>
      </div>
      {selected && (
        <div style={s.nudgeHint}>
          <kbd style={s.kbdTiny}>←→</kbd>
          <span>切换区段</span>
        </div>
      )}
      <textarea
        style={s.cardInput}
        value={label.text}
        placeholder="听写文本 / 备注"
        onClick={(e) => e.stopPropagation()}
        onChange={(e) => onUpdateText(e.target.value)}
      />
    </div>
  );
}

// ── 样式 ──────────────────────────────────────────────────────────────────────

const s: Record<string, React.CSSProperties> = {
  container: {
    display: "flex",
    flexShrink: 0,
    flexDirection: "row",
    gap: 10,
    overflowX: "auto",
    padding: "14px 18px",
    background: "var(--color-paper-2)",
    borderTop: `0.5px solid var(--color-border)`,
    minHeight: 265,
    maxHeight: 315,
    alignItems: "stretch",
  },
  empty: {
    flex: 1,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 10,
    color: "var(--color-ink-3)",
    minHeight: 220,
  },
  emptyIcon: {
    width: 28,
    height: 28,
    borderRadius: "50%",
    border: "1px dashed var(--color-border-2)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 18,
    color: "var(--color-ink-3)",
  },
  emptyText: { fontSize: 13, fontFamily: "var(--font-mono)" },
  addHint: {
    flexShrink: 0,
    width: 84,
    height: 96,
    border: `1px dashed var(--color-border-2)`,
    borderRadius: 8,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: 4,
    cursor: "default",
    opacity: 0.52,
  },
  addIcon: { fontSize: 22, color: "var(--color-ink-3)", lineHeight: 1 },
  addText: { fontSize: 11, color: "var(--color-ink-3)", textAlign: "center", lineHeight: 1.5 },

  card: {
    position: "relative",
    flexShrink: 0,
    alignSelf: "stretch",
    minWidth: 270,
    maxWidth: 320,
    border: `0.5px solid var(--color-border)`,
    borderRadius: 8,
    padding: "12px 14px 14px",
    display: "flex",
    flexDirection: "column",
    gap: 7,
    cursor: "pointer",
    overflow: "hidden",
    transition: "box-shadow 0.12s, border-color 0.12s, background 0.12s, transform 0.12s",
  },
  accentBar: {
    position: "absolute",
    left: 0,
    top: 0,
    bottom: 0,
    width: 3,
    background: "var(--color-brand)",
    borderTopLeftRadius: 8,
    borderBottomLeftRadius: 8,
  },
  closeBtn: {
    position: "absolute",
    top: 8,
    right: 8,
    width: 26,
    height: 26,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    border: "none",
    borderRadius: 6,
    padding: 0,
    fontSize: 20,
    lineHeight: 1,
    cursor: "pointer",
    transition: "background 0.12s, color 0.12s",
  },
  cardNum: {
    fontFamily: "var(--font-mono)",
    fontSize: 18,
    fontWeight: 500,
  },
  overlapBadge: {
    fontSize: 10,
    fontFamily: "var(--font-mono)",
    color: "#DC2626",
    background: "#FEE2E2",
    border: "0.5px solid #FCA5A5",
    borderRadius: 6,
    padding: "2px 7px",
    letterSpacing: "0.04em",
    fontWeight: 600,
  },
  nudgeHint: {
    display: "flex",
    alignItems: "center",
    gap: 4,
    fontSize: 10,
    color: "var(--color-ink-3)",
    fontFamily: "var(--font-mono)",
    marginTop: -2,
  },
  nudgeSep: { color: "var(--color-border-2)", fontSize: 10 },
  kbdTiny: {
    fontFamily: "var(--font-mono)",
    fontSize: 9,
    color: "var(--color-ink-3)",
    background: "var(--color-paper)",
    border: `0.5px solid var(--color-border-2)`,
    borderRadius: 3,
    padding: "1px 4px",
    lineHeight: 1.2,
  },
  cardTimes: {
    display: "flex",
    alignItems: "center",
    gap: 4,
    fontFamily: "var(--font-mono)",
    fontSize: 13,
    flexWrap: "wrap",
  },
  t: { color: "var(--color-ink-1)", fontWeight: 500 },
  arrow: { color: "var(--color-ink-3)" },
  dur: { color: "var(--color-ink-3)", fontSize: 11 },
  cardInput: {
    background: "#fffefb",
    border: `0.5px solid var(--color-border-2)`,
    borderRadius: 6,
    color: "var(--color-ink-2)",
    fontSize: 13,
    lineHeight: 1.45,
    padding: "7px 8px",
    width: "100%",
    minHeight: 64,
    resize: "none",
    outline: "none",
  },
};
