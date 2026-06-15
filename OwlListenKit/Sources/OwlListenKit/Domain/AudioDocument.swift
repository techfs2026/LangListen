import Foundation

public struct AudioDocument: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int

    public init(url: URL, duration: TimeInterval, sampleRate: Double, channelCount: Int) {
        self.url = url
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct WaveformEnvelope: Equatable, Sendable {
    public let samples: [Float]
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(
        samples: [Float],
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 0
    ) {
        self.samples = samples
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct WaveformLevel: Equatable, Sendable {
    public let framesPerPeak: Int
    public let samples: [Float]

    public init(framesPerPeak: Int, samples: [Float]) {
        self.framesPerPeak = framesPerPeak
        self.samples = samples
    }
}

public struct WaveformPyramid: Equatable, Sendable {
    public let sampleRate: Double
    public let totalFrames: Int64
    public let levels: [WaveformLevel]

    public init(sampleRate: Double, totalFrames: Int64, levels: [WaveformLevel]) {
        self.sampleRate = sampleRate
        self.totalFrames = totalFrames
        self.levels = levels
    }

    public var duration: TimeInterval {
        guard sampleRate > 0 else {
            return 0
        }
        return Double(totalFrames) / sampleRate
    }

    public var finestPeakCount: Int {
        levels.first?.samples.count ?? 0
    }

    public func envelope(
        from requestedStart: TimeInterval,
        to requestedEnd: TimeInterval,
        targetSampleCount: Int
    ) -> WaveformEnvelope {
        guard let finestLevel = levels.first,
              sampleRate > 0,
              totalFrames > 0,
              targetSampleCount > 0
        else {
            return WaveformEnvelope(samples: [])
        }

        let start = min(max(0, requestedStart), duration)
        let end = min(max(start, requestedEnd), duration)
        guard end > start else {
            return WaveformEnvelope(samples: [], startTime: start, endTime: end)
        }

        let startFrame = Int64(floor(start * sampleRate))
        let endFrame = min(totalFrames, Int64(ceil(end * sampleRate)))
        let framesPerOutput = max(
            1,
            Int(ceil(Double(endFrame - startFrame) / Double(targetSampleCount)))
        )
        let level = levels.last(where: { $0.framesPerPeak <= framesPerOutput }) ?? finestLevel
        let firstIndex = max(0, Int(startFrame) / level.framesPerPeak)
        let lastIndex = min(
            level.samples.count,
            Int(ceil(Double(endFrame) / Double(level.framesPerPeak)))
        )
        guard firstIndex < lastIndex else {
            return WaveformEnvelope(samples: [], startTime: start, endTime: end)
        }

        let visible = level.samples[firstIndex..<lastIndex]
        if visible.count <= targetSampleCount {
            return WaveformEnvelope(
                samples: Array(visible),
                startTime: start,
                endTime: end
            )
        }

        let entriesPerOutput = Double(visible.count) / Double(targetSampleCount)
        var output = [Float]()
        output.reserveCapacity(targetSampleCount)
        for outputIndex in 0..<targetSampleCount {
            let lower = visible.index(
                visible.startIndex,
                offsetBy: Int(floor(Double(outputIndex) * entriesPerOutput))
            )
            let upperOffset = min(
                visible.count,
                Int(ceil(Double(outputIndex + 1) * entriesPerOutput))
            )
            let upper = visible.index(visible.startIndex, offsetBy: upperOffset)
            output.append(visible[lower..<upper].max() ?? 0)
        }
        return WaveformEnvelope(samples: output, startTime: start, endTime: end)
    }
}
