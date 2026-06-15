@preconcurrency import AVFoundation
import AppKit
import Combine
import OwlListenKit
import UniformTypeIdentifiers

@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    private(set) var anchorDate = Date()

    func update(to time: TimeInterval) {
        anchorDate = Date()
        currentTime = time
    }
}

@MainActor
final class InitialListenViewModel: ObservableObject {
    enum LoadState: Equatable {
        case empty
        case loading
        case ready
        case failed(String)
    }

    struct ExportState: Equatable {
        enum Step: Equatable {
            case splitting
            case transcribing(completed: Double, total: Int)
            case zipping
            case done
            case failed
        }

        var step: Step
        var outputURL: URL?
        var errorMessage: String?

        var progress: Double {
            switch step {
            case .splitting:
                return 0.1
            case .transcribing(let completed, let total):
                guard total > 0 else {
                    return 0.1
                }
                return 0.1 + (completed / Double(total)) * 0.8
            case .zipping:
                return 0.95
            case .done:
                return 1
            case .failed:
                return 0
            }
        }

        var isFinished: Bool {
            step == .done || step == .failed
        }
    }

    @Published private(set) var loadState: LoadState = .empty
    @Published private(set) var document: AudioDocument?
    @Published private(set) var waveform = WaveformEnvelope(samples: [])
    let playbackClock = PlaybackClock()
    @Published private(set) var isPlaying = false
    @Published private(set) var viewStart: TimeInterval = 0
    @Published private(set) var viewEnd: TimeInterval = 20
    @Published var labels: [AudioLabel] = []
    @Published var selectedLabelID: UUID?
    @Published private(set) var labelSelectionRevision = 0
    @Published private(set) var labelListScrollTargetID: UUID?
    @Published var isLooping = false
    @Published var playbackRate: Float = 1 {
        didSet {
            if isPlaying {
                player?.rate = playbackRate
            }
        }
    }
    @Published private(set) var exportState: ExportState?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var accessedURL: URL?
    private var loadGeneration = 0
    private var waveformPyramid: WaveformPyramid?
    private var waveformSampleCount = 1_600
    private var exportTask: Task<Void, Never>?
    private var pendingLabelSeek: (id: UUID, deadline: Date)?

    var selectedLabel: AudioLabel? {
        labels.first { $0.id == selectedLabelID }
    }

    var currentTime: TimeInterval {
        playbackClock.currentTime
    }

