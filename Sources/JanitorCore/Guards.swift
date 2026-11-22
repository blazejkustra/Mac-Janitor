import Foundation

/// Facts gathered once per run that veto removing a path: something has it
/// open or as its cwd, or a LaunchAgent refers to it.
public struct Guards {
    /// Sorted, so `veto` finds a path and what lies under it by binary search.
    var openPaths: [String]
    /// Working directories of processes, sorted like `openPaths`.
    var cwdPaths: [String]
    var launchAgentStrings: [(plist: String, value: String)]

    init(openPaths: [String], cwdPaths: [String] = [], launchAgentStrings: [(plist: String, value: String)]) {
        self.openPaths = Set(openPaths).sorted()
        self.cwdPaths = Set(cwdPaths).sorted()
        self.launchAgentStrings = launchAgentStrings
    }

    /// Without -b, lsof stats every mount point and file, waiting up to 15 s on each, so
    /// a stalled mount can run it past the timeout. Its paths come from the kernel either way.
    static let lsofArgs = ["lsof", "-n", "-b", "-w", "-Ffn"]

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
        return Guards(openPaths: paths.open, cwdPaths: paths.cwd, launchAgentStrings: agentStrings)
    }

    /// Splits `lsof -Ffn` output by descriptor: each `n` line names the file of the `f` line before it.
    static func parseLsof(_ output: String) -> (open: [String], cwd: [String]) {
        var open: [String] = [], cwd: [String] = []
        var fd = ""
        for line in output.split(separator: "\n") {
            if line.hasPrefix("f") {
                fd = String(line.dropFirst())
            } else if line.hasPrefix("n/") {
                if fd == "cwd" { cwd.append(String(line.dropFirst())) } else { open.append(String(line.dropFirst())) }
            }
        }
        return (open, cwd)
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
    /// whose cwd is in it does not count: it is left in a deleted folder.
    public func veto(_ path: String, allowingWorkingDirectories: Bool = false) -> String? {
        if let hit = Self.first(at: path, in: openPaths) { return "in use (open: \(hit))" }
        if !allowingWorkingDirectories, let hit = workingDirectory(in: path) { return "in use (working directory: \(hit))" }
        let prefix = path + "/"
        if let hit = launchAgentStrings.first(where: { $0.value == path || $0.value.contains(prefix) }) {
            return "referenced by LaunchAgent \(hit.plist)"
        }
        return nil
    }

    /// A process working directory at or under `path`.
    public func workingDirectory(in path: String) -> String? { Self.first(at: path, in: cwdPaths) }

    /// `path` itself or the first entry under it, in a sorted list.
    static func first(at path: String, in sorted: [String]) -> String? {
        // Everything under a folder sorts together, starting at the first string not below `path/`.
        func first(notBelow key: String) -> String? {
            var lo = 0, hi = sorted.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sorted[mid] < key { lo = mid + 1 } else { hi = mid }
            }
            return lo < sorted.count ? sorted[lo] : nil
        }
        let prefix = path + "/"
        if let hit = first(notBelow: path), hit == path { return hit }
        if let hit = first(notBelow: prefix), hit.hasPrefix(prefix) { return hit }
        return nil
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
