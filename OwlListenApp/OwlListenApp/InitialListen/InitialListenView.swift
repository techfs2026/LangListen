import OwlListenKit
import SwiftUI
import UniformTypeIdentifiers

struct InitialListenView: View {
    let onBack: () -> Void

    @StateObject private var model = InitialListenViewModel()
    @State private var showHelp = false
    @FocusState private var focusedLabelID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if model.loadState == .ready {
                TimeAxisView(start: model.viewStart, end: model.viewEnd, placement: .top)
            }

            waveformArea

            if model.loadState == .ready {
                TimeAxisView(start: model.viewStart, end: model.viewEnd, placement: .bottom)
            }

            labelList
            playerBar
        }
        .background(LearningDeskBackground())
        .onDisappear(perform: model.closeAudio)
        .sheet(isPresented: $showHelp) {
            ShortcutHelpView()
        }
        .overlay {
            if let exportState = model.exportState {
                ExportPanel(
                    state: exportState,
                    onCancel: model.cancelExport,
                    onClose: model.dismissExport,
                    onReveal: model.revealExport
                )
            }
        }
        .background {
            HStack {
                Button("") { model.selectAdjacentLabel(offset: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { model.selectAdjacentLabel(offset: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { focusedLabelID = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(focusedLabelID == nil)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else {
                return false
            }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else {
                    return
                }
                Task { @MainActor in
                    model.loadAudio(url)
                }
            }
            return true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            ToolbarButton("← 返回", action: onBack)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ModeTag(text: "精听模式")
                    Text(model.document?.url.deletingPathExtension().lastPathComponent ?? "声纹书桌")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ink1)
                        .lineLimit(1)
                }
                Text(sessionSubtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            ToolbarButton("打开音频", primary: true, action: model.openAudioPanel)
                .keyboardShortcut("o", modifiers: .command)

            ToolbarButton("载入标记", action: model.loadLabelsPanel)
                .disabled(model.document == nil)
            DirtyToolbarButton(
                title: "保存标记",
                dirty: model.hasUnsavedLabelChanges,
                action: model.saveLabelsPanel
            )
            .disabled(model.labels.isEmpty && !model.hasUnsavedLabelChanges)
            ToolbarButton("清空标记", action: model.clearLabels)
                .disabled(model.labels.isEmpty)

            if model.loadState == .loading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("解码中…")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.orange)
            } else if case .failed = model.loadState {
                Text("加载失败")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.danger)
            } else if !model.labels.isEmpty {
                Text("\(model.labels.count) 段")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.brandSoft)
                    .clipShape(Capsule())
            }

            ToolbarButton("↓ 导出数据包", dark: true, action: model.exportPackPanel)
                .disabled(model.document == nil || model.labels.isEmpty || model.exportState != nil)
            ToolbarDivider()
            ToolbarButton("快捷键  H", action: { showHelp = true })
                .keyboardShortcut("h", modifiers: [])
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(AppTheme.paperElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var sessionSubtitle: String {
        switch model.loadState {
        case .empty:
            return "打开一段音频，开始逐句辨认"
        case .loading:
            return "正在把声音展开成可阅读的声纹"
        case .failed:
            return "音频加载失败，请重新选择"
        case .ready:
            let duration = model.document.map { formatTime($0.duration) } ?? "--:--"
            return "第 1 遍 · \(duration) · 拖拽声纹添加听写片段"
        }
    }

    @ViewBuilder
    private var waveformArea: some View {
        ZStack {
            AppTheme.paperElevated

            switch model.loadState {
            case .empty:
                EmptyWaveformState(
                    icon: "waveform",
                    title: "把音频拖到这里",
                    hint: "OwlListen 会把声音摊开成一份可标注的听写稿"
                )
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("解码中，请稍候…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.ink3)
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.ink3)
                    ToolbarButton("重新选择音频", primary: true, action: model.openAudioPanel)
                }
            case .ready:
                PlaybackWaveform(
                    clock: model.playbackClock,
                    envelope: model.waveform,
                    duration: model.document?.duration ?? 0,
                    viewStart: model.viewStart,
                    viewEnd: model.viewEnd,
                    isPlaying: model.isPlaying,
                    playbackRate: model.playbackRate,
                    labels: model.labels,
                    selectedLabelID: model.selectedLabelID,
                    onSeek: {
                        focusedLabelID = nil
                        model.seek(to: $0)
                    },
                    onCreateLabel: { start, end in
                        focusedLabelID = nil
                        model.addLabel(start: start, end: end)
                    },
                    onSelectLabel: {
                        focusedLabelID = nil
                        model.selectLabel($0)
                    },
                    onAdjustLabel: { id, start, end in
                        focusedLabelID = nil
                        model.updateLabel(id, start: start, end: end)
                    },
                    onWidthChanged: model.setWaveformWidth,
                    onZoom: { factor, center in
                        model.zoom(by: factor, center: center)
                    },
                    onScroll: model.scrollView
                )
            }
        }
        .frame(minHeight: 190)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var labelList: some View {
        Group {
            if model.labels.isEmpty {
                EmptyNotebookState()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .leading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focusedLabelID = nil
                                }

                            HStack(spacing: 10) {
                                ForEach(Array(model.labels.enumerated()), id: \.element.id) { index, label in
                                    LabelCard(
                                        index: index + 1,
                                        label: label,
                                        selected: label.id == model.selectedLabelID,
                                        overlapping: overlappingLabelIDs.contains(label.id),
                                        onSelect: { model.selectLabel(label.id) },
                                        onDelete: { model.removeLabel(label.id) },
                                        onTextChanged: { model.updateLabel(label.id, text: $0) },
                                        focusedLabelID: $focusedLabelID
                                    )
                                    .id(label.id)
                                }

                                AddLabelHint()
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .frame(minHeight: 265, alignment: .leading)
                        }
                        .frame(minWidth: 1, maxWidth: .infinity, minHeight: 265, alignment: .leading)
                    }
                    .onChange(of: model.labelSelectionRevision) { _ in
                        guard let id = model.labelListScrollTargetID else {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 265, maxHeight: 315)
        .background(AppTheme.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var playerBar: some View {
        VStack(spacing: 8) {
            PlaybackProgressRow(
                clock: model.playbackClock,
                duration: model.document?.duration,
                labels: model.labels,
                selectedLabelID: model.selectedLabelID,
                onSeek: {
                    focusedLabelID = nil
                    model.seek(to: $0)
                },
                onSelectLabel: {
                    focusedLabelID = nil
                    model.selectLabel($0, play: false, centerInWaveform: true)
                }
            )
            .modifier(HoverCursor(cursor: model.document == nil ? .arrow : .pointingHand))
            .padding(.horizontal, 18)
            .padding(.top, 9)

            ZStack {
                Button(action: {
                    focusedLabelID = nil
                    model.togglePlayback()
                }) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(model.document == nil ? AppTheme.ink3 : AppTheme.brand)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.brand.opacity(model.document == nil ? 0 : 0.28), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(model.document == nil)
                .keyboardShortcut(.space, modifiers: [])
                .modifier(HoverCursor(cursor: .pointingHand))

                HStack {
                    Toggle("句段回环", isOn: Binding(
                        get: { model.isLooping },
                        set: { _ in model.toggleLoop() }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppTheme.brand)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(model.isLooping ? AppTheme.brand : AppTheme.ink3)
                    .disabled(model.labels.isEmpty)
                    .keyboardShortcut("l", modifiers: [])
                    .modifier(HoverCursor(cursor: .pointingHand))

                    Spacer()

                    HStack(spacing: 8) {
                        Text("慢听速度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.ink3)
                        Picker("变速", selection: $model.playbackRate) {
                            Text("0.5×").tag(Float(0.5))
                            Text("0.75×").tag(Float(0.75))
                            Text("1×").tag(Float(1))
                            Text("1.25×").tag(Float(1.25))
                            Text("1.5×").tag(Float(1.5))
                            Text("1.75×").tag(Float(1.75))
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 360)
                        .disabled(model.document == nil)
                        .modifier(HoverCursor(cursor: .pointingHand))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .background(AppTheme.paperElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var overlappingLabelIDs: Set<UUID> {
        var result = Set<UUID>()
        for firstIndex in model.labels.indices {
            for secondIndex in model.labels.indices where secondIndex > firstIndex {
                let first = model.labels[firstIndex]
                let second = model.labels[secondIndex]
                if first.start < second.end, first.end > second.start {
                    result.insert(first.id)
                    result.insert(second.id)
                }
            }
        }
        return result
    }
}

private struct PlaybackWaveform: View {
    @ObservedObject var clock: PlaybackClock

    let envelope: WaveformEnvelope
    let duration: TimeInterval
    let viewStart: TimeInterval
    let viewEnd: TimeInterval
    let isPlaying: Bool
    let playbackRate: Float
    let labels: [AudioLabel]
    let selectedLabelID: UUID?
    let onSeek: (TimeInterval) -> Void
    let onCreateLabel: (TimeInterval, TimeInterval) -> Void
    let onSelectLabel: (UUID) -> Void
    let onAdjustLabel: (UUID, TimeInterval?, TimeInterval?) -> Void
    let onWidthChanged: (CGFloat) -> Void
    let onZoom: (Double, TimeInterval) -> Void
    let onScroll: (Double) -> Void

    var body: some View {
        WaveformView(
            envelope: envelope,
            duration: duration,
            viewStart: viewStart,
            viewEnd: viewEnd,
            currentTime: clock.currentTime,
            playheadAnchorDate: clock.anchorDate,
            canInterpolatePlayhead: clock.isInterpolating,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            labels: labels,
            selectedLabelID: selectedLabelID,
            onSeek: onSeek,
            onCreateLabel: onCreateLabel,
            onSelectLabel: onSelectLabel,
            onAdjustLabel: onAdjustLabel,
            onWidthChanged: onWidthChanged,
            onZoom: onZoom,
            onScroll: onScroll
        )
    }
}

private struct PlaybackProgressRow: View {
    @ObservedObject var clock: PlaybackClock

    let duration: TimeInterval?
    let labels: [AudioLabel]
    let selectedLabelID: UUID?
    let onSeek: (TimeInterval) -> Void
    let onSelectLabel: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(duration == nil ? "--:--" : formatTime(clock.currentTime))
                .frame(width: 58, alignment: .leading)

            ProgressSlider(
                currentTime: clock.currentTime,
                duration: duration ?? 0,
                enabled: duration != nil,
                labels: labels,
                selectedLabelID: selectedLabelID,
                onSeek: onSeek,
                onSelectLabel: onSelectLabel
            )

            Text(duration.map(formatTime) ?? "--:--")
                .foregroundColor(AppTheme.ink3)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(AppTheme.ink2)
    }
}

private struct LearningDeskBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AppTheme.paper,
                AppTheme.paper2,
                Color(red: 0.943, green: 0.938, blue: 0.912),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct ExportPanel: View {
    let state: InitialListenViewModel.ExportState
    let onCancel: () -> Void
    let onClose: () -> Void
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.ink1)
                    Spacer()
                    if state.isFinished {
                        Button("×", action: onClose)
                            .buttonStyle(.plain)
                            .foregroundColor(AppTheme.ink3)
                            .modifier(HoverCursor(cursor: .pointingHand))
                    }
                }

                if !state.isFinished {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.brand)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ExportStepRow(
                        title: "切割音频",
                        state: stepState(for: .splitting)
                    )
                    ExportStepRow(
                        title: transcriptionTitle,
                        state: stepState(for: .transcribing(completed: 0, total: 0))
                    )
                    ExportStepRow(
                        title: "打包 ZIP",
                        state: stepState(for: .zipping)
                    )
                }

                if case .done = state.step, let outputURL = state.outputURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(outputURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.success)
                            .textSelection(.enabled)
                        ToolbarButton("在 Finder 中显示", action: onReveal)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.successSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if case .failed = state.step {
                    Text(state.errorMessage ?? "导出失败")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppTheme.danger)
                        .textSelection(.enabled)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !state.isFinished {
                    HStack {
                        Spacer()
                        ToolbarButton("取消", action: onCancel)
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(width: 380)
            .background(AppTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
        }
    }

    private var title: String {
        switch state.step {
        case .done:
            return "✓ 导出完成"
        case .failed:
            return "× 导出失败"
        default:
            return "正在导出…"
        }
    }

    private var transcriptionTitle: String {
        if case .transcribing(let completed, let total) = state.step {
            let finished = min(Int(completed), total)
            let percent = Int((completed - floor(completed)) * 100)
            if finished < total, percent > 0 {
                return "Whisper 转写 (\(finished)/\(total)，当前 \(percent)%)"
            }
            return "Whisper 转写 (\(finished)/\(total))"
        }
        return "Whisper 转写"
    }

    private func stepState(
        for target: InitialListenViewModel.ExportState.Step
    ) -> ExportStepRow.State {
        let currentOrder = order(of: state.step)
        let targetOrder = order(of: target)
        if currentOrder > targetOrder || state.step == .done {
            return .done
        }
        if currentOrder == targetOrder, state.step != .failed {
            return .active
        }
        return .pending
    }

    private func order(of step: InitialListenViewModel.ExportState.Step) -> Int {
        switch step {
        case .splitting:
            return 0
        case .transcribing:
            return 1
        case .zipping:
            return 2
        case .done:
            return 3
        case .failed:
            return -1
        }
    }
}

private struct ExportStepRow: View {
    enum State {
        case pending
        case active
        case done
    }

    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .pending:
                    Circle()
                        .stroke(AppTheme.ink3, lineWidth: 1)
                case .active:
                    ProgressView()
                        .controlSize(.small)
                case .done:
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.success)
                }
            }
            .frame(width: 18, height: 18)

            Text(title)
                .font(.system(size: 14, weight: state == .active ? .semibold : .regular))
                    .foregroundColor(state == .pending ? AppTheme.ink3 : AppTheme.ink1)
        }
        .opacity(state == .pending ? 0.45 : 1)
    }
}

private struct TimeAxisView: View {
    enum Placement {
        case top
        case bottom
    }

    let start: TimeInterval
    let end: TimeInterval
    let placement: Placement

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: placement == .top ? .bottom : .top) {
                AppTheme.paperElevated
                ForEach(ticks, id: \.self) { tick in
                    let ratio = (tick - start) / max(end - start, 0.001)
                    VStack(spacing: 2) {
                        if placement == .top {
                            Text(axisTime(tick))
                            tickMark
                        } else {
                            tickMark
                            Text(axisTime(tick))
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.ink3)
                    .position(
                        x: max(18, min(proxy.size.width - 18, proxy.size.width * ratio)),
                        y: 12
                    )
                }
            }
        }
        .frame(height: 24)
        .overlay(alignment: placement == .top ? .bottom : .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var tickMark: some View {
        Rectangle()
            .fill(AppTheme.ink3)
            .frame(width: 0.5, height: 5)
    }

    private var ticks: [TimeInterval] {
        let duration = max(0, end - start)
        guard duration > 0 else {
            return []
        }
        let options: [TimeInterval] = [
            0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600,
        ]
        let ideal = duration / 10
        let interval = options.min { abs($0 - ideal) < abs($1 - ideal) } ?? 1
        var result = [TimeInterval]()
        var tick = ceil(start / interval) * interval
        while tick <= end + 0.000_001 {
            result.append(tick)
            tick += interval
        }
        return result
    }
}

private struct LabelCard: View {
    let index: Int
    let label: AudioLabel
    let selected: Bool
    let overlapping: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTextChanged: (String) -> Void
    let focusedLabelID: FocusState<UUID?>.Binding
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("句段 \(index)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(overlapping ? AppTheme.danger : selected ? AppTheme.brand : AppTheme.ink3)

                if overlapping {
                    Text("⚠ 重叠")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.996, green: 0.886, blue: 0.886))
                        .clipShape(Capsule())
                }

                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.ink3)
                .modifier(HoverCursor(cursor: .pointingHand))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: selectCard)
            .modifier(HoverCursor(cursor: .pointingHand))

            HStack(spacing: 4) {
                Text(formatTime(label.start))
                    .foregroundColor(AppTheme.ink1)
                    .fontWeight(.medium)
                Text("→").foregroundColor(AppTheme.ink3)
                Text(formatTime(label.end))
                    .foregroundColor(AppTheme.ink1)
                    .fontWeight(.medium)
                Text(formatDuration(label.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.ink3)
            }
            .font(.system(size: 13, design: .monospaced))
            .contentShape(Rectangle())
            .onTapGesture(perform: selectCard)
            .modifier(HoverCursor(cursor: .pointingHand))

            if selected {
                HStack(spacing: 4) {
                    Text("←→")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppTheme.paper)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(AppTheme.border2, lineWidth: 0.5)
                        }
                    Text("切换区段")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(AppTheme.ink3)
                .contentShape(Rectangle())
                .onTapGesture(perform: selectCard)
                .modifier(HoverCursor(cursor: .pointingHand))
            }

            TextField(
                "听到的句子 / 难点备注",
                text: Binding(get: { label.text }, set: onTextChanged)
            )
            .textFieldStyle(.plain)
            .focused(focusedLabelID, equals: label.id)
            .onSubmit {
                focusedLabelID.wrappedValue = nil
            }
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(AppTheme.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppTheme.border2, lineWidth: 0.5)
            }
            .modifier(HoverCursor(cursor: .iBeam))

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: selectCard)
                .modifier(HoverCursor(cursor: .pointingHand))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(overlapping ? Color(red: 1, green: 0.96, blue: 0.96) : AppTheme.paperElevated)
        .overlay(alignment: .leading) {
            if selected, !overlapping {
                Rectangle().fill(AppTheme.brand).frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    overlapping
                        ? Color.red.opacity(0.45)
                        : selected
                            ? AppTheme.brand
                            : hovered
                                ? AppTheme.ink3.opacity(0.5)
                                : AppTheme.border2,
                    lineWidth: selected ? 1.5 : hovered ? 1 : 0.5
                )
        }
        .shadow(
            color: AppTheme.ink1.opacity(selected ? 0.12 : hovered ? 0.1 : 0.05),
            radius: selected ? 8 : hovered ? 10 : 2,
            y: selected ? 4 : hovered ? 5 : 1
        )
        .offset(y: selected || hovered ? -2 : 0)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }
    }

    private func selectCard() {
        focusedLabelID.wrappedValue = nil
        onSelect()
    }
}

