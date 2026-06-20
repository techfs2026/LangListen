import React, { useEffect, useRef, useState } from "react";
import { PRESET_TAGS, type Label } from "@/types/waveform";

interface LabelListProps {
  labels: Label[];
  duration: number;
  selectedId: string | null;
  overlappingIds: Set<string>;
  whisperStatus: "loading" | "ready" | "error";
  onSelect: (id: string) => void;
  onRemove: (id: string) => void;
  onUpdateTranscript: (id: string, transcript: string) => void;
  onUpdateNote: (id: string, note: string) => void;
  onToggleTag: (id: string, tag: string) => void;
  onRetranscribe: (id: string) => void;
  onCancelTranscribe: (id: string) => void;
}

const WHISPER_HINT: Record<LabelListProps["whisperStatus"], string> = {
  loading: "Whisper 模型加载中…",
  ready: "Whisper 就绪 · 在声纹上拖拽添加片段",
  error: "Whisper 加载失败 · 仍可拖拽,转写时会重试",
};

export function LabelList({
  labels,
  selectedId,
  overlappingIds,
  whisperStatus,
  onSelect,
  onRemove,
  onUpdateTranscript,
  onUpdateNote,
  onToggleTag,
  onRetranscribe,
  onCancelTranscribe,
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
    // 外层负责横向滚动并 rotateX 翻转,把滚动条移到顶部;内层再翻回来让内容正立
    <div ref={listRef} style={s.container}>
      <div style={s.inner}>
        {labels.length === 0 ? (
          <div style={s.empty}>
            {whisperStatus === "loading" ? (
              <span style={s.emptySpinner} />
            ) : (
              <span style={s.emptyIcon}>{whisperStatus === "error" ? "!" : "+"}</span>
            )}
            <span style={s.emptyText}>{WHISPER_HINT[whisperStatus]}</span>
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
              onUpdateTranscript={(text) => onUpdateTranscript(label.id, text)}
              onUpdateNote={(text) => onUpdateNote(label.id, text)}
              onToggleTag={(tag) => onToggleTag(label.id, tag)}
              onRetranscribe={() => onRetranscribe(label.id)}
              onCancelTranscribe={() => onCancelTranscribe(label.id)}
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
  onUpdateTranscript: (text: string) => void;
  onUpdateNote: (text: string) => void;
  onToggleTag: (tag: string) => void;
  onRetranscribe: () => void;
  onCancelTranscribe: () => void;
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
  onUpdateTranscript,
  onUpdateNote,
  onToggleTag,
  onRetranscribe,
  onCancelTranscribe,
}: LabelCardProps) {
  const [hovered, setHovered] = useState(false);
  const [closeHover, setCloseHover] = useState(false);
  const status = label.transcriptStatus ?? "idle";

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
      {/* 转写区：标题行带状态/操作 */}
      <div style={s.sectionHead}>
        <span style={s.sectionLabel}>转写</span>
        {status === "loading" ? (
          <button
            style={s.miniBtn}
            onClick={(e) => {
              e.stopPropagation();
              onCancelTranscribe();
            }}
            title="取消转写"
          >
            <span style={s.spinner} /> 取消
          </button>
        ) : (
          <button
            style={s.miniBtn}
            onClick={(e) => {
              e.stopPropagation();
              onRetranscribe();
            }}
            title="重新转写"
          >
            ↻ 重转
          </button>
        )}
      </div>
      <textarea
        style={s.transcriptInput}
        value={label.transcript}
        placeholder={
          status === "loading"
            ? "转写中…"
            : status === "empty"
              ? "未识别,请手动填写"
              : status === "error"
                ? "转写失败,点「重转」重试"
                : "Whisper 转写文本"
        }
        onClick={(e) => e.stopPropagation()}
        onChange={(e) => onUpdateTranscript(e.target.value)}
      />

      {/* 标签 chips */}
      <div style={s.tagRow}>
        {PRESET_TAGS.map((tag) => {
          const active = label.tags.includes(tag);
          return (
            <button
              key={tag}
              style={{
                ...s.tagChip,
                ...(active ? s.tagChipActive : null),
              }}
              onClick={(e) => {
                e.stopPropagation();
                onToggleTag(tag);
              }}
            >
              {tag}
            </button>
          );
        })}
      </div>

      {/* 备注 */}
      <textarea
        style={s.noteInput}
        value={label.note}
        placeholder="备注…"
        onClick={(e) => e.stopPropagation()}
        onChange={(e) => onUpdateNote(e.target.value)}
      />
    </div>
  );
}

// ── 样式 ──────────────────────────────────────────────────────────────────────

const s: Record<string, React.CSSProperties> = {
  container: {
    // 波形区 : 标注列表 = 4 : 6
    flex: 6,
    display: "flex",
    flexDirection: "row",
    overflowX: "auto",
    overflowY: "hidden",
    background: "var(--color-paper-2)",
    borderTop: `0.5px solid var(--color-border)`,
    minHeight: 240,
    // rotateX 翻转 → 横向滚动条移到顶部（内层再翻回来）
    transform: "rotateX(180deg)",
  },
  inner: {
    display: "flex",
    flexDirection: "row",
    gap: 10,
    padding: "14px 18px",
    // 卡片保持自然高度并在面板内垂直居中（面板可能比卡片高）
    alignItems: "center",
    minWidth: "100%",
    transform: "rotateX(180deg)",
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
  emptySpinner: {
    width: 22,
    height: 22,
    border: `2px solid var(--color-border-2)`,
    borderTop: `2px solid var(--color-brand)`,
    borderRadius: "50%",
    animation: "spin 0.8s linear infinite",
    display: "inline-block",
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
    // 占列表区高度的 90%（inner 已 alignItems:center → 垂直居中）
    height: "90%",
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
  sectionHead: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    marginTop: 1,
  },
  sectionLabel: {
    fontSize: 10,
    fontFamily: "var(--font-mono)",
    color: "var(--color-ink-3)",
    letterSpacing: "0.06em",
    textTransform: "uppercase",
  },
  miniBtn: {
    display: "inline-flex",
    alignItems: "center",
    gap: 4,
    border: `0.5px solid var(--color-border-2)`,
    background: "var(--color-paper)",
    borderRadius: 5,
    color: "var(--color-ink-3)",
    fontSize: 10,
    lineHeight: 1,
    padding: "3px 6px",
    cursor: "pointer",
  },
  spinner: {
    width: 8,
    height: 8,
    border: `1.5px solid var(--color-border-2)`,
    borderTop: `1.5px solid var(--color-brand)`,
    borderRadius: "50%",
    animation: "spin 0.7s linear infinite",
    display: "inline-block",
  },
  transcriptInput: {
    background: "#fffefb",
    border: `0.5px solid var(--color-border-2)`,
    borderRadius: 6,
    color: "var(--color-ink-1)",
    fontSize: 13,
    lineHeight: 1.45,
    padding: "7px 8px",
    width: "100%",
    // 撑开卡片变高后多出来的空间（转写是主区）
    flex: 1,
    minHeight: 52,
    resize: "none",
    outline: "none",
  },
  tagRow: {
    display: "flex",
    flexWrap: "wrap",
    gap: 5,
  },
  tagChip: {
    border: `0.5px solid var(--color-border-2)`,
    background: "var(--color-paper)",
    borderRadius: 999,
    color: "var(--color-ink-3)",
    fontSize: 11,
    lineHeight: 1,
    padding: "4px 9px",
    cursor: "pointer",
    transition: "background 0.12s, color 0.12s, border-color 0.12s",
  },
  tagChipActive: {
    background: "var(--color-brand-soft)",
    borderColor: "var(--color-brand)",
    color: "var(--color-brand)",
    fontWeight: 600,
  },
  noteInput: {
    background: "#fffefb",
    border: `0.5px solid var(--color-border-2)`,
    borderRadius: 6,
    color: "var(--color-ink-2)",
    fontSize: 12,
    lineHeight: 1.4,
    padding: "6px 8px",
    width: "100%",
    minHeight: 38,
    resize: "none",
    outline: "none",
  },
};
