@preconcurrency import AVFoundation
import CWhisper
import Foundation

public struct ListeningPackMetadata: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public let index: Int
        public let audio: String
        public let start: TimeInterval
        public let end: TimeInterval
        public let text: String
        public let label: String

        public init(
            index: Int,
            audio: String,
            start: TimeInterval,
            end: TimeInterval,
            text: String,
            label: String
        ) {
            self.index = index
            self.audio = audio
            self.start = start
            self.end = end
            self.text = text
            self.label = label
        }
    }

    public let version: Int
    public let segments: [Segment]

    public init(version: Int = 1, segments: [Segment]) {
        self.version = version
        self.segments = segments
    }
}

public enum ListeningPackExportProgress: Equatable, Sendable {
    case splitting
    case transcribing(completed: Double, total: Int)
    case zipping
}

public struct ListeningPackExportConfiguration: Sendable {
    public let ffmpegURL: URL?
    public let whisperModelURL: URL?
    public let transcriber: (any AudioTranscribing)?

    public init(
        ffmpegURL: URL? = nil,
        whisperModelURL: URL? = nil,
        transcriber: (any AudioTranscribing)? = nil
    ) {
        self.ffmpegURL = ffmpegURL
        self.whisperModelURL = whisperModelURL
        self.transcriber = transcriber
    }
}

public protocol AudioTranscribing: Sendable {
    func transcribe(
        audioURLs: [URL],
        modelURL: URL?,
        progress: @escaping @Sendable (_ completed: Double, _ total: Int) async -> Void
    ) async throws -> [String]
}

public enum ListeningPackExportError: LocalizedError {
    case noLabels
    case toolNotFound(String)
    case invalidLabel(Int)
    case commandFailed(String, String)
    case audioConversionFailed
    case whisper(String)

    public var errorDescription: String? {
        switch self {
        case .noLabels:
            return "没有可导出的标记片段。"
        case .toolNotFound(let message):
            return message
        case .invalidLabel(let index):
            return "第 \(index + 1) 个标记的起止时间无效。"
        case .commandFailed(let command, let message):
            return "\(command) 执行失败：\(message)"
        case .audioConversionFailed:
            return "无法将音频转换为 Whisper 所需的 16kHz 单声道 PCM。"
        case .whisper(let message):
            return "Whisper 转写失败：\(message)"
        }
    }
}

public enum ListeningPackExporter {
    public static func export(
        sourceURL: URL,
        labels: [AudioLabel],
        outputURL: URL,
        configuration: ListeningPackExportConfiguration = .init(),
        progress: @escaping @Sendable (ListeningPackExportProgress) async -> Void
    ) async throws {
        guard !labels.isEmpty else {
            throw ListeningPackExportError.noLabels
        }

        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("owllisten-export-\(UUID().uuidString)", isDirectory: true)
        let segmentsDirectory = workspace.appendingPathComponent("segments", isDirectory: true)
        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
        }

        await progress(.splitting)
        let ffmpegURL = try configuration.ffmpegURL ?? ToolResolver.ffmpeg()
        let segmentURLs = try await split(
            sourceURL: sourceURL,
            labels: labels,
            outputDirectory: segmentsDirectory,
            ffmpegURL: ffmpegURL
        )

        await progress(.transcribing(completed: 0, total: segmentURLs.count))
        let transcriber = configuration.transcriber ?? NativeWhisperTranscriber.shared
        let transcriptions = try await transcriber.transcribe(
            audioURLs: segmentURLs,
            modelURL: configuration.whisperModelURL
        ) { completed, total in
            await progress(.transcribing(completed: completed, total: total))
        }