private struct ProgressSlider: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let enabled: Bool
    let labels: [AudioLabel]
    let selectedLabelID: UUID?
    let onSeek: (TimeInterval) -> Void
    let onSelectLabel: (UUID) -> Void

    @State private var hover: (x: CGFloat, time: TimeInterval)?
    @State private var markerHover: (x: CGFloat, index: Int, label: AudioLabel)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Slider(
                    value: Binding(get: { currentTime }, set: onSeek),
                    in: 0...max(duration, 0.01)
                )
                .disabled(!enabled)
                .tint(AppTheme.brand)
                .padding(.top, 8)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location) where enabled && duration > 0:
                        let x = min(max(0, location.x), proxy.size.width)
                        hover = (x, TimeInterval(x / max(proxy.size.width, 1)) * duration)
                    default:
                        hover = nil
                    }
                }

                if enabled, duration > 0 {
                    ForEach(Array(labels.enumerated()), id: \.element.id) { index, label in
                        LabelStartMarker(
                            index: index + 1,
                            label: label,
                            selected: label.id == selectedLabelID,
                            onHover: { isHovering in
                                let x = min(
                                    max(7, proxy.size.width * CGFloat(label.start / duration)),
                                    proxy.size.width - 7
                                )
                                markerHover = isHovering ? (x, index + 1, label) : nil
                                if isHovering {
                                    hover = nil
                                }
                            },
                            onSelect: { onSelectLabel(label.id) }
                        )
                        .position(
                            x: min(max(7, proxy.size.width * CGFloat(label.start / duration)), proxy.size.width - 7),
                            y: 3
                        )
                    }
                }

                if let markerHover {
                    LabelMarkerTooltip(
                        index: markerHover.index,
                        label: markerHover.label
                    )
                    .position(
                        x: min(max(96, markerHover.x), max(96, proxy.size.width - 96)),
                        y: -18
                    )
                    .allowsHitTesting(false)
                    .zIndex(3)
                } else if let hover {
                    Text(formatTime(hover.time))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.ink1.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .position(
                            x: min(max(34, hover.x), max(34, proxy.size.width - 34)),
                            y: -8
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 30)
        .zIndex(2)
    }
}

