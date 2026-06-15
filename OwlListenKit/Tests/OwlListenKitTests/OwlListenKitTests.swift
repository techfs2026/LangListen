@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import OwlListenKit

@Test
func exposesPackageVersion() {
    #expect(OwlListenKit.version == "0.1.0")
}

@Test
func labelFileRoundTripPreservesTimesAndSanitizesText() {
    let labels = [
        AudioLabel(start: 4.25, end: 6.5, text: "weak\tending"),
        AudioLabel(start: 1, end: 2.125, text: "first\nnote"),
    ]

    let encoded = LabelFileCodec.encode(labels)
    let decoded = LabelFileCodec.decode(encoded)

    #expect(decoded.count == 2)
    #expect(decoded[0].start == 1)
    #expect(decoded[0].end == 2.125)
    #expect(decoded[0].text == "first note")
    #expect(decoded[1].text == "weak ending")
}

@Test
func malformedLabelRowsAreIgnored() {
    let decoded = LabelFileCodec.decode(
        """
        invalid
        1.250000\t2.500000\tkeep
        nope\t3.000000\tskip
        """
    )

    #expect(decoded.count == 1)
    #expect(decoded[0].text == "keep")
}

@Test
func analyzesWaveFileIntoPeakPyramidWithoutKeepingFullPCM() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("owllisten-\(UUID().uuidString).wav")
    defer {
        try? FileManager.default.removeItem(at: url)
    }

    let sampleRate = 8_000.0
    let frameCount: AVAudioFrameCount = 8_000
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let samples = buffer.floatChannelData![0]
    for frame in 0..<Int(frameCount) {
        samples[frame] = sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) * 0.5
    }
    var outputFile: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
    try outputFile?.write(from: buffer)
    outputFile = nil

    let result = try AudioAnalyzer.analyze(
        url: url,
        baseFramesPerPeak: 80,
        levelScale: 4
    )
    let envelope = result.waveform.envelope(from: 0.25, to: 0.75, targetSampleCount: 20)

    #expect(abs(result.document.duration - 1) < 0.001)
    #expect(result.document.sampleRate == sampleRate)
    #expect(result.document.channelCount == 1)
    #expect(result.waveform.levels.count > 1)
    #expect(result.waveform.finestPeakCount == 100)
    #expect(envelope.samples.count <= 20)
    #expect(envelope.samples.max() ?? 0 > 0.49)
    #expect(envelope.startTime == 0.25)
    #expect(envelope.endTime == 0.75)
}

@Test
func exportsTauriCompatibleListeningPack() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("owllisten-pack-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let sourceURL = root.appendingPathComponent("source.wav")
    try Data("source".utf8).write(to: sourceURL)
    let ffmpegURL = root.appendingPathComponent("fake-ffmpeg")
    try makeExecutable(
        at: ffmpegURL,
        contents: """
        #!/bin/sh
        for last; do true; done
        printf 'fake mp3' > "$last"
        """
    )
    let outputURL = root.appendingPathComponent("listening_pack.zip")

    try await ListeningPackExporter.export(
        sourceURL: sourceURL,
        labels: [
            AudioLabel(start: 1.25, end: 2.5, text: "human label"),
            AudioLabel(start: 3, end: 4.75, text: "second"),
        ],
        outputURL: outputURL,
        configuration: ListeningPackExportConfiguration(
            ffmpegURL: ffmpegURL,
            transcriber: StubTranscriber()
        ),
        progress: { _ in }
    )

    let metadataData = try unzipEntry("metadata.json", from: outputURL)
    let metadata = try JSONDecoder().decode(ListeningPackMetadata.self, from: metadataData)
    #expect(metadata.version == 1)
    #expect(metadata.segments.map(\.audio) == ["segments/0000.mp3", "segments/0001.mp3"])
    #expect(metadata.segments[0].start == 1.25)
    #expect(metadata.segments[0].end == 2.5)
    #expect(metadata.segments[0].text == "recognized text")
    #expect(metadata.segments[0].label == "human label")
    #expect(try unzipEntry("segments/0000.mp3", from: outputURL) == Data("fake mp3".utf8))
}

@Test
func nativeWhisperSmokeTestWhenConfigured() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["OWLLISTEN_WHISPER_MODEL_PATH"],
          let audioPath = environment["OWLLISTEN_WHISPER_AUDIO_PATH"]
    else {
        return
    }

    let result = try await NativeWhisperTranscriber.transcribe(
        audioURL: URL(fileURLWithPath: audioPath),
        configuration: ListeningPackExportConfiguration(
            whisperModelURL: URL(fileURLWithPath: modelPath)
        )
    )
    #expect(!result.isEmpty)
}

@Test
func resolvesDevelopmentWhisperModelOutsideRepositoryWorkingDirectory() throws {
    let expectedURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("src-tauri/whisper-models/ggml-small.en.bin")

    guard FileManager.default.fileExists(atPath: expectedURL.path) else {
        return
    }

    let originalDirectory = FileManager.default.currentDirectoryPath
    defer {
        FileManager.default.changeCurrentDirectoryPath(originalDirectory)
    }
    FileManager.default.changeCurrentDirectoryPath("/")

    #expect(try ToolResolver.whisperModel() == expectedURL.resolvingSymlinksInPath())
}

private struct StubTranscriber: AudioTranscribing {
    func transcribe(
        audioURLs: [URL],
        modelURL: URL?,
        progress: @escaping @Sendable (Double, Int) async -> Void
    ) async throws -> [String] {
        for index in audioURLs.indices {
            await progress(Double(index + 1), audioURLs.count)
        }
        return audioURLs.map { _ in "recognized text" }
    }
}

private func makeExecutable(at url: URL, contents: String) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}

private func unzipEntry(_ entry: String, from archiveURL: URL) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", archiveURL.path, entry]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return data
}
