import Foundation

public enum Janitor {
    static var lockPath = Paths.support.appendingPathComponent("run.lock").path

    /// True while a real run, scheduled or not, holds the run lock.
    public static func isRunning() -> Bool {
        let fd = open(lockPath, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return true
    }

    /// Why a scheduled run should not start now, or nil to run.
    public static func scheduledSkipReason(_ cfg: Config, lastStart: Date?, freeBytes: Int64, now: Date = Date()) -> String? {
        if cfg.paused { return "paused" }
        let lowDisk = freeBytes > 0 && Double(freeBytes) < cfg.lowDiskGB * 1e9
        if let lastStart, !lowDisk, now.timeIntervalSince(lastStart) < cfg.intervalHours * 3600 {
            return "last run under \(cfg.intervalHours) h ago"
        }
        return nil
    }

    /// Plans every enabled rule and, unless `dryRun`, carries the plan out. With
    /// `only`, a real run acts on just those action ids, if they are still planned.
    /// A real run holds an exclusive lock for the duration, so overlapping real runs
    /// fail fast. A dry run takes none: it deletes nothing, and previews must neither
    /// wait for nor block the scheduled run.
    /// `sizes` are the preview's measurements by action id, for the targets a clean
    /// with `only` no longer measures itself.
    public static func run(_ cfg: Config, dryRun: Bool, only: Set<String>? = nil, sizes: [String: Int64] = [:],
                           log: (String) -> Void = { _ in }) throws -> Report {
        var cfg = cfg
        // Planning a category takes up to minutes (fetch, gh, walks); skip those `only` cannot name.
        if let only {
            cfg.disabled += Category.allCases.filter { c in !only.contains { $0.hasPrefix(c.rawValue + ":") } }
        }
        try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let lockFD = dryRun ? nil : try lock()
        defer { lockFD.map { _ = close($0) } }
        // A clean from the applet returns once targets are out of the way, not unlinked.
        FS.deferRemoval = !dryRun && only != nil
        if !dryRun { purgeInBackground() }

        let started = Date()
        let freeBefore = freeDiskBytes()
        ScanProgress.step("Checking which files are in use")
        let guards = try Guards.gather()
        var skips: [Skip] = []
        var issues: [Issue] = []

        ScanProgress.step("Looking for git projects and worktrees")
        let wt = WorktreeJanitor(cfg: cfg, guards: guards, only: only)
        Safety.protectedPaths = (wt.repos + wt.repos.map(WorktreeJanitor.root)
            + [cfg.avdHome, cfg.scratchpadRoot, cfg.trashDir, cfg.androidSDK + "/system-images"] + cfg.cacheRoots)
            .map(FS.canonical)
        let worktrees = wt.plan()
        skips += wt.skips
        issues += wt.issues
        ScanProgress.found(.worktree, worktrees.map(\.action), skips)
        ScanProgress.found(.nodeModules, worktrees.map(\.action), skips)
        if !Privacy.hasFullDiskAccess, let c = [Category.worktree, .nodeModules, .build, .largeFile].first(where: cfg.enabled),
           Privacy.askingFolders.contains(where: { $0.hasPrefix(FS.canonical(FS.normalize(cfg.worktreeSearchRoot)) + "/") }) {
            issues.append(Issue(c, "Desktop, Documents and Downloads are not searched; give janitor Full Disk Access "
                                + "in System Settings > Privacy & Security"))
        }
        ScanProgress.step("Checking Claude Code scratchpads")
        let scratch = cfg.enabled(.scratchpad) ? ScratchpadJanitor.plan(cfg, guards: guards, now: started, skips: &skips) : []
        ScanProgress.found(.scratchpad, scratch, skips)
        ScanProgress.step("Checking Android emulators")
        let avds = cfg.enabled(.avd) ? AVDJanitor.plan(cfg, guards: guards, now: started, skips: &skips) : []
        ScanProgress.found(.avd, avds, skips)
        ScanProgress.step("Checking Docker images")
        let images = cfg.enabled(.dockerImage) ? DockerJanitor.plan(cfg, now: started, skips: &skips, issues: &issues) : []
        ScanProgress.found(.dockerImage, images, skips)
        ScanProgress.step("Searching your home folder for build output and large files")

        let searchRoot = FS.canonical(FS.normalize(cfg.worktreeSearchRoot))
        let unscanned = Set([searchRoot + "/Library", FS.canonical(cfg.trashDir)] + cfg.cacheRoots.map(FS.canonical)
                            + Privacy.unwalked())
        let largeFileBytes = cfg.enabled(.largeFile) ? Int64(cfg.largeFileMinGB * 1e9) : nil
        let scan = !cfg.enabled(.build) && !cfg.enabled(.largeFile) ? HomeScan()
            : only.map { ids in
                HomeScan.named(ids.compactMap { id in id.firstIndex(of: ":").map { String(id[id.index(after: $0)...]) } },
                               root: searchRoot, skipping: unscanned, largeFileBytes: largeFileBytes)
            } ?? HomeScan.scan(searchRoot, skipping: unscanned, largeFileBytes: largeFileBytes)
        // Worktrees and their node_modules are the worktree rules' to judge, and a
        // worktree's node_modules may link into its repo's.
        let worktreeTargets = worktrees.map(\.action.target)
        let nodeModulesOwners = wt.repos + wt.repos.map(WorktreeJanitor.root) + wt.scanned
        func under(_ path: String, _ dirs: [String]) -> Bool { dirs.contains { path == $0 || path.hasPrefix($0 + "/") } }
        let builds = cfg.enabled(.build) ? BuildJanitor.plan(cfg, guards: guards, now: started, scan: scan, owner: { path in
            if under(path, worktreeTargets) { return "worktree" }
            if (path as NSString).lastPathComponent == "node_modules", under(path, nodeModulesOwners) { return "node_modules" }
            return nil
        }, skips: &skips) : []
        ScanProgress.found(.build, builds, skips)
        let large = cfg.enabled(.largeFile) ? LargeFileJanitor.plan(cfg, guards: guards, now: started, scan: scan, skips: &skips) : []
        ScanProgress.found(.largeFile, large, skips)
        ScanProgress.step("Checking app and developer caches")
        let caches = cfg.enabled(.cache) ? CacheJanitor.plan(cfg, guards: guards, now: started, skips: &skips) : []
        ScanProgress.found(.cache, caches, skips)
        ScanProgress.step("Checking the Trash")
        let trash = cfg.enabled(.trash) ? TrashJanitor.plan(cfg, guards: guards, now: started, skips: &skips, issues: &issues) : []
        ScanProgress.found(.trash, trash, skips)

        var actions: [Action] = []
        // Large files are previewed, but only ever removed by name.
        func wanted(_ a: Action) -> Bool { only?.contains(a.id) ?? (dryRun || a.category != .largeFile) }
        func record(_ a: Action) {
            var a = a
            if a.bytes == 0, let size = sizes[a.id] { a.bytes = size }
            actions.append(a)
            let size = ByteCountFormatter.string(fromByteCount: a.bytes, countStyle: .file)
            var line = "\(a.status.rawValue) \(a.category.rawValue) \(a.target) (\(size)): \(a.reason)"
            if let s = a.salvage { line += " [salvaged: \(s)]" }
            if let e = a.error { line += " [error: \(e)]" }
            log(line)
        }
        // Planning can take minutes (fetch, gh); look again at what is in use right before deleting.
        let fresh = dryRun ? guards : try Guards.gather()
        func stillFree(_ a: Action, _ paths: String...) -> Bool {
            guard let veto = paths.lazy.compactMap(fresh.veto).first else { return true }
            skips.append(Skip(category: a.category, target: a.target, reason: "\(a.reason), but \(veto)"))
            return false
        }
        for c in worktrees {
            guard wanted(c.action) && stillFree(c.action, c.action.target, c.checkout) else {
                wt.stayed.append(c.action.target)
                continue
            }
            record(dryRun ? c.action : wt.execute(c))
        }
        for a in scratch where wanted(a) && stillFree(a, a.target) { record(dryRun ? a : ScratchpadJanitor.execute(a)) }
        for a in avds where wanted(a) && stillFree(a, AVDJanitor.directory(of: a, cfg)) {
            record(dryRun ? a : AVDJanitor.execute(a, cfg))
        }
        for a in images where wanted(a) { record(dryRun ? a : DockerJanitor.execute(a)) }
        for a in builds + caches + trash where wanted(a) && stillFree(a, a.target) { record(dryRun ? a : removePath(a)) }
        for a in large where wanted(a) && stillFree(a, a.target) { record(dryRun ? a : LargeFileJanitor.execute(a)) }
        if !dryRun && only == nil { pruneSalvage(cfg, now: started, log: log) }
        for s in skips { log("skip \(s.category.rawValue) \(s.target): \(s.reason)") }
        for i in issues { log("issue \(i.category.rawValue): \(i.message)") }

        // Nobody waits on a scheduled run, so it frees the space before measuring it.
        if !dryRun && !FS.deferRemoval { purgeLeftovers(log: log) }
        let report = Report(startedAt: started, finishedAt: Date(), dryRun: dryRun,
                            freeBytesBefore: freeBefore, freeBytesAfter: freeDiskBytes(),
                            actions: actions, skips: skips, issues: issues,
                            removalDeferred: FS.deferRemoval ? true : nil)
        if !dryRun { try recordRun(report) }
        if !dryRun && FS.deferRemoval { purgeInBackground() }
        return report
    }

    /// The run lock, held exclusively until the descriptor is closed.
    static func lock() throws -> Int32 {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        // A few tries: `isRunning` probes hold the lock shared for an instant.
        for _ in 0..<20 where fd >= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            usleep(50_000)
        }
        if fd >= 0 { close(fd) }
        throw JanitorError("another janitor run is in progress")
    }

