import OwlListenKit
import SwiftUI
import UniformTypeIdentifiers

struct InitialListenView: View {
    let onBack: () -> Void

    @StateObject private var model = InitialListenViewModel()
    @State private var showHelp = false

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
        .background(AppTheme.paper2)
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
        HStack(spacing: 6) {
            ToolbarButton("← 返回", action: onBack)
                .keyboardShortcut(.cancelAction)

            ModeTag(text: "初次精听")
            ToolbarDivider()

            ToolbarButton("打开音频", primary: true, action: model.openAudioPanel)
                .keyboardShortcut("o", modifiers: .command)
            ToolbarDivider()

            ToolbarButton("载入标记", action: model.loadLabelsPanel)
                .disabled(model.document == nil)
            ToolbarButton("保存标记", action: model.saveLabelsPanel)
                .disabled(model.labels.isEmpty)
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

            Spacer(minLength: 8)

            ToolbarButton("↓ 导出数据包", dark: true, action: model.exportPackPanel)
                .disabled(model.document == nil || model.labels.isEmpty || model.exportState != nil)
            ToolbarDivider()
            ToolbarButton("快捷键  H", action: { showHelp = true })
                .keyboardShortcut("h", modifiers: [])
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(AppTheme.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var waveformArea: some View {
        ZStack {
            AppTheme.paper

            switch model.loadState {
            case .empty:
                EmptyWaveformState(
                    icon: "♪",
                    title: "拖入音频文件，或点击「打开音频」",
                    hint: "支持 MP3 · WAV · FLAC · M4A · OGG · AAC"
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
                WaveformView(
                    envelope: model.waveform,
                    duration: model.document?.duration ?? 0,
                    viewStart: model.viewStart,
                    viewEnd: model.viewEnd,
                    currentTime: model.currentTime,
                    labels: model.labels,
                    selectedLabelID: model.selectedLabelID,
                    onSeek: model.seek,
                    onCreateLabel: model.addLabel,
                    onSelectLabel: { model.selectLabel($0) },
                    onAdjustLabel: { id, start, end in
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
        .frame(minHeight: 160)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var labelList: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    if model.labels.isEmpty {
                        HStack(spacing: 10) {
                            Text("⋯")
                                .font(.system(size: 20))
                            Text("在波形上拖拽鼠标来添加标注片段")
                                .font(.system(size: 13, design: .monospaced))
                        }
                        .foregroundColor(AppTheme.ink3)
                        .frame(minWidth: 940, maxHeight: .infinity)
                    } else {
                        ForEach(Array(model.labels.enumerated()), id: \.element.id) { index, label in
                            LabelCard(
                                index: index + 1,
                                label: label,
                                selected: label.id == model.selectedLabelID,
                                overlapping: overlappingLabelIDs.contains(label.id),
                                onSelect: { model.selectLabel(label.id) },
                                onDelete: { model.removeLabel(label.id) },
                                onTextChanged: { model.updateLabel(label.id, text: $0) }
                            )
                            .id(label.id)
                        }

                        AddLabelHint()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minHeight: 265, alignment: .leading)
            }
            .onChange(of: model.selectedLabelID) { id in
                guard let id else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(minHeight: 265, maxHeight: 315)
        .background(AppTheme.paper2)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var playerBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(model.document == nil ? "--:--" : formatTime(model.currentTime))
                    .frame(width: 58, alignment: .leading)

                Slider(
                    value: Binding(get: { model.currentTime }, set: model.seek),
                    in: 0...max(model.document?.duration ?? 0, 0.01)
                )
                .disabled(model.document == nil)
                .tint(AppTheme.brand)

                Text(model.document.map { formatTime($0.duration) } ?? "--:--")
                    .foregroundColor(AppTheme.ink3)
                    .frame(width: 58, alignment: .trailing)
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(AppTheme.ink2)
            .padding(.horizontal, 16)
            .padding(.top, 7)

            ZStack {
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(model.document == nil ? AppTheme.ink3 : AppTheme.brand)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(model.document == nil)
                .keyboardShortcut(.space, modifiers: [])

                HStack {
                    Toggle("回环", isOn: Binding(
                        get: { model.isLooping },
                        set: { _ in model.toggleLoop() }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppTheme.brand)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(model.isLooping ? AppTheme.brand : AppTheme.ink3)
                    .disabled(model.labels.isEmpty)
                    .keyboardShortcut("l", modifiers: [])

                    Spacer()

                    HStack(spacing: 8) {
                        Text("变速")
                            .font(.system(size: 13, design: .monospaced))
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
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(AppTheme.paper)
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
            return "Whisper 转写 (\(completed)/\(total))"
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
                AppTheme.paper
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
                    .font(.system(size: 9, design: .monospaced))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("#\(index)")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
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
            }

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
            }

            TextField(
                "备注",
                text: Binding(get: { label.text }, set: onTextChanged)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.paper2)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppTheme.border2, lineWidth: 0.5)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(overlapping ? Color(red: 1, green: 0.96, blue: 0.96) : AppTheme.paper)
        .overlay(alignment: .leading) {
            if selected, !overlapping {
                Rectangle().fill(AppTheme.brand).frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    overlapping ? Color.red.opacity(0.45) : selected ? AppTheme.brand : AppTheme.border2,
                    lineWidth: selected ? 1.5 : 0.5
                )
        }
        .shadow(
            color: AppTheme.ink1.opacity(selected ? 0.12 : 0.05),
            radius: selected ? 8 : 2,
            y: selected ? 4 : 1
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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

private struct EmptyWaveformState: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 32))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("初次精听快捷键")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            ShortcutRow(keys: "Space", description: "播放 / 暂停")
            ShortcutRow(keys: "L", description: "切换回环")
            ShortcutRow(keys: "← / →", description: "上一段 / 下一段")
            ShortcutRow(keys: "⌘ O", description: "打开音频")
        }
        .padding(24)
        .frame(width: 390)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(description)
            Spacer()
        }
    }
}

private struct ModeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(AppTheme.brand)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.brandSoft)
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
            .buttonStyle(ToolbarButtonStyle(primary: primary, dark: dark))
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let primary: Bool
    let dark: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary || dark ? .medium : .regular))
            .foregroundColor(primary || dark ? .white : AppTheme.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                primary
                    ? AppTheme.brand
                    : dark
                        ? AppTheme.ink1
                        : configuration.isPressed
                            ? AppTheme.paper3
                            : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private enum AppTheme {
    static let paper = Color(red: 0.98, green: 0.98, blue: 0.969)
    static let paper2 = Color(red: 0.957, green: 0.953, blue: 0.933)
    static let paper3 = Color(red: 0.933, green: 0.925, blue: 0.918)
    static let ink1 = Color(red: 0.102, green: 0.153, blue: 0.267)
    static let ink2 = Color(red: 0.239, green: 0.31, blue: 0.431)
    static let ink3 = Color(red: 0.518, green: 0.573, blue: 0.667)
    static let brand = Color(red: 0.102, green: 0.306, blue: 0.847)
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
