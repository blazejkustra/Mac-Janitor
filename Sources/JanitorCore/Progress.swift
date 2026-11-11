import Foundation

/// What a run is doing, streamed to the applet while it plans.
public enum ScanEvent: Codable, Sendable {
    /// A step of the plan, in plain words.
    case step(String)
    /// The folder a walk is in right now.
    case folder(String)
    /// A category finished planning: what it would remove and what it keeps.
    case found(Category, actions: [Action], skips: [Skip])

    /// One line of the CLI's `--progress` stream on stderr.
    public static let linePrefix = "@progress "

    public var line: String {
        let json = (try? JSONEncoder.janitorLine.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return Self.linePrefix + json
    }

    /// The event in a stream line, or nil for any other output.
    public static func parse(_ line: Substring) -> ScanEvent? {
        guard line.hasPrefix(linePrefix) else { return nil }
        return try? JSONDecoder.janitor.decode(ScanEvent.self, from: Data(line.dropFirst(linePrefix.count).utf8))
    }
}

/// Where a run reports progress. Unset, reporting costs nothing.
public enum ScanProgress {
    public static var sink: ((ScanEvent) -> Void)?
    /// Folder events are frequent; at most one per interval gets through.
    static var folderInterval: TimeInterval = 0.1
    private static var lastFolder = Date.distantPast

    static func step(_ text: String) {
        sink?(.step(text))
    }

    static func folder(_ path: String) {
        guard let sink else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFolder) >= folderInterval else { return }
        lastFolder = now
        sink(.folder(path))
    }

    static func found(_ category: Category, _ actions: [Action], _ skips: [Skip]) {
        sink?(.found(category, actions: actions.filter { $0.category == category },
                     skips: skips.filter { $0.category == category }))
    }
}

extension JSONEncoder {
    static var janitorLine: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
