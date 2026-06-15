import Foundation

public struct AudioLabel: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String = ""
    ) {
        self.id = id
        self.start = min(start, end)
        self.end = max(start, end)
        self.text = text
    }

    public var duration: TimeInterval {
        max(0, end - start)
    }
}