private struct LabelStartMarker: View {
    let index: Int
    let label: AudioLabel
    let selected: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: selected ? 10 : 8, weight: .bold))
                .foregroundColor(selected ? AppTheme.brand : AppTheme.ink3.opacity(0.75))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .modifier(HoverCursor(cursor: .pointingHand))
    }
}

private struct LabelMarkerTooltip: View {
    let index: Int
    let label: AudioLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("句段 \(index) · \(formatTime(label.start))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.82))
            Text(summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 190, alignment: .leading)
        .background(AppTheme.ink1.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var summary: String {
        let note = label.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? "未填写备注" : note
    }
}

private struct AddLabelHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("+").font(.system(size: 22))
            Text("拖拽添加\n片段")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(AppTheme.ink3)
        .frame(width: 84, height: 96)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border2, style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
        .opacity(0.45)
    }
}

private struct EmptyNotebookState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(AppTheme.border2)

            VStack(spacing: 5) {
                Text("听写笔记还没有片段")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.ink2)
                Text("在上方声纹上拖出一句话，OwlListen 会自动循环并把它放到这里。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.ink3)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(AppTheme.paperElevated)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct EmptyWaveformState: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AppTheme.border2)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.ink3)
            Text(hint)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.ink3.opacity(0.6))
        }
    }
}

private struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("键盘快捷键")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.ink1)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 32) {
                ShortcutGroup(
                    title: "键盘",
                    rows: [
                        ("空格", "播放 / 暂停"),
                        ("L", "切换回环"),
                        ("← / →", "上一段 / 下一段"),
                        ("H", "显示 / 隐藏帮助"),
                    ]
                )
                ShortcutGroup(
                    title: "鼠标 · 波形",
                    rows: [
                        ("拖拽", "框选新片段（自动回环）"),
                        ("拖边缘", "调整片段边界"),
                        ("单击", "定位播放头"),
                        ("滚轮", "左右平移"),
                        ("⌘ + 滚轮", "缩放"),
                    ]
                )
            }

            HStack(spacing: 4) {
                Text("按")
                ShortcutKey(text: "H")
                Text("或")
                ShortcutKey(text: "Esc")
                Text("关闭")
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundColor(AppTheme.ink3)
            .padding(.top, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(width: 620)
        .background(AppTheme.paper)
        .background {
            HStack {
                Button("") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("") { dismiss() }
                    .keyboardShortcut("h", modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }
}

private struct ShortcutGroup: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(AppTheme.ink3)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ShortcutKey(text: row.0)
                    Text(row.1)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.ink1)
                    Spacer()
                }
                .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShortcutKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(AppTheme.ink2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.paper2)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.border2, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ModeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(AppTheme.brand)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.paper)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.brand.opacity(0.32), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.border2)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }
}

