import Foundation

/// Facts gathered once per run that veto removing a path: something has it
/// open or as its cwd, or a LaunchAgent refers to it.
public struct Guards {
    /// Sorted, so `veto` finds a path and what lies under it by binary search.
    var openPaths: [String]
    /// Working directories of processes, sorted like `openPaths`.
    var cwdPaths: [String]
    /// What the watchman daemon holds open, sorted like `openPaths`. It keeps every root it ever watched.
    var watchmanPaths: [String]
    var launchAgentStrings: [(plist: String, value: String)]
    /// Who holds each path, sorted by path like `openPaths`.
    var holderRecords: [Holder]

    init(openPaths: [String], cwdPaths: [String] = [], watchmanPaths: [String] = [],
         launchAgentStrings: [(plist: String, value: String)], holders: [Holder] = []) {
        self.openPaths = Set(openPaths).sorted()
        self.cwdPaths = Set(cwdPaths).sorted()
        self.watchmanPaths = Set(watchmanPaths).sorted()
        self.launchAgentStrings = launchAgentStrings
        self.holderRecords = holders.sorted { $0.path < $1.path }
    }

    /// Without -b, lsof stats every mount point and file, waiting up to 15 s on each, so
    /// a stalled mount can run it past the timeout. Its paths come from the kernel either way.
    static let lsofArgs = ["lsof", "-n", "-b", "-w", "-Fpcfn"]

    public static func gather() throws -> Guards {
        // Every process of this user: cwd, executables, mapped and open files.
        let r = Shell.run(lsofArgs, timeout: 60)
        // lsof exits 1 over a single unreadable process; no output means no guard at all.
        guard r.status == 0 || (r.status == 1 && !r.stdout.isEmpty) else {
            throw JanitorError("lsof failed, so nothing in use can be told apart: \(r.stderr)")
        }
        let paths = parseLsof(r.stdout)
        var agentStrings: [(String, String)] = []
        let dir = Paths.home.appendingPathComponent("Library/LaunchAgents").path
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".plist") {
            let path = dir + "/" + name
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { continue }
            for s in strings(in: plist) { agentStrings.append((name, s)) }
        }
        return Guards(openPaths: paths.open, cwdPaths: paths.cwd, watchmanPaths: paths.watchman,
                      launchAgentStrings: agentStrings, holders: paths.holders)
    }

    /// Splits `lsof -Fpcfn` output by descriptor and process: each `n` line names the file of the
    /// `f` line before it, held by the process of the `c` line before that.
    static func parseLsof(_ output: String) -> (open: [String], cwd: [String], watchman: [String], holders: [Holder]) {
        var open: [String] = [], cwd: [String] = [], watchman: [String] = []
        var holders: [Holder] = []
        var command = "", fd = "", pid = 0
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                command = ""
                pid = Int(line.dropFirst()) ?? 0
            } else if line.hasPrefix("c") {
                command = String(line.dropFirst())
            } else if line.hasPrefix("f") {
                fd = String(line.dropFirst())
            } else if line.hasPrefix("n/") {
                let path = String(line.dropFirst())
                holders.append(Holder(path: path, process: command, pid: pid, kind: Holder.Kind(fd: fd)))
                if fd == "cwd" {
                    cwd.append(path)
                } else if command == "watchman" {
                    watchman.append(path)
                } else {
                    open.append(path)
                }
            }
        }
        return (open, cwd, watchman, holders)
    }

    static func strings(in value: Any) -> [String] {
        switch value {
        case let s as String: return [s]
        case let a as [Any]: return a.flatMap(strings)
        case let d as [String: Any]: return d.values.flatMap(strings)
        default: return []
        }
    }

    /// Why `path` must not be removed, or nil. With `allowingWorkingDirectories`, a process
    /// whose cwd is in it does not count: it is left in a deleted folder. With `allowingWatchman`,
    /// neither does the watchman daemon, which is told to drop its watch before removal.
    public func veto(_ path: String, allowingWorkingDirectories: Bool = false, allowingWatchman: Bool = false) -> String? {
        if let hit = Self.first(at: path, in: openPaths) { return "in use (open: \(hit))" }
        if !allowingWatchman, let hit = watchmanHold(in: path) { return "in use (open: \(hit))" }
        if !allowingWorkingDirectories, let hit = workingDirectory(in: path) { return "in use (working directory: \(hit))" }
        let prefix = path + "/"
        if let hit = launchAgentStrings.first(where: { $0.value == path || $0.value.contains(prefix) }) {
            return "referenced by LaunchAgent \(hit.plist)"
        }
        return nil
    }

    /// A process working directory at or under `path`.
    public func workingDirectory(in path: String) -> String? { Self.first(at: path, in: cwdPaths) }

    /// A path at or under `path` that the watchman daemon holds open.
    public func watchmanHold(in path: String) -> String? { Self.first(at: path, in: watchmanPaths) }

    /// What `veto` let through for a merged, idle worktree, or nil when nothing holds it.
    public func idleHolders(in path: String) -> String? {
        switch (workingDirectory(in: path) != nil, watchmanHold(in: path) != nil) {
        case (true, true): return "in use only as a shell's working directory and by watchman"
        case (true, false): return "in use only as a shell's working directory"
        case (false, true): return "held only by watchman"
        case (false, false): return nil
        }
    }

    /// Every process holding `path` or something under it, and every LaunchAgent naming it.
    public func holders(in path: String) -> [Holder] {
        let prefix = path + "/"
        let start = Self.lowerBound(path, in: holderRecords.lazy.map(\.path))
        let held = holderRecords[start...].prefix { $0.path == path || $0.path.hasPrefix(prefix) }
        let agents = launchAgentStrings.filter { $0.value == path || $0.value.contains(prefix) }
            .map { Holder(path: $0.value, process: $0.plist, pid: nil, kind: .launchAgent) }
        return Array(held) + agents
    }

    static func lowerBound<C: RandomAccessCollection>(_ key: String, in sorted: C) -> C.Index where C.Element == String {
        var lo = sorted.startIndex, hi = sorted.endIndex
        while lo < hi {
            let mid = sorted.index(lo, offsetBy: sorted.distance(from: lo, to: hi) / 2)
            if sorted[mid] < key { lo = sorted.index(after: mid) } else { hi = mid }
        }
        return lo
    }

    /// `path` itself or the first entry under it, in a sorted list.
    static func first(at path: String, in sorted: [String]) -> String? {
        // Everything under a folder sorts together, starting at the first string not below `path/`.
        func first(notBelow key: String) -> String? {
            let i = lowerBound(key, in: sorted)
            return i < sorted.count ? sorted[i] : nil
        }
        let prefix = path + "/"
        if let hit = first(notBelow: path), hit == path { return hit }
        if let hit = first(notBelow: prefix), hit.hasPrefix(prefix) { return hit }
        return nil
    }
}