    func openAudioPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开音频"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        loadAudio(url)
    }

    func loadAudio(_ url: URL) {
        closeAudio()
        loadGeneration += 1
        let generation = loadGeneration
        loadState = .loading

        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AudioAnalyzer.analyze(url: url)
                }.value
                guard generation == loadGeneration else {
                    return
                }

                document = result.document
                waveformPyramid = result.waveform
                labels = []
                selectedLabelID = nil
                viewStart = 0
                viewEnd = min(result.document.duration, 20)
                refreshVisibleWaveform()
                configurePlayer(url: url)
                loadState = .ready
            } catch {
                guard generation == loadGeneration else {
                    return
                }
                loadState = .failed(error.localizedDescription)
                releaseSecurityScopedURL()
            }
        }
    }

    func closeAudio() {
        cancelExport()
        loadGeneration += 1
        player?.pause()
        removeTimeObserver()
        player = nil
        playbackClock.update(to: 0)
        isPlaying = false
        document = nil
        waveform = WaveformEnvelope(samples: [])
        waveformPyramid = nil
        viewStart = 0
        viewEnd = 20
        labels = []
        selectedLabelID = nil
        labelListScrollTargetID = nil
        pendingLabelSeek = nil
        isLooping = false
        loadState = .empty
        releaseSecurityScopedURL()
    }

    func togglePlayback() {
        guard let player, let document else {
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        if currentTime >= document.duration - 0.05 {
            seek(to: 0)
            labelListScrollTargetID = labels.first?.id
            labelSelectionRevision += 1
        }
        if isLooping, let selectedLabel,
           currentTime < selectedLabel.start || currentTime >= selectedLabel.end {
            seek(to: selectedLabel.start)
        }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func seek(to time: TimeInterval) {
        guard let document else {
            return
        }
        let clamped = min(max(0, time), document.duration)
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        playbackClock.update(to: clamped)
        reveal(clamped)
        selectLabel(at: clamped)
    }

    func addLabel(start: TimeInterval, end: TimeInterval) {
        guard let document else {
            return
        }
        let lower = min(max(0, start), document.duration)
        let upper = min(max(0, end), document.duration)
        guard upper - lower >= 0.05 else {
            seek(to: lower)
            return
        }

        let label = AudioLabel(start: lower, end: upper)
        labels.append(label)
        labels.sort { $0.start < $1.start }
        selectedLabelID = label.id
        labelListScrollTargetID = label.id
        labelSelectionRevision += 1
        isLooping = true
        seek(to: label.start)
        player?.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func selectLabel(_ id: UUID, play: Bool = true, centerInWaveform: Bool = false) {
        guard let label = labels.first(where: { $0.id == id }) else {
            return
        }
        pendingLabelSeek = (id, Date().addingTimeInterval(1))
        selectedLabelID = id
        labelListScrollTargetID = id
        labelSelectionRevision += 1
        if centerInWaveform {
            centerView(on: label)
        } else {
            reveal(label)
        }
        seek(to: label.start)
        if play {
            player?.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    func selectAdjacentLabel(offset: Int) {
        guard !labels.isEmpty else {
            return
        }
        let currentIndex = labels.firstIndex { $0.id == selectedLabelID }
        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(0, currentIndex + offset), labels.count - 1)
        } else if offset > 0 {
            targetIndex = labels.firstIndex { $0.start > currentTime } ?? labels.count - 1
        } else {
            targetIndex = labels.lastIndex { $0.end < currentTime } ?? 0
        }
        selectLabel(labels[targetIndex].id, centerInWaveform: true)
    }

    func updateLabel(_ id: UUID, start: TimeInterval? = nil, end: TimeInterval? = nil, text: String? = nil) {
        guard let index = labels.firstIndex(where: { $0.id == id }),
              let document
        else {
            return
        }
        var label = labels[index]
        if let start {
            label.start = min(max(0, start), label.end - 0.05)
        }
        if let end {
            label.end = max(label.start + 0.05, min(end, document.duration))
        }
        if let text {
            label.text = text
        }
        labels[index] = label
        labels.sort { $0.start < $1.start }
    }

    func removeLabel(_ id: UUID) {
        labels.removeAll { $0.id == id }
        if pendingLabelSeek?.id == id {
            pendingLabelSeek = nil
        }
        if labelListScrollTargetID == id {
            labelListScrollTargetID = nil
        }
        if selectedLabelID == id {
            selectedLabelID = nil
        }
    }

    func clearLabels() {
        labels = []
        selectedLabelID = nil
        labelListScrollTargetID = nil
        pendingLabelSeek = nil
        isLooping = false
    }

    func toggleLoop() {
        if isLooping {
            isLooping = false
            return
        }

        let target = labels.first {
            currentTime >= $0.start && currentTime <= $0.end
        } ?? labels.min {
            distance(from: currentTime, to: $0) < distance(from: currentTime, to: $1)
        }
        guard let target else {
            return
        }
        selectedLabelID = target.id
        isLooping = true
        seek(to: target.start)
        player?.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func setWaveformWidth(_ width: CGFloat) {
        let nextCount = max(320, min(4_000, Int(width * 2)))
        guard nextCount != waveformSampleCount else {
            return
        }
        waveformSampleCount = nextCount
        refreshVisibleWaveform()
    }

    func loadLabelsPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入标签"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            labels = LabelFileCodec.decode(try String(contentsOf: url))
                .map { label in
                    AudioLabel(
                        id: label.id,
                        start: max(0, min(label.start, document?.duration ?? label.start)),
                        end: max(0, min(label.end, document?.duration ?? label.end)),
                        text: label.text
                    )
                }
                .filter { $0.duration >= 0.05 }
            selectedLabelID = labels.first {
                currentTime >= $0.start && currentTime <= $0.end
            }?.id
            if selectedLabelID != nil {
                labelListScrollTargetID = selectedLabelID
                labelSelectionRevision += 1
            }
        } catch {
            loadState = .failed("无法读取标签：\(error.localizedDescription)")
        }
    }

    func saveLabelsPanel() {
        let panel = NSSavePanel()
        panel.title = "导出标签"
        panel.nameFieldStringValue = "labels.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try LabelFileCodec.encode(labels).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            loadState = .failed("无法保存标签：\(error.localizedDescription)")
        }
    }

    func exportPackPanel() {
        guard let sourceURL = document?.url, !labels.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出数据包"
        panel.nameFieldStringValue = "listening_pack.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let outputURL = panel.url else {
            return
        }

        exportTask?.cancel()
        exportState = ExportState(step: .splitting)
        let exportLabels = labels
        exportTask = Task {
            do {
                try await ListeningPackExporter.export(
                    sourceURL: sourceURL,
                    labels: exportLabels,
                    outputURL: outputURL
                ) { [weak self] progress in
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        switch progress {
                        case .splitting:
                            self.exportState = ExportState(step: .splitting)
                        case .transcribing(let completed, let total):
                            self.exportState = ExportState(
                                step: .transcribing(completed: completed, total: total)
                            )
                        case .zipping:
                            self.exportState = ExportState(step: .zipping)
                        }
                    }
                }
                guard !Task.isCancelled else {
                    return
                }
                exportState = ExportState(step: .done, outputURL: outputURL)
            } catch is CancellationError {
                exportState = nil
            } catch {
                exportState = ExportState(
                    step: .failed,
                    outputURL: outputURL,
                    errorMessage: error.localizedDescription
                )
            }
            exportTask = nil
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        if exportState?.isFinished == false {
            exportState = nil
        }
    }

    func dismissExport() {
        guard exportState?.isFinished == true else {
            return
        }
        exportState = nil
    }

    func revealExport() {
        guard let url = exportState?.outputURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func zoom(by factor: Double) {
        zoom(by: factor, center: currentTime)
    }

    func zoom(by factor: Double, center: TimeInterval) {
        guard let document, document.duration > 0 else {
            return
        }
        let currentSpan = max(0.5, viewEnd - viewStart)
        let nextSpan = min(document.duration, max(0.5, currentSpan * factor))
        let resolvedCenter = min(max(viewStart, center), viewEnd)
        setViewRange(center: resolvedCenter, span: nextSpan)
    }

    func scrollView(by fraction: Double) {
        let span = viewEnd - viewStart
        setViewRange(center: viewStart + span / 2 + span * fraction, span: span)
    }

    func showAll() {
        guard let document else {
            return
        }
        viewStart = 0
        viewEnd = document.duration
        refreshVisibleWaveform()
    }

    private func configurePlayer(url: URL) {
        let player = AVPlayer(url: url)
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
        self.player = player
        let interval = CMTime(seconds: 0.03, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.receivePlayerTime(time.seconds)
            }
        }
    }

    private func receivePlayerTime(_ time: TimeInterval) {
        guard time.isFinite else {
            return
        }
        playbackClock.update(to: time)
        reveal(time)

        if isLooping, let label = selectedLabel, time >= label.end {
            player?.seek(
                to: CMTime(seconds: label.start, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            playbackClock.update(to: label.start)
            return
        }

        if !isLooping, shouldSynchronizeSelection(at: time) {
            selectLabel(at: time)
        }

        if let document, time >= document.duration - 0.02 {
            isPlaying = false
        }
    }

    private func selectLabel(at time: TimeInterval) {
        let nextID = labels.first { time >= $0.start && time <= $0.end }?.id
        guard nextID != selectedLabelID else {
            return
        }
        selectedLabelID = nextID
        if nextID != nil {
            labelListScrollTargetID = nextID
            labelSelectionRevision += 1
        }
    }

    private func shouldSynchronizeSelection(at time: TimeInterval) -> Bool {
        guard let pendingLabelSeek else {
            return true
        }
        guard Date() < pendingLabelSeek.deadline,
              let target = labels.first(where: { $0.id == pendingLabelSeek.id })
        else {
            self.pendingLabelSeek = nil
            return true
        }
        if time >= target.start, time <= target.end {
            self.pendingLabelSeek = nil
            return true
        }
        return false
    }

    private func reveal(_ time: TimeInterval) {
        guard let document, time < viewStart || time > viewEnd else {
            return
        }
        let span = max(0.5, viewEnd - viewStart)
        let start = min(max(0, time), max(0, document.duration - span))
        viewStart = start
        viewEnd = min(document.duration, start + span)
        refreshVisibleWaveform()
    }

    private func refreshVisibleWaveform() {
        waveform = waveformPyramid?.envelope(
            from: viewStart,
            to: viewEnd,
            targetSampleCount: waveformSampleCount
        ) ?? WaveformEnvelope(samples: [])
    }

    private func reveal(_ label: AudioLabel) {
        guard label.start < viewStart || label.end > viewEnd else {
            return
        }
        centerView(on: label)
    }

    private func centerView(on label: AudioLabel) {
        let span = max(0.5, viewEnd - viewStart)
        setViewRange(center: (label.start + label.end) / 2, span: span)
    }

    private func distance(from time: TimeInterval, to label: AudioLabel) -> TimeInterval {
        min(abs(time - label.start), abs(time - label.end))
    }

    private func setViewRange(center: TimeInterval, span: TimeInterval) {
        guard let document else {
            return
        }
        let resolvedSpan = min(document.duration, max(0.5, span))
        let start = min(
            max(0, center - resolvedSpan / 2),
            max(0, document.duration - resolvedSpan)
        )
        viewStart = start
        viewEnd = min(document.duration, start + resolvedSpan)
        refreshVisibleWaveform()
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func releaseSecurityScopedURL() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
