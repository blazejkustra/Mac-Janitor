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

    static func cleaned(_ a: Action) -> Action {
        pace()
        var a = a
        a.status = .removed
        return a
    }
}
#endif