/// A process, or a LaunchAgent, holding a path.
public struct Holder: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case cwd
        case openFile = "open-file"
        case executable
        case launchAgent = "launch-agent"

        init(fd: String) {
            switch fd {
            case "cwd": self = .cwd
            case "txt": self = .executable
            default: self = .openFile
            }
        }
    }

    public var path: String
    /// The command name, or the plist file name for a LaunchAgent.
    public var process: String
    public var pid: Int?
    public var kind: Kind
}

/// The watchman daemon, asked to drop its watches on a folder about to go.
enum Watchman {
    static var run: ([String]) -> ShellResult = { Shell.run(["watchman", "--no-spawn"] + $0, timeout: 30) }

    struct WatchList: Codable { var roots: [String] }

    /// Empty when watchman is missing, not running or fails.
    static func roots() -> [String] {
        let r = run(["watch-list"])
        guard r.ok, let list = try? JSONDecoder().decode(WatchList.self, from: Data(r.stdout.utf8)) else { return [] }
        return list.roots
    }

    static func unwatch(_ path: String) {
        for root in roots() where root == path || root.hasPrefix(path + "/") {
            run(["watch-del", root])
        }
    }
}

/// Home folders no walk enters. macOS asks the user before a process reads Desktop,
/// Documents or Downloads, unless it has Full Disk Access; a background job must not
/// ask, so without it they are skipped. Music and Pictures hold media libraries,
/// never checkouts, and reading them asks for media access.
public enum Privacy {
    /// Each opens only with Full Disk Access, and checking asks nothing. Some are missing on
    /// some Macs (the per-user TCC.db is absent on recent macOS), so any one opening is enough.
    static let probes = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        Paths.home.path + "/Library/Application Support/com.apple.TCC/TCC.db",
        Paths.home.path + "/Library/Safari",
        Paths.home.path + "/Library/Containers/com.apple.stocks",
    ]

    public static var hasFullDiskAccess: Bool { canOpenAny(probes) }

    static func canOpenAny(_ paths: [String]) -> Bool {
        paths.contains { path in
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd) }
            return fd >= 0
        }
    }

    public static let askingFolders = ["Desktop", "Documents", "Downloads"].map { Paths.home.path + "/" + $0 }

    public static func unwalked(fullDiskAccess: Bool = hasFullDiskAccess) -> [String] {
        ["Music", "Pictures"].map { Paths.home.path + "/" + $0 } + (fullDiskAccess ? [] : askingFolders)
    }
}