private struct ToolbarButton: View {
    let title: String
    var primary = false
    var dark = false
    let action: () -> Void
    @State private var hovered = false

    init(
        _ title: String,
        primary: Bool = false,
        dark: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.primary = primary
        self.dark = dark
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ToolbarButtonStyle(primary: primary, dark: dark, hovered: hovered))
            .onHover { hovered = $0 }
            .modifier(HoverCursor(cursor: .pointingHand))
    }
}

private struct DirtyToolbarButton: View {
    let title: String
    let dirty: Bool
    let action: () -> Void

    var body: some View {
        ToolbarButton(title, action: action)
            .overlay(alignment: .topTrailing) {
                if dirty {
                    Circle()
                        .fill(AppTheme.danger)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle().stroke(AppTheme.paperElevated, lineWidth: 1.5)
                        }
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.12), value: dirty)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let primary: Bool
    let dark: Bool
    let hovered: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary || dark ? .medium : .regular))
            .foregroundColor(primary || dark ? .white : AppTheme.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                primary
                    ? hovered && isEnabled ? AppTheme.brandHover : AppTheme.brand
                    : dark
                        ? hovered && isEnabled ? AppTheme.ink2 : AppTheme.ink1
                        : (hovered && isEnabled) || configuration.isPressed
                            ? AppTheme.paper3
                            : AppTheme.paper
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        primary
                            ? AppTheme.brand
                            : dark
                                ? AppTheme.ink1
                                : hovered && isEnabled
                                    ? AppTheme.ink3
                                    : AppTheme.border2,
                        lineWidth: 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
    }
}

