import Foundation

/// A build for recording demos (`DEMO=1 install/build-app.sh`): it scans for real, but a
/// clean only reports what it would remove, and its records live in their own folder.
public enum Demo {
    #if DEMO
    public static let isOn = true
    #else
    public static let isOn = false
    #endif
}

#if DEMO
extension Demo {
    static let installedSupport = Paths.home.appendingPathComponent("Library/Application Support/MacJanitor")

    /// Each launch starts from the installed app's settings and Docker history, with no
    /// earlier demo cleans.
    public static func resetData() {
        let fm = FileManager.default
        try? fm.removeItem(at: Paths.support)
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        for name in [Paths.config, Paths.dockerSeen].map(\.lastPathComponent) {
            try? fm.copyItem(at: installedSupport.appendingPathComponent(name), to: Paths.support.appendingPathComponent(name))
        }
    }

    /// Roughly what moving one item aside takes in a real clean.
    static func pace() {
        Thread.sleep(forTimeInterval: 0.08)
    }

    /// Survives `resetData`, so later launches replay the first scan instead of repeating it.
    public static let cachedPreviewURL = Paths.home
        .appendingPathComponent("Library/Application Support/MacJanitor Demo Cache/preview.json")

    public static func cachePreview(_ report: Report) {
        let fm = FileManager.default
        try? fm.createDirectory(at: cachedPreviewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.janitor.encode(report).write(to: cachedPreviewURL, options: .atomic)
    }

    public static func cachedPreview() -> Report? {
        guard let data = try? Data(contentsOf: cachedPreviewURL) else { return nil }
        return try? JSONDecoder.janitor.decode(Report.self, from: data)
    }

    /// Marks `actions` removed without planning or touching anything, paced to take a couple of seconds.
    public static func simulateClean(_ actions: [Action]) -> Report {
        let started = Date()
        let free = freeDiskBytes()
        let step = min(0.08, 2.0 / Double(max(actions.count, 1)))
        let removed = actions.map { a -> Action in
            Thread.sleep(forTimeInterval: step)
            var a = a
            a.status = .removed
            return a
        }
        return Report(startedAt: started, finishedAt: Date(), dryRun: false, freeBytesBefore: free,
                      freeBytesAfter: free, actions: removed, skips: [], issues: [], removalDeferred: true)
    }

    static func cleaned(_ a: Action) -> Action {
        pace()
        var a = a
        a.status = .removed
        return a
    }
}
#endif
