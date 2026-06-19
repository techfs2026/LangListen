import React, { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { open, save } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { AnnotateToolbar } from "./AnnotateToolbar";
import {
  WaveformCanvas,
  useWaveform,
  type RenderData,
  type WaveformRegion,
} from "@owllisten/waveform-react";
import { createTauriWaveformBackend } from "@owllisten/waveform-react/tauri";
import { TimeAxis } from "./TimeAxis";
import { LabelList } from "./LabelList";
import { AnnotatePlayerBar } from "./AnnotatePlayerBar";
import { ExportPanel, type ExportProgress } from "./ExportPanel";
import { ShortcutModal } from "./ShortcutModal";
import { useLabels } from "@/hooks/useLabels";
import { usePracticePlayer } from "@/hooks/usePracticePlayer";
import { exportListeningPack } from "@/utils/annotateApi";
import type { Label } from "@/types/waveform";

interface AnnotateScreenProps {
  onBack: () => void;
}

// 加载后初始视图分辨率：每秒约占 50 CSS px。窗口越宽 → 一屏看到的秒数越多，
// 但单句的像素宽度保持稳定，便于拖拽框选。整曲短于此跨度时退化为显示全曲。
const FIT_PX_PER_SEC = 50;
const waveformBackend = createTauriWaveformBackend();

/** 从完整路径取文件名（兼容 / 与 \ 分隔）。 */
function basename(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

export function AnnotateScreen({ onBack }: AnnotateScreenProps) {
  const {
    audioInfo,
    loadingState,
    viewRange,
    loadFile: loadWaveform,
    fetchPeaks,
    setViewRange,
    zoomIn,
    zoomOut,
    scrollBy,
  } = useWaveform({ backend: waveformBackend });

  const {
    labels,
    hasUnsavedChanges,
    addLabel,
    removeLabel,
    updateLabel,
    clearLabels,
    resetLabels,
    saveToFile,
    loadFromFile,
  } = useLabels();

  const {
    playState,
    currentTime,
    playheadWallMs,
    duration,
    loopRange,
    speed,
    load: loadAudio,
    play,
    playSegment,
    pause,
    seek,
    unload: unloadAudio,
    setLoop,
    setSpeed,
  } = usePracticePlayer();

  const [renderData, setRenderData] = useState<RenderData | null>(null);
  const [exportProgress, setExportProgress] = useState<ExportProgress | null>(null);
  const [containerWidth, setContainerWidth] = useState(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [audioName, setAudioName] = useState<string>("");
  const [showHelp, setShowHelp] = useState(false);

  const audioPathRef = useRef<string>("");
  const containerRef = useRef<HTMLDivElement>(null);
  // 跟踪最新 selectedId，供"播放头跟随选中"副作用比对而不把它放进依赖，
  // 否则点击卡片改了 selectedId 会触发副作用、用陈旧 currentTime 把选中冲掉。
  const selectedIdRef = useRef<string | null>(null);
  useEffect(() => {
    selectedIdRef.current = selectedId;
  }, [selectedId]);

  // 按起点排序的片段，供 ←/→ 片段间导航使用
  const sortedLabels = useMemo<Label[]>(
    () => [...labels].sort((a, b) => a.start - b.start),
    [labels],
  );

  // 重叠检测：O(n²)，label 数量通常 < 200 完全可接受
  const overlappingIds = useMemo<Set<string>>(() => {
    const ids = new Set<string>();
    for (let i = 0; i < labels.length; i++) {
      for (let j = i + 1; j < labels.length; j++) {
        const a = labels[i],
          b = labels[j];
        if (a.start < b.end && a.end > b.start) {
          ids.add(a.id);
          ids.add(b.id);
        }
      }
    }
    return ids;
  }, [labels]);

  const waveformRegions = useMemo<WaveformRegion[]>(
    () =>
      labels.map((label) => ({
        id: label.id,
        startSec: label.start,
        endSec: label.end,
        selected: label.id === selectedId,
        overlapping: overlappingIds.has(label.id),
      })),
    [labels, selectedId, overlappingIds],
  );

  // ── 峰值刷新 ──────────────────────────────────────────────────────────────

  const rafIdRef = useRef<number>(0);
  const reqIdRef = useRef<number>(0);

  const refreshPeaks = useCallback(() => {
    if (rafIdRef.current) return;
    rafIdRef.current = requestAnimationFrame(async () => {
      rafIdRef.current = 0;
      const container = containerRef.current;
      if (!container || !audioInfo) return;
      const dpr = window.devicePixelRatio || 1;
      const pixelWidth = Math.floor(container.clientWidth * dpr);
      if (pixelWidth <= 0) return;

      const myReqId = ++reqIdRef.current;
      const data = await fetchPeaks(pixelWidth);
      if (myReqId !== reqIdRef.current) return;

      if (data) {
        if (process.env.NODE_ENV !== "production") {
          const ch0 = data.channels[0];
          const len =
            ch0?.kind === "envelope"
              ? ch0.peaks.length
              : ch0?.kind === "polyline" || ch0?.kind === "stem"
                ? ch0.points.length
                : 0;
          const dur = viewRange.endSec - viewRange.startSec;
          const spp = (dur * (audioInfo?.sampleRate ?? 22050)) / pixelWidth;
          console.log(
            `[waveform] mode=${data.mode} channels=${data.channels.length} ` +
              `len=${len} pixelWidth=${pixelWidth} spp=${spp.toFixed(2)} dur=${dur.toFixed(3)}s`,
          );
        }
        setRenderData(data);
      }
    });
  }, [audioInfo, fetchPeaks, viewRange]);

  useEffect(() => {
    return () => {
      if (rafIdRef.current) {
        cancelAnimationFrame(rafIdRef.current);
        rafIdRef.current = 0;
      }
    };
  }, []);

  // 离开界面时关闭 Rust 播放引擎，避免返回后音频还在后台播放
  useEffect(() => {
    return () => unloadAudio();
  }, [unloadAudio]);

  useEffect(() => {
    refreshPeaks();
  }, [refreshPeaks]);

  useEffect(() => {
    const ro = new ResizeObserver(() => {
      if (containerRef.current) setContainerWidth(containerRef.current.clientWidth);
      refreshPeaks();
    });
    if (containerRef.current) ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, [refreshPeaks]);

  // ── 播放头跟随 ─────────────────────────────────────────────────────────────

  useEffect(() => {
    if (playState !== "playing") return;
    const dur = viewRange.endSec - viewRange.startSec;
    if (currentTime > viewRange.endSec) {
      setViewRange({ startSec: currentTime, endSec: currentTime + dur });
    }
    if (currentTime < viewRange.startSec) {
      setViewRange({ startSec: currentTime, endSec: currentTime + dur });
    }
  }, [currentTime, playState, viewRange, setViewRange]);

  // 播放头进入某个片段时自动选中对应卡片；落在片段之间的空隙时清空选中。
  // 仅依赖 currentTime（用 ref 比对 selectedId），保证只在播放头真正移动时同步。
  useEffect(() => {
    if (playState !== "playing") return;
    const cur = labels.find((l) => currentTime >= l.start && currentTime <= l.end);
    const nextId = cur ? cur.id : null;
    if (nextId !== selectedIdRef.current) setSelectedId(nextId);
  }, [currentTime, playState, labels]);

  // ── 文件操作 ──────────────────────────────────────────────────────────────

  // 按当前窗口宽度算出"适合的初始视图"：每秒约 FIT_PX_PER_SEC px。
  // 在 loadFile 内一次性应用，避免先渲染整曲再 snap 的闪烁。
  const computeFitView = useCallback((duration: number) => {
    const w = containerRef.current?.clientWidth ?? 0;
    const span = w > 0 ? w / FIT_PX_PER_SEC : duration;
    return { startSec: 0, endSec: Math.min(span, duration) };
  }, []);

  const handleOpenAudio = useCallback(async () => {
    const path = await open({
      multiple: false,
      filters: [
        { name: "音频文件", extensions: ["mp3", "wav", "flac", "m4a", "ogg", "aac"] },
        { name: "全部文件", extensions: ["*"] },
      ],
    });
    if (typeof path !== "string") return;
    audioPathRef.current = path;
    setAudioName(basename(path));
    setRenderData(null);
    resetLabels();
    unloadAudio();
    setLoop(null);
    await Promise.all([loadWaveform(path, computeFitView), loadAudio(path)]);
  }, [loadWaveform, loadAudio, resetLabels, unloadAudio, setLoop, computeFitView]);

  const handleSaveLabels = useCallback(async () => {
    const path = await save({
      defaultPath: "labels.txt",
      filters: [{ name: "Labels", extensions: ["txt"] }],
    });
    if (typeof path === "string") await saveToFile(path);
  }, [saveToFile]);

  const handleLoadLabels = useCallback(async () => {
    const path = await open({
      multiple: false,
      filters: [{ name: "Labels", extensions: ["txt"] }],
    });
    if (typeof path !== "string") return;
    const loaded = await loadFromFile(path);
    const audioDuration = audioInfo?.duration ?? Infinity;
    const normalized = loaded
      .map((label) => ({
        ...label,
        start: Math.max(0, Math.min(label.start, audioDuration)),
        end: Math.max(0, Math.min(label.end, audioDuration)),
      }))
      .filter((label) => label.end - label.start >= 0.05)
      .sort((a, b) => a.start - b.start);
    if (normalized.length !== loaded.length || normalized.some((label, i) => label !== loaded[i])) {
      resetLabels(normalized);
    }
    // 载入后定位到第一段：保持当前缩放级别，仅在其超出可见区时平移过去
    if (normalized.length > 0) {
      const first = normalized[0];
      const dur = viewRange.endSec - viewRange.startSec;
      if (first.start < viewRange.startSec || first.end > viewRange.endSec) {
        const segDur = first.end - first.start;
        const newStart = Math.max(0, first.start - (dur - segDur) / 2);
        setViewRange({ startSec: newStart, endSec: newStart + dur });
      }
      setSelectedId(first.id);
      seek(first.start);
    }
  }, [loadFromFile, audioInfo, resetLabels, viewRange, setViewRange, seek]);

  // ── 波形交互 ──────────────────────────────────────────────────────────────

  // 鼠标点击波形移动播放指针：seek 的同时同步选中对应片段的卡片（空隙处清空）。
  const handleSeek = useCallback(
    (sec: number) => {
      seek(sec);
      const cur = labels.find((l) => sec >= l.start && sec <= l.end);
      setSelectedId(cur ? cur.id : null);
    },
    [seek, labels],
  );

  const handleRegionSelected = useCallback(
    (start: number, end: number) => {
      const label = addLabel(start, end);
      setSelectedId(label.id);
      // 拖完自动开回环，立刻进入精听节奏
      setLoop([start, end]);
      seek(start);
      play(start);
    },
    [addLabel, setLoop, seek, play],
  );

  const handleZoom = useCallback(
    (delta: number, centerSec: number) => {
      if (delta > 0) zoomIn(centerSec);
      else zoomOut(centerSec);
    },
    [zoomIn, zoomOut],
  );

  // 选中片段并播放（回环则换 loop 区间，否则播一段自动停）。
  // pan=true：仅当片段超出当前视图时平移过去，保持缩放级别不变（不改变分辨率）。
  const selectLabel = useCallback(
    (label: Label, pan: boolean) => {
      setSelectedId(label.id);
      if (pan) {
        const dur = viewRange.endSec - viewRange.startSec;
        if (label.start < viewRange.startSec || label.end > viewRange.endSec) {
          const segDur = label.end - label.start;
          const newStart = Math.max(0, label.start - (dur - segDur) / 2);
          setViewRange({ startSec: newStart, endSec: newStart + dur });
        }
      }
      if (loopRange) {
        setLoop([label.start, label.end]);
        seek(label.start);
        play(label.start);
      } else {
        playSegment(label.start, label.end);
      }
    },
    [viewRange, loopRange, setLoop, seek, play, playSegment, setViewRange],
  );

  // ←/→ 片段间导航：有选中按序号 ±1；无选中则跳到 playhead 之后/之前最近的一段。
  const navigateSegment = useCallback(
    (dir: 1 | -1) => {
      if (sortedLabels.length === 0) return;
      const curIdx = sortedLabels.findIndex((l) => l.id === selectedId);
      let target: Label | undefined;
      if (curIdx !== -1) {
        const ni = curIdx + dir;
        if (ni < 0 || ni >= sortedLabels.length) return;
        target = sortedLabels[ni];
      } else if (dir === 1) {
        target = sortedLabels.find((l) => l.start > currentTime + 0.01);
      } else {
        for (let i = sortedLabels.length - 1; i >= 0; i--) {
          if (sortedLabels[i].start < currentTime - 0.01) {
            target = sortedLabels[i];
            break;
          }
        }
      }
      if (target) selectLabel(target, true);
    },
    [sortedLabels, selectedId, currentTime, selectLabel],
  );

  // 边缘拖拽
  const handleLabelEdgeDrag = useCallback(
    (id: string, edge: "start" | "end", newSec: number) => {
      const label = labels.find((l) => l.id === id);
      if (!label) return;
      const clamped = Math.max(0, Math.min(newSec, audioInfo?.duration ?? Infinity));
      const isLooping = loopRange !== null && selectedId === id;
      if (edge === "start") {
        const newStart = Math.min(clamped, label.end - 0.05);
        updateLabel(id, { start: newStart });
        if (isLooping) setLoop([newStart, label.end]);
      } else {
        const newEnd = Math.max(clamped, label.start + 0.05);
        updateLabel(id, { end: newEnd });
        if (isLooping) setLoop([label.start, newEnd]);
      }
    },
    [labels, updateLabel, audioInfo, loopRange, selectedId, setLoop],
  );

  const handleDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      const file = e.dataTransfer.files[0];
      if (!file) return;
      const path = (file as unknown as { path?: string }).path ?? file.name;
      audioPathRef.current = path;
      setAudioName(basename(path));
      setRenderData(null);
      resetLabels();
      unloadAudio();
      setLoop(null);
      await Promise.all([loadWaveform(path, computeFitView), loadAudio(path)]);
    },
    [loadWaveform, loadAudio, resetLabels, unloadAudio, setLoop, computeFitView],
  );

  // ── 导出 ──────────────────────────────────────────────────────────────────

  const handleExport = useCallback(async () => {
    if (!audioPathRef.current || labels.length === 0) return;

    const zipPath = await save({
      defaultPath: "listening_pack.zip",
      filters: [{ name: "ZIP 压缩包", extensions: ["zip"] }],
    });
    if (typeof zipPath !== "string") return;

    const labelData = labels.map((l) => ({ start: l.start, end: l.end, text: l.text }));
    setExportProgress({ step: "splitting", transcribed: 0, total: labels.length });

    let unlisten: (() => void) | null = null;
    try {
      unlisten = await listen<ExportProgress>("listening-pack-export-progress", (event) => {
        setExportProgress(event.payload);
      });
      await exportListeningPack(audioPathRef.current, labelData, zipPath);
    } catch (err) {
      setExportProgress((prev) => ({ ...prev!, step: "error", errorMsg: String(err) }));
    } finally {
      unlisten?.();
    }
  }, [labels]);

  const isPlaying = playState === "playing";

  // 切换 AB 回环：无回环时取当前时间所在/最后一个片段开始回环；有回环则清除。
  const handleToggleLoop = useCallback(() => {
    if (loopRange) {
      setLoop(null);
      return;
    }
    const target =
      labels.find((lb) => currentTime >= lb.start && currentTime <= lb.end) ??
      labels[labels.length - 1];
    if (target) {
      setLoop([target.start, target.end]);
      seek(target.start);
      play(target.start);
    }
  }, [loopRange, labels, currentTime, setLoop, seek, play]);

  // ── 键盘快捷键 ────────────────────────────────────────────────────────────
  //
  // 空格    播放/暂停
  // L      切换回环播放（当前时间所在/最近的 label）
  // ←/→   上一段 / 下一段（片段间导航，保持缩放只平移）
  // H      显示/隐藏快捷键帮助
  //
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.repeat) return;

      const el = document.activeElement as HTMLElement | null;
      const inEditable =
        el?.tagName === "INPUT" || el?.tagName === "TEXTAREA" || el?.isContentEditable === true;
      if (inEditable) return;

      // H：显示 / 隐藏快捷键帮助
      if (e.key === "h" || e.key === "H") {
        e.preventDefault();
        setShowHelp((v) => !v);
        return;
      }

      // Esc：关闭帮助弹窗
      if (e.key === "Escape") {
        setShowHelp(false);
        return;
      }

      // 空格：播放/暂停（聚焦在按钮上时让位给按钮的点击）
      if (e.key === " " || e.code === "Space") {
        if (el?.tagName === "BUTTON") return;
        if (loadingState !== "ready") return;
        e.preventDefault();
        if (playState === "playing") pause();
        else play();
        return;
      }

      // L：切换回环播放
      if (e.key === "l" || e.key === "L") {
        if (loadingState !== "ready") return;
        e.preventDefault();

        if (loopRange !== null) {
          setLoop(null);
          return;
        }

        const target =
          labels.find((lb) => currentTime >= lb.start && currentTime <= lb.end) ??
          labels.reduce<(typeof labels)[0] | null>((best, lb) => {
            if (!best) return lb;
            const distA = Math.min(
              Math.abs(currentTime - best.start),
              Math.abs(currentTime - best.end),
            );
            const distB = Math.min(
              Math.abs(currentTime - lb.start),
              Math.abs(currentTime - lb.end),
            );
            return distB < distA ? lb : best;
          }, null);

        if (!target) return;
        setLoop([target.start, target.end]);
        seek(target.start);
        play(target.start);
        return;
      }

      // ←/→：上一段 / 下一段
      if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
        if (loadingState !== "ready") return;
        e.preventDefault();
        navigateSegment(e.key === "ArrowRight" ? 1 : -1);
        return;
      }
    };

    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [
    playState,
    play,
    pause,
    loadingState,
    navigateSegment,
    currentTime,
    labels,
    loopRange,
    setLoop,
    seek,
  ]);

  return (
    <div style={s.root} onDragOver={(e) => e.preventDefault()} onDrop={handleDrop}>
      <AnnotateToolbar
        audioInfo={audioInfo}
        audioName={audioName}
        loadingState={loadingState}
        labelCount={labels.length}
        hasUnsavedChanges={hasUnsavedChanges}
        onBack={onBack}
        onShowHelp={() => setShowHelp(true)}
        onOpenAudio={handleOpenAudio}
        onSaveLabels={handleSaveLabels}
        onLoadLabels={handleLoadLabels}
        onClearLabels={() => {
          setLoop(null);
          clearLabels();
        }}
        onExport={handleExport}
      />

      {/* 顶部时间轴 */}
      {loadingState === "ready" && (
        <TimeAxis viewRange={viewRange} width={containerWidth} placement="top" />
      )}

      {/* 波形区 */}
      <div ref={containerRef} style={s.waveArea}>
        {loadingState === "idle" && (
          <EmptyState
            icon="♪"
            title="拖入音频文件，或点击「打开音频」"
            hint="支持 MP3 · WAV · FLAC · M4A · OGG · AAC"
          />
        )}
        {loadingState === "decoding" && <EmptyState spinner title="解码中，请稍候…" />}
        {(loadingState === "ready" || renderData !== null) && (
          <WaveformCanvas
            data={renderData}
            viewRange={viewRange}
            duration={audioInfo?.duration ?? 0}
            playhead={currentTime}
            playheadWallMs={playheadWallMs}
            playing={isPlaying}
            speed={speed}
            colors={{
              background: "#F3F4EF",
              wave: "#263F78",
              waveRms: "#263F78",
              centerLine: "#1A2744",
              channelDivider: "#1A2744",
              playhead: "#168049",
              regionFill: "#BAD4FA",
              regionBorder: "#1A4ED8",
              selection: "#1A4ED8",
            }}
            regions={waveformRegions}
            loopRange={loopRange}
            onSeek={handleSeek}
            onRegionSelected={handleRegionSelected}
            onZoom={handleZoom}
            onScroll={scrollBy}
            onRegionEdgeDrag={handleLabelEdgeDrag}
          />
        )}
      </div>

      {/* 时间轴 */}
      {loadingState === "ready" && <TimeAxis viewRange={viewRange} width={containerWidth} />}

      {/* 标注列表 */}
      <LabelList
        labels={labels}
        duration={audioInfo?.duration ?? 0}
        selectedId={selectedId}
        overlappingIds={overlappingIds}
        onSelect={(id) => {
          // 点击卡片：保持当前缩放级别不变，仅当片段超出可见区时平移过去，再选中并播放
          const label = labels.find((l) => l.id === id);
          if (label) selectLabel(label, true);
        }}
        onRemove={(id) => {
          const label = labels.find((l) => l.id === id);
          // 若正在循环的恰是被删片段，清掉回环：去掉高亮背景，让播放正常走下去
          if (label && loopRange && loopRange[0] === label.start && loopRange[1] === label.end) {
            setLoop(null);
          }
          removeLabel(id);
          if (selectedId === id) setSelectedId(null);
        }}
        onUpdateText={(id, text) => updateLabel(id, { text })}
      />

      {/* 底部播放栏：播放 / 回环 / 变速，进度与波形同步 */}
      <AnnotatePlayerBar
        ready={loadingState === "ready"}
        playing={isPlaying}
        looping={loopRange !== null}
        currentTime={currentTime}
        playheadWallMs={playheadWallMs}
        duration={duration || audioInfo?.duration || 0}
        speed={speed}
        labels={labels}
        selectedId={selectedId}
        onPlay={() => play()}
        onPause={pause}
        onToggleLoop={handleToggleLoop}
        onSetSpeed={setSpeed}
        onSeek={seek}
      />

      {/* 导出进度 */}
      {exportProgress && (
        <ExportPanel
          progress={exportProgress}
          onClose={() => setExportProgress(null)}
          onReveal={(path) => {
            import("@tauri-apps/api/core").then(({ invoke }) =>
              invoke("reveal_in_finder", { path }).catch(console.warn),
            );
          }}
        />
      )}

      {/* 快捷键帮助弹窗 */}
      {showHelp && <ShortcutModal onClose={() => setShowHelp(false)} />}
    </div>
  );
}