        let metadata = ListeningPackMetadata(
            segments: labels.enumerated().map { index, label in
                ListeningPackMetadata.Segment(
                    index: index,
                    audio: String(format: "segments/%04d.mp3", index),
                    start: label.start,
                    end: label.end,
                    text: transcriptions[index],
                    label: label.text
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(
            to: workspace.appendingPathComponent("metadata.json"),
            options: .atomic
        )

        await progress(.zipping)
        try Task.checkCancellation()
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-r", outputURL.path, "metadata.json", "segments"],
            currentDirectoryURL: workspace
        )
    }

    private static func split(
        sourceURL: URL,
        labels: [AudioLabel],
        outputDirectory: URL,
        ffmpegURL: URL
    ) async throws -> [URL] {
        for (index, label) in labels.enumerated() where label.end <= label.start {
            throw ListeningPackExportError.invalidLabel(index)
        }

        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            var nextIndex = 0
            var results = [(Int, URL)]()
            let concurrency = min(4, labels.count)

            func addTask(at index: Int) {
                let label = labels[index]
                let outputURL = outputDirectory
                    .appendingPathComponent(String(format: "%04d.mp3", index))
                group.addTask {
                    try Task.checkCancellation()
                    try await ProcessRunner.run(
                        executableURL: ffmpegURL,
                        arguments: [
                            "-hide_banner", "-loglevel", "error", "-y",
                            "-i", sourceURL.path,
                            "-ss", String(format: "%.6f", label.start),
                            "-t", String(format: "%.6f", label.end - label.start),
                            "-vn", "-ac", "1", "-ar", "16000",
                            "-codec:a", "libmp3lame", "-b:a", "128k",
                            outputURL.path,
                        ]
                    )
                    return (index, outputURL)
                }
            }

            while nextIndex < concurrency {
                addTask(at: nextIndex)
                nextIndex += 1
            }
            while let result = try await group.next() {
                results.append(result)
                if nextIndex < labels.count {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

}

public actor NativeWhisperTranscriber: AudioTranscribing {
    public static let shared = NativeWhisperTranscriber()

    private var contexts: [String: WhisperContextBox] = [:]

    public init() {}

    public static func transcribe(
        audioURL: URL,
        configuration: ListeningPackExportConfiguration = .init()
    ) async throws -> String {
        let transcriber = configuration.transcriber ?? shared
        return try await transcriber.transcribe(
            audioURLs: [audioURL],
            modelURL: configuration.whisperModelURL,
            progress: { _, _ in }
        )[0]
    }

    public func transcribe(
        audioURLs: [URL],
        modelURL: URL?,
        progress: @escaping @Sendable (_ completed: Double, _ total: Int) async -> Void
    ) async throws -> [String] {
        let resolvedModelURL = try modelURL ?? ToolResolver.whisperModel()
        let context = try await loadContext(modelURL: resolvedModelURL)
        var results: [String] = []
        results.reserveCapacity(audioURLs.count)

        for (index, audioURL) in audioURLs.enumerated() {
            try Task.checkCancellation()
            let samples = try await Task.detached(priority: .userInitiated) {
                try AudioPCMConverter.load16kMono(url: audioURL)
            }.value
            let text = try await context.transcribe(samples: samples) { segmentProgress in
                let completed = Double(index) + Double(segmentProgress) / 100
                Task {
                    await progress(completed, audioURLs.count)
                }
            }
            results.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            await progress(Double(index + 1), audioURLs.count)
        }
        return results
    }

    private func loadContext(modelURL: URL) async throws -> WhisperContextBox {
        if let context = contexts[modelURL.path] {
            return context
        }

        let context = try await Task.detached(priority: .userInitiated) {
            var errorPointer: UnsafeMutablePointer<CChar>?
            guard let pointer = owl_whisper_load_model(modelURL.path, &errorPointer) else {
                throw ListeningPackExportError.whisper(consumeCString(errorPointer))
            }
            return WhisperContextBox(pointer: pointer)
        }.value
        contexts[modelURL.path] = context
        return context
    }
}

@MainActor
public final class MicrophoneTranscriber {
    public enum RecordingError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case notRecording

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "没有麦克风权限。请在系统设置中允许 OwlListen 使用麦克风。"
            case .alreadyRecording:
                return "当前已经在录音。"
            case .notRecording:
                return "当前没有正在进行的录音。"
            }
        }
    }

    public private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    public init() {}

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    public func startRecording() async throws {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }
        guard await requestPermission() else {
            throw RecordingError.permissionDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("owllisten-recording-\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
        )
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
        recordingURL = url
        isRecording = true
    }

    public func stopAndTranscribe(
        configuration: ListeningPackExportConfiguration = .init()
    ) async throws -> String {
        guard let recorder, let recordingURL, isRecording else {
            throw RecordingError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        isRecording = false
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        return try await NativeWhisperTranscriber.transcribe(
            audioURL: recordingURL,
            configuration: configuration
        )
    }

    public func cancelRecording() {
        recorder?.stop()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        isRecording = false
    }
}

enum ToolResolver {
    static func ffmpeg() throws -> URL {
        try resolve(
            name: "FFmpeg",
            environmentKey: "OWLLISTEN_FFMPEG_PATH",
            candidates: [
                Bundle.main.resourceURL?.appendingPathComponent("ffmpeg"),
                URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
                URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            ],
            requiresExecutablePermission: true,
            missingMessage: "找不到 FFmpeg。开发环境请安装 ffmpeg，发布版需将 ffmpeg 放入 App Resources。"
        )
    }

    static func whisperModel() throws -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceRepositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try resolve(
            name: "Whisper small.en model",
            environmentKey: "OWLLISTEN_WHISPER_MODEL_PATH",
            candidates: [
                Bundle.main.resourceURL?
                    .appendingPathComponent("whisper-models")
                    .appendingPathComponent("ggml-small.en.bin"),
                Bundle.main.resourceURL?
                    .appendingPathComponent("ggml-small.en.bin"),
                sourceRepositoryRoot
                    .appendingPathComponent("src-tauri/whisper-models/ggml-small.en.bin"),
                currentDirectory
                    .appendingPathComponent("src-tauri/whisper-models/ggml-small.en.bin"),
                currentDirectory
                    .appendingPathComponent("../src-tauri/whisper-models/ggml-small.en.bin"),
            ],
            requiresExecutablePermission: false,
            missingMessage: "找不到 ggml-small.en.bin。模型不会提交到 Git；请放入 App Resources/whisper-models，或设置 OWLLISTEN_WHISPER_MODEL_PATH。"
        )
    }

    private static func resolve(
        name: String,
        environmentKey: String,
        candidates: [URL?],
        requiresExecutablePermission: Bool,
        missingMessage: String
    ) throws -> URL {
        let environmentURL = ProcessInfo.processInfo.environment[environmentKey].map {
            URL(fileURLWithPath: $0)
        }
        for candidate in [environmentURL] + candidates {
            guard let candidate else {
                continue
            }
            let resolvedCandidate = candidate.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: resolvedCandidate.path,
                isDirectory: &isDirectory
            ),
               !isDirectory.boolValue,
               (!requiresExecutablePermission
                   || FileManager.default.isExecutableFile(atPath: resolvedCandidate.path))
            {
                return resolvedCandidate
            }
        }
        throw ListeningPackExportError.toolNotFound("\(name)：\(missingMessage)")
    }
}