private enum AppTheme {
    static let paper = Color(red: 0.98, green: 0.98, blue: 0.969)
    static let paper2 = Color(red: 0.957, green: 0.953, blue: 0.933)
    static let paper3 = Color(red: 0.933, green: 0.925, blue: 0.918)
    static let paperElevated = Color(red: 0.992, green: 0.991, blue: 0.979)
    static let ink1 = Color(red: 0.102, green: 0.153, blue: 0.267)
    static let ink2 = Color(red: 0.239, green: 0.31, blue: 0.431)
    static let ink3 = Color(red: 0.518, green: 0.573, blue: 0.667)
    static let brand = Color(red: 0.102, green: 0.306, blue: 0.847)
    static let brandHover = Color(red: 0.075, green: 0.247, blue: 0.72)
    static let brandSoft = Color(red: 0.91, green: 0.933, blue: 0.98)
    static let success = Color(red: 0.086, green: 0.396, blue: 0.204)
    static let successSoft = Color(red: 0.863, green: 0.988, blue: 0.906)
    static let danger = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let dangerSoft = Color(red: 0.996, green: 0.91, blue: 0.902)
    static let border = ink1.opacity(0.09)
    static let border2 = ink1.opacity(0.16)
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0:00.00"
    }
    let minutes = Int(seconds) / 60
    let remainder = seconds - Double(minutes * 60)
    return String(format: "%d:%05.2f", minutes, remainder)
}

private func axisTime(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    return String(format: "%d:%02.0f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    seconds < 1
        ? String(format: "%.0fms", seconds * 1_000)
        : String(format: "%.2fs", seconds)
}
