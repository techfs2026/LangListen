import React from "react";
import { Btn } from "@/components/shared/Primitives";
import type { AudioInfo, LoadingState } from "@/types/waveform";

interface AnnotateToolbarProps {
  audioInfo: AudioInfo | null;
  audioName?: string;
  loadingState: LoadingState;
  labelCount: number;
  hasUnsavedChanges?: boolean;
  onBack: () => void;
  onShowHelp: () => void;
  onOpenAudio: () => void;
  onSaveLabels: () => void;
  onLoadLabels: () => void;
  onClearLabels: () => void;
  onExport: () => void;
}

export function AnnotateToolbar({
  audioInfo,
  audioName,
  loadingState,
  labelCount,
  hasUnsavedChanges = false,
  onBack,
  onShowHelp,
  onOpenAudio,
  onSaveLabels,
  onLoadLabels,
  onClearLabels,
  onExport,
}: AnnotateToolbarProps) {
  const isReady = loadingState === "ready";
  const fileName = audioInfo ? audioName || "当前音频" : "声纹书桌";
  const subtitle =
    loadingState === "idle"
      ? "打开一段音频，开始逐句辨认"
      : loadingState === "decoding"
        ? "正在把声音展开成可阅读的声纹"
        : loadingState === "error"
          ? "音频加载失败，请重新选择"
          : `第 1 遍 · ${formatDuration(audioInfo?.duration ?? 0)} · 拖拽声纹添加听写片段`;

  return (
    <div style={s.shell}>
      <div style={s.row}>
        <Btn variant="ghost" size="sm" onClick={onBack} style={s.backBtn}>
          ← 返回
        </Btn>

        <div style={s.titleBlock}>
          <div style={s.titleLine}>
            <span style={s.modeTag}>精听模式</span>
            <span style={s.fileName} title={fileName}>
              {fileName}
            </span>
          </div>
          <span style={s.subtitle}>{subtitle}</span>
        </div>

        <div style={s.spacer} />

        <Btn variant="primary" onClick={onOpenAudio}>
          打开音频
        </Btn>
        <Btn variant="ghost" onClick={onLoadLabels} disabled={!isReady}>
          载入标记
        </Btn>
        <Btn
          variant="ghost"
          onClick={onSaveLabels}
          disabled={labelCount === 0 && !hasUnsavedChanges}
          style={hasUnsavedChanges ? s.dirtyBtn : undefined}
        >
          {hasUnsavedChanges ? "保存标记 *" : "保存标记"}
        </Btn>
        <Btn variant="ghost" onClick={onClearLabels} disabled={labelCount === 0}>
          清空标记
        </Btn>

        {loadingState === "decoding" && (
          <span style={s.decoding}>
            <span style={s.decodingDot} />
            解码中…
          </span>
        )}
        {loadingState === "error" && <span style={s.error}>加载失败</span>}
        {isReady && audioInfo && labelCount > 0 && <span style={s.badge}>{labelCount} 段</span>}

        <Btn variant="dark" onClick={onExport} disabled={labelCount === 0}>
          ↓ 导出数据包
        </Btn>
        <div style={s.rowSep} />
        <Btn
          variant="ghost"
          size="sm"
          onClick={onShowHelp}
          style={{ fontSize: 12 }}
          title="查看全部快捷键"
        >
          快捷键 <kbd className="kbd kbd--inline">H</kbd>
        </Btn>
      </div>
    </div>
  );
}

function formatDuration(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return "--:--";
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s < 10 ? "0" : ""}${s}`;
}

// ── 样式 ─────────────────────────────────────────────────────────────────────

const s: Record<string, React.CSSProperties> = {
  shell: {
    display: "flex",
    flexDirection: "column",
    background: "var(--color-paper)",
    borderBottom: `0.5px solid var(--color-border)`,
    flexShrink: 0,
    boxShadow: "0 1px 0 rgba(26,39,68,0.04)",
  },
  row: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    padding: "0 16px",
    height: 58,
    minWidth: 0,
  },
  backBtn: {
    fontSize: 12,
    padding: "4px 10px",
  },
  rowSep: {
    width: 1,
    height: 18,
    background: "var(--color-border-2)",
    borderRadius: 1,
    flexShrink: 0,
    margin: "0 2px",
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    gap: 3,
    minWidth: 180,
    maxWidth: 360,
    overflow: "hidden",
  },
  titleLine: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    minWidth: 0,
  },
  modeTag: {
    fontFamily: "var(--font-mono)",
    fontSize: 10,
    letterSpacing: 0,
    color: "var(--color-brand)",
    padding: "2px 7px",
    background: "var(--color-brand-soft)",
    borderRadius: 4,
    whiteSpace: "nowrap",
  },
  fileName: {
    fontSize: 14,
    fontWeight: 650,
    color: "var(--color-ink-1)",
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  subtitle: {
    fontFamily: "var(--font-mono)",
    fontSize: 11,
    color: "var(--color-ink-3)",
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  spacer: { flex: 1, minWidth: 12 },
  time: {
    fontFamily: "var(--font-mono)",
    fontSize: 13,
    color: "var(--color-ink-1)",
    letterSpacing: "-0.02em",
    minWidth: 138,
  },
  timeSep: { color: "var(--color-ink-3)", margin: "0 3px" },
  meta: { fontSize: 11, color: "var(--color-ink-3)" },
  badge: {
    fontFamily: "var(--font-mono)",
    fontSize: 10,
    fontWeight: 500,
    color: "var(--color-brand)",
    background: "var(--color-brand-soft)",
    border: `0.5px solid #5B7FEA44`,
    borderRadius: 10,
    padding: "2px 8px",
  },
  dirtyBtn: {
    color: "var(--color-warning)",
    background: "var(--color-warning-soft)",
    borderColor: "rgba(146,64,14,0.2)",
  },
  decoding: {
    display: "flex",
    alignItems: "center",
    gap: 4,
    fontSize: 12,
    color: "#D97706",
    fontWeight: 500,
  },
  decodingDot: {
    width: 6,
    height: 6,
    borderRadius: "50%",
    background: "#D97706",
    animation: "spin 1s linear infinite",
  },
  error: { fontSize: 12, color: "var(--color-danger)", fontWeight: 500 },
};
