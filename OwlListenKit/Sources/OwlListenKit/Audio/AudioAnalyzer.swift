@preconcurrency import AVFoundation
import Accelerate
import Foundation

public enum AudioAnalyzer {
    public struct AnalysisResult: Equatable, Sendable {
        public let document: AudioDocument
        public let waveform: WaveformPyramid

        public init(document: AudioDocument, waveform: WaveformPyramid) {
            self.document = document
            self.waveform = waveform
        }
    }

    public static func analyze(
        url: URL,
        baseFramesPerPeak: Int = 256,
        levelScale: Int = 4
    ) throws -> AnalysisResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = max(0, file.length)
        let duration = format.sampleRate > 0
            ? Double(totalFrames) / format.sampleRate
            : 0
        let document = AudioDocument(
            url: url,
            duration: duration,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount)
        )

        guard totalFrames > 0, format.channelCount > 0 else {
            return AnalysisResult(
                document: document,
                waveform: WaveformPyramid(
                    sampleRate: format.sampleRate,
                    totalFrames: totalFrames,
                    levels: []
                )
            )
        }

        let resolvedBaseFrames = max(16, baseFramesPerPeak)
        let resolvedLevelScale = max(2, levelScale)
        let peakCount = Int(ceil(Double(totalFrames) / Double(resolvedBaseFrames)))
        var peaks = [Float](repeating: 0, count: peakCount)
        let chunkSize: AVAudioFrameCount = 262_144
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw AudioAnalyzerError.cannotCreateBuffer
        }

        var absoluteFrame = 0
        while file.framePosition < totalFrames {
            try file.read(into: buffer, frameCount: chunkSize)
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 {
                break
            }

            if let channels = buffer.floatChannelData {
                let channelCount = Int(format.channelCount)
                let channelData = SendableChannelData(baseAddress: channels)
                let chunkStart = absoluteFrame
                let chunkEnd = absoluteFrame + frameLength
                let firstPeak = chunkStart / resolvedBaseFrames
                let lastPeak = min((chunkEnd - 1) / resolvedBaseFrames, peakCount - 1)
                let peaksInChunk = lastPeak - firstPeak + 1

                peaks.withUnsafeMutableBufferPointer { peakBuffer in
                    guard let peakBaseAddress = peakBuffer.baseAddress else {
                        return
                    }
                    let peakData = SendableMutableFloatData(baseAddress: peakBaseAddress)
                    DispatchQueue.concurrentPerform(iterations: peaksInChunk) { offset in
                        let peakIndex = firstPeak + offset
                        let peakStart = peakIndex * resolvedBaseFrames
                        let peakEnd = peakStart + resolvedBaseFrames
                        let localStart = max(chunkStart, peakStart) - chunkStart
                        let localEnd = min(chunkEnd, peakEnd) - chunkStart
                        let length = localEnd - localStart
                        guard length > 0 else {
                            return
                        }

                        var amplitude: Float = 0
                        for channel in 0..<channelCount {
                            var channelPeak: Float = 0
                            vDSP_maxmgv(
                                channelData.baseAddress[channel].advanced(by: localStart),
                                1,
                                &channelPeak,
                                vDSP_Length(length)
                            )
                            amplitude = max(amplitude, channelPeak)
                        }
                        peakData.baseAddress[peakIndex] = max(
                            peakData.baseAddress[peakIndex],
                            amplitude
                        )
                    }
                }
            } else {
                throw AudioAnalyzerError.unsupportedPCMFormat
            }

            absoluteFrame += frameLength
        }

        var levels = [
            WaveformLevel(framesPerPeak: resolvedBaseFrames, samples: peaks),
        ]
        while let previous = levels.last, previous.samples.count > 1 {
            var next = [Float]()
            next.reserveCapacity(
                Int(ceil(Double(previous.samples.count) / Double(resolvedLevelScale)))
            )
            for start in stride(from: 0, to: previous.samples.count, by: resolvedLevelScale) {
                let end = min(previous.samples.count, start + resolvedLevelScale)
                next.append(previous.samples[start..<end].max() ?? 0)
            }
            levels.append(
                WaveformLevel(
                    framesPerPeak: previous.framesPerPeak * resolvedLevelScale,
                    samples: next
                )
            )
        }

        let waveform = WaveformPyramid(
            sampleRate: format.sampleRate,
            totalFrames: totalFrames,
            levels: levels
        )
        return AnalysisResult(document: document, waveform: waveform)
    }
}

private struct SendableChannelData: @unchecked Sendable {
    let baseAddress: UnsafePointer<UnsafeMutablePointer<Float>>
}

private struct SendableMutableFloatData: @unchecked Sendable {
    let baseAddress: UnsafeMutablePointer<Float>
}

public enum AudioAnalyzerError: LocalizedError {
    case cannotCreateBuffer
    case unsupportedPCMFormat

    public var errorDescription: String? {
        switch self {
        case .cannotCreateBuffer:
            return "无法创建音频读取缓冲区。"
        case .unsupportedPCMFormat:
            return "当前音频的 PCM 格式暂不支持。"
        }
    }
}