private final class WhisperCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let progress: @Sendable (Int) -> Void

    init(progress: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.progress = progress
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }

    func isCancelled() -> Bool {
        lock.withLock {
            cancelled
        }
    }

    func reportProgress(_ value: Int) {
        progress(value)
    }
}

private final class WhisperContextBox: @unchecked Sendable {
    private let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        owl_whisper_free_model(pointer)
    }

    func transcribe(
        samples: [Float],
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> String {
        let token = WhisperCancellationToken(progress: progress)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let userData = Unmanaged.passRetained(token).toOpaque()
                defer {
                    Unmanaged<WhisperCancellationToken>.fromOpaque(userData).release()
                }

                var errorPointer: UnsafeMutablePointer<CChar>?
                let resultPointer = samples.withUnsafeBufferPointer { buffer in
                    owl_whisper_transcribe(
                        self.pointer,
                        buffer.baseAddress,
                        Int32(buffer.count),
                        whisperProgressCallback,
                        whisperCancelCallback,
                        userData,
                        &errorPointer
                    )
                }
                guard let resultPointer else {
                    try Task.checkCancellation()
                    throw ListeningPackExportError.whisper(consumeCString(errorPointer))
                }
                defer {
                    owl_whisper_free_string(resultPointer)
                }
                return String(cString: resultPointer)
            }.value
        } onCancel: {
            token.cancel()
        }
    }
}

private let whisperProgressCallback: @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void = {
    progress, userData in
    guard let userData else {
        return
    }
    Unmanaged<WhisperCancellationToken>
        .fromOpaque(userData)
        .takeUnretainedValue()
        .reportProgress(Int(progress))
}

private let whisperCancelCallback: @convention(c) (UnsafeMutableRawPointer?) -> Bool = {
    userData in
    guard let userData else {
        return false
    }
    return Unmanaged<WhisperCancellationToken>
        .fromOpaque(userData)
        .takeUnretainedValue()
        .isCancelled()
}

private enum AudioPCMConverter {
    static func load16kMono(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw ListeningPackExportError.audioConversionFailed
        }

        let inputCapacity = AVAudioFrameCount(file.length)
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(file.length) * 16_000 / file.processingFormat.sampleRate)
        ) + 1_024
        guard inputCapacity > 0,
              let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: inputCapacity
        ), let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            throw ListeningPackExportError.audioConversionFailed
        }

        try file.read(into: inputBuffer)
        try converter.convert(to: outputBuffer, from: inputBuffer)
        guard let channel = outputBuffer.floatChannelData?[0] else {
            throw ListeningPackExportError.audioConversionFailed
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(outputBuffer.frameLength)
            )
        )
    }
}

private func consumeCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
    guard let pointer else {
        return "未知错误"
    }
    defer {
        owl_whisper_free_string(pointer)
    }
    return String(cString: pointer)
}

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func store(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    func terminate() {
        lock.withLock {
            process?.terminate()
        }
    }
}

private enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) async throws {
        let runningProcess = RunningProcess()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let process = Process()
                    let errorPipe = Pipe()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.currentDirectoryURL = currentDirectoryURL
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = errorPipe
                    process.terminationHandler = { process in
                        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorText = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if process.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: ListeningPackExportError.commandFailed(
                                executableURL.lastPathComponent,
                                errorText.isEmpty
                                    ? "退出码 \(process.terminationStatus)"
                                    : errorText
                            ))
                        }
                    }
                    do {
                        try process.run()
                        runningProcess.store(process)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                runningProcess.terminate()
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }
}
