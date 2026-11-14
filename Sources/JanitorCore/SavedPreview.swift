import Foundation

/// The last finished preview, kept so the panel has results to show at launch. It is
/// only ever displayed: a clean acts on a fresh preview.
public struct SavedPreview: Codable {
    public static let currentSchema = 1
    public static let maxAge: TimeInterval = 24 * 3600

    public var schema: Int
    public var savedAt: Date
    /// The settings the preview was planned with.
    public var config: Config
    public var report: Report

    public init(report: Report, config: Config, savedAt: Date = Date()) {
        self.schema = Self.currentSchema
        self.savedAt = savedAt
        self.config = config
        self.report = report
    }

    public func save(to url: URL = Paths.savedPreview) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.janitor.encode(self).write(to: url, options: .atomic)
    }

    /// The saved preview if it still describes this Mac under `config`; otherwise it is discarded.
    public static func load(from url: URL = Paths.savedPreview, config: Config, now: Date = Date()) -> SavedPreview? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let saved = try? JSONDecoder.janitor.decode(SavedPreview.self, from: data),
              saved.isCurrent(config: config, now: now) else {
            discard(at: url)
            return nil
        }
        return saved
    }

    func isCurrent(config: Config, now: Date) -> Bool {
        schema == Self.currentSchema && now.timeIntervalSince(savedAt) < Self.maxAge
            && !config.invalidates(previewPlannedWith: self.config)
    }

    /// Whether there was one to remove.
    @discardableResult
    public static func discard(at url: URL = Paths.savedPreview) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}

extension Config {
    /// Whether a preview planned with `then` can miss something under these settings:
    /// another plan input, a re-enabled category, or an unpinned target.
    public func invalidates(previewPlannedWith then: Config) -> Bool {
        then.planInputs != planInputs
            || !Set(then.disabled).subtracting(disabled).isEmpty
            || !Set(then.keep).subtracting(keep).isEmpty
    }

    private var planInputs: Config {
        var c = self
        c.paused = false
        c.intervalHours = 0
        c.lowDiskGB = 0
        c.keep = []
        c.disabled = []
        return c
    }
}