// ── In 点指示器 ───────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

function EmptyState({
  icon,
  title,
  hint,
  spinner,
}: {
  icon?: string;
  title: string;
  hint?: string;
  spinner?: boolean;
}) {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 8,
      }}
    >
      {spinner ? (
        <div
          style={{
            width: 22,
            height: 22,
            border: `2px solid var(--color-border)`,
            borderTop: `2px solid var(--color-brand)`,
            borderRadius: "50%",
            animation: "spin 0.8s linear infinite",
            marginBottom: 4,
          }}
        />
      ) : (
        <div
          style={{ fontSize: 32, color: "var(--color-border-2)", lineHeight: 1, marginBottom: 4 }}
        >
          {icon}
        </div>
      )}
      <p style={{ fontSize: 14, color: "var(--color-ink-3)", fontWeight: 500 }}>{title}</p>
      {hint && <p style={{ fontSize: 12, color: "var(--color-border-2)" }}>{hint}</p>}
    </div>
  );
}

const s: Record<string, React.CSSProperties> = {
  root: {
    display: "flex",
    flexDirection: "column",
    width: "100vw",
    height: "100vh",
    background:
      "linear-gradient(180deg, var(--color-paper) 0%, var(--color-paper-2) 62%, #efede6 100%)",
    overflow: "hidden",
    userSelect: "none",
  },
  waveArea: {
    flex: 1,
    minHeight: 190,
    position: "relative",
    overflow: "hidden",
    background: "var(--color-paper)",
    borderBottom: `0.5px solid var(--color-border)`,
  },
};
