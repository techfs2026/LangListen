import Foundation

public enum LabelFileCodec {
    public static func decode(_ contents: String) -> [AudioLabel] {
        contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard columns.count >= 2,
                      let start = TimeInterval(columns[0].trimmingCharacters(in: .whitespaces)),
                      let end = TimeInterval(columns[1].trimmingCharacters(in: .whitespaces))
                else {
                    return nil
                }

                let text = columns.count == 3
                    ? String(columns[2]).trimmingCharacters(in: .whitespaces)
                    : ""
                return AudioLabel(start: start, end: end, text: text)
            }
            .sorted { $0.start < $1.start }
    }

    public static func encode(_ labels: [AudioLabel]) -> String {
        labels
            .sorted { $0.start < $1.start }
            .map { label in
                "\(format(label.start))\t\(format(label.end))\t\(sanitize(label.text))"
            }
            .joined(separator: "\n")
            .appending(labels.isEmpty ? "" : "\n")
    }

    private static func format(_ value: TimeInterval) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