    /// Salvaged work outlives its worktree by `abandonedIdleDays`, then goes too.
    static func pruneSalvage(_ cfg: Config, now: Date, log: (String) -> Void) {
        let cutoff = now.addingTimeInterval(-cfg.abandonedIdleDays * 86400)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: cfg.salvageDir)) ?? [] {
            let path = cfg.salvageDir + "/" + name
            guard let st = FS.lstatInfo(path), FS.mtime(st) < cutoff, (try? FS.remove(path)) != nil else { continue }
            log("removed salvage \(path)")
        }
    }

    /// Where a real run's report goes; tests swap it to keep the user's records untouched.
    static var recordRun: (Report) throws -> Void = persist
    static var historyURL = Paths.history
    /// Starts `janitor purge` in its own session, so it outlives this process; tests swap it.
    static var spawnPurge: () -> Void = { spawnDetached([executable, "purge"]) }

    static var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    /// Unlinks what earlier cleans moved aside, without waiting for it.
    public static func purgeInBackground() {
        guard !FS.purgeEntries.isEmpty else { return }
        spawnPurge()
    }

    /// Unlinks what cleans moved aside, logging and recording what that freed.
    @discardableResult
    public static func purgeLeftovers(log: (String) -> Void) -> FS.PurgeResult {
        let started = Date()
        let result = FS.purgeNow()
        for failure in result.failures { log("purge failed: \(failure)") }
        guard result.removed > 0 else { return result }
        log("purged \(result.removed) items (\(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)))")
        try? appendHistory([
            "startedAt": ISO8601DateFormatter().string(from: started),
            "purged": result.removed,
            "purgedBytes": result.bytes,
        ])
        return result
    }

    /// Detached from this process's session and descriptors: not the run lock, nor the
    /// stdout a caller reads to EOF. Runs `argv` in place if it cannot be spawned.
    static func spawnDetached(_ argv: [String]) {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&files, fd, "/dev/null", O_RDWR, 0) }
        let cArgs = argv.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        var pid = pid_t()
        if posix_spawn(&pid, argv[0], &files, &attr, cArgs, environ) != 0 {
            Shell.run(argv, timeout: 3600)
        }
    }

    static func persist(_ report: Report) throws {
        SavedPreview.discard()
        try JSONEncoder.janitor.encode(report).write(to: Paths.lastRun, options: .atomic)
        let summary: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: report.startedAt),
            "freedBytes": report.freedBytes,
            "removed": report.actions.filter { $0.status == .removed }.count,
            "failed": report.actions.filter { $0.status == .failed }.count,
            "removedBytes": report.removedBytes,
        ]
        try appendHistory(summary)
    }

    static func appendHistory(_ summary: [String: Any]) throws {
        var line = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        line.append(0x0A)
        if let h = FileHandle(forWritingAtPath: historyURL.path) {
            h.seekToEndOfFile()
            h.write(line)
            h.closeFile()
        } else {
            try line.write(to: historyURL)
        }
    }
}
