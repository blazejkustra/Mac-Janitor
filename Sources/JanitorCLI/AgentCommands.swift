import Foundation
import JanitorCore

/// Commands for an agent reviewing the disk: what a run would remove, what it keeps and why,
/// what no rule covers, and removing or pinning one item through the run's own guards.
public enum AgentCLI {
    static let commands: Set<String> = ["plan", "skips", "unknown", "inspect", "remove", "pin", "unpin"]
    static let pathCommands: Set<String> = ["inspect", "remove", "pin", "unpin"]

    public static let usage = """
           janitor plan [--json]
           janitor skips [--json]
           janitor unknown [--min-gb <n>] [--json]
           janitor inspect <path> [--json]
           janitor remove <path> [--yes] [--json]
           janitor pin <path> [--json]
           janitor unpin <path> [--json]

      plan           what a run would remove: path, category, bytes, reason
      skips          what a run keeps and why, with the processes holding each item
      unknown        large folders in the home folder that no category covers (default 1 GB)
      inspect        everything janitor knows about one path and what a run would do with it
      remove         remove one item, only if a run would remove it now; needs --yes
                     unless confirmed at a terminal
      pin, unpin     keep a path for good, or stop keeping it
    """

    struct Arguments: Equatable {
        var command: String
        var path: String?
        var json = false
        var yes = false
        var minGB = 1.0

        static func parse(_ args: [String]) -> Arguments? {
            guard let command = args.first, commands.contains(command) else { return nil }
            var parsed = Arguments(command: command)
            var rest = args.dropFirst()
            while let arg = rest.popFirst() {
                switch arg {
                case "--json": parsed.json = true
                case "--yes" where command == "remove": parsed.yes = true
                case "--min-gb" where command == "unknown":
                    guard let value = rest.popFirst().flatMap(Double.init), value > 0 else { return nil }
                    parsed.minGB = value
                case _ where !arg.hasPrefix("-") && pathCommands.contains(command) && parsed.path == nil:
                    parsed.path = arg
                default: return nil
                }
            }
            return pathCommands.contains(command) == (parsed.path != nil) ? parsed : nil
        }
    }

    static var configURL = Paths.config
    static var isInteractive: () -> Bool = { isatty(STDIN_FILENO) == 1 }
    static var readAnswer: () -> String? = { readLine() }
    /// Where `remove` logs, as a run does; tests swap it to keep the user's log untouched.
    static var log: (String) -> Void = RunLog(dryRun: false, quiet: true).write

    static func main(_ args: [String]) -> Int32 {
        guard let parsed = Arguments.parse(args) else {
            CLI.printError("usage:\n" + usage)
            return 2
        }
        let out = Output(json: parsed.json)
        do {
            let cfg = try Config.load(from: configURL)
            let path = parsed.path.map(resolve)
            switch parsed.command {
            case "plan": return try plan(cfg, out)
            case "skips": return try skips(cfg, out)
            case "unknown": return unknown(cfg, minGB: parsed.minGB, out)
            case "inspect": return try inspect(path!, cfg, out)
            case "remove": return try remove(path!, cfg, yes: parsed.yes, out)
            case "pin": return try pin(path!, cfg, out)
            default: return try unpin(path!, cfg, out)
            }
        } catch {
            return out.refuse("\(error)")
        }
    }

    /// Absolute, symlink-free spelling of a path argument, as rules record their targets.
    static func resolve(_ arg: String) -> String {
        let expanded = (arg as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
        return FS.canonical(FS.normalize(absolute))
    }

    // MARK: - Reading

    struct PlanItem: Encodable {
        var path: String
        var category: JanitorCore.Category
        var bytes: Int64
        var reason: String
    }

    struct PlanOutput: Encodable {
        var items: [PlanItem]
        var issues: [Issue]
    }

    static func planOutput(_ cfg: Config) throws -> PlanOutput {
        let (report, _) = try preview(cfg)
        let items = report.actions.map { PlanItem(path: location($0, cfg), category: $0.category, bytes: $0.bytes, reason: $0.reason) }
        return PlanOutput(items: items, issues: report.issues)
    }

    static func plan(_ cfg: Config, _ out: Output) throws -> Int32 {
        let plan = try planOutput(cfg)
        out.emit(plan) {
            plan.items.map { "\(row($0.category, $0.bytes, $0.path)): \($0.reason)" } + plan.issues.map(issueLine)
        }
        return 0
    }

    struct SkipItem: Encodable {
        var path: String
        var category: JanitorCore.Category
        var bytes: Int64
        var reason: String
        var kept: Bool
        var holders: [Holder]
        var worktree: WorktreeFacts?
    }

    struct SkipsOutput: Encodable {
        var items: [SkipItem]
        var issues: [Issue]
    }

    static func skipsOutput(_ cfg: Config) throws -> SkipsOutput {
        let (report, details) = try preview(cfg)
        return SkipsOutput(items: report.skips.map { skipItem($0, cfg, details) }, issues: report.issues)
    }

    static func skips(_ cfg: Config, _ out: Output) throws -> Int32 {
        let skips = try skipsOutput(cfg)
        out.emit(skips) {
            skips.items.flatMap { item in
                ["\(row(item.category, item.bytes, item.path)): \(item.reason)"] + item.holders.map { "    held by \(holderLine($0))" }
            } + skips.issues.map(issueLine)
        }
        return 0
    }

    static func skipItem(_ s: Skip, _ cfg: Config, _ details: Janitor.RunDetails) -> SkipItem {
        let path = location(s, cfg)
        return SkipItem(path: path, category: s.category, bytes: s.bytes > 0 ? s.bytes : FS.allocatedSize(path),
                        reason: s.reason, kept: s.kept, holders: distinct(details.guards.holders(in: path)),
                        worktree: worktree(containing: path, details))
    }

    static func unknown(_ cfg: Config, minGB: Double, _ out: Output) -> Int32 {
        let folders = UnknownFolders.find(cfg, minBytes: Int64(minGB * 1e9))
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        out.emit(folders) {
            folders.map { "\(size($0.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \($0.path) (modified \(day.string(from: $0.lastModified)))" }
        }
        return 0
    }

    struct Match: Encodable {
        enum Status: String, Encodable { case remove, skip, kept }
        var path: String
        var category: JanitorCore.Category
        var status: Status
        var reason: String
        var bytes: Int64
    }

    struct Inspection: Encodable {
        var path: String
        var exists: Bool
        var bytes: Int64
        var lastModified: Date?
        var pinnedBy: [String]
        /// Why removal would refuse this path whatever the rules say.
        var protected: String?
        var matches: [Match]
        var inside: [Match]
        var holders: [Holder]
        var worktree: WorktreeFacts?
        var verdict: String
    }

    static func inspect(_ path: String, _ cfg: Config, _ out: Output) throws -> Int32 {
        let inspection = try inspection(path, cfg)
        out.emit(inspection) { inspectionLines(inspection) }
        return 0
    }

    static func inspection(_ path: String, _ cfg: Config) throws -> Inspection {
        let (report, details) = try preview(cfg)
        let all = report.actions.map { match($0, cfg) } + report.skips.map { match($0, cfg) }
        let matches = all.filter { $0.path == path }
        var protected: String?
        do { try Safety.check(path) } catch { protected = "\(error)" }
        return Inspection(
            path: path, exists: FS.exists(path), bytes: FS.allocatedSize(path),
            lastModified: FS.newestMTime(path), pinnedBy: cfg.keepEntries(for: path), protected: protected,
            matches: matches, inside: all.filter { $0.path.hasPrefix(path + "/") }.sorted { $0.bytes > $1.bytes },
            holders: distinct(details.guards.holders(in: path)), worktree: worktree(containing: path, details),
            verdict: verdict(matches, protected: protected))
    }

    static func verdict(_ matches: [Match], protected: String?) -> String {
        if let protected { return "never removed: \(protected)" }
        guard let m = matches.first else { return "no category matches it now" }
        switch (m.status, m.category) {
        case (.remove, .largeFile): return "a run lists it as a large file; only `janitor remove` or the app moves it to the Trash"
        case (.remove, _): return "a run removes it (\(m.category.rawValue)): \(m.reason)"
        case (.kept, _): return "pinned, so no run removes it"
        case (.skip, _): return "a run keeps it (\(m.category.rawValue)): \(m.reason)"
        }
    }

    static func inspectionLines(_ i: Inspection) -> [String] {
        var lines = ["\(i.path) (\(i.exists ? size(i.bytes) : "missing"))", "verdict: \(i.verdict)"]
        if !i.pinnedBy.isEmpty { lines.append("pinned by: \(i.pinnedBy.joined(separator: ", "))") }
        if let f = i.worktree {
            lines.append("worktree \(f.path): idle \(String(format: "%.1f", f.idleDays)) days, dirty \(f.dirty), "
                         + "pushed \(f.headOnRemote), merged \(f.mergedIntoMain), merged PR \(f.mergedPR.map(String.init) ?? "none"), "
                         + "open PR \(f.openPR.map(String.init) ?? "none"), locked \(f.locked)")
        }
        lines += i.holders.map { "held by \(holderLine($0))" }
        lines += i.inside.map { "inside: \(row($0.category, $0.bytes, $0.path)) \($0.status.rawValue): \($0.reason)" }
        return lines
    }

    // MARK: - Changing

    struct RemoveOutput: Encodable {
        var path: String
        var category: JanitorCore.Category
        var status: Action.Status
        var bytes: Int64
        var reason: String
        var salvage: String?
        var error: String?
    }

    static func remove(_ path: String, _ cfg: Config, yes: Bool, _ out: Output) throws -> Int32 {
        let r = try removal(path, cfg, yes: yes)
        out.emit(r) {
            ["\(r.status.rawValue) \(row(r.category, r.bytes, path))"
             + (r.salvage.map { " [salvaged: \($0)]" } ?? "") + (r.error.map { " [error: \($0)]" } ?? "")]
        }
        return r.status == .removed ? 0 : 1
    }

    /// A real run acting on `path` alone, so it plans, guards, salvages and records as any clean does.
    /// Throws when nothing was attempted.
    static func removal(_ path: String, _ cfg: Config, yes: Bool) throws -> RemoveOutput {
        if !yes {
            guard isInteractive() else { throw JanitorError("remove needs --yes when not run at a terminal") }
            guard try confirmRemoval(path, cfg) else { throw JanitorError("not removed: not confirmed") }
        }
        log("remove \(path) requested")
        let ids = ids(for: path, cfg)
        let bytes = FS.allocatedSize(path)
        let report = try Janitor.run(cfg, dryRun: false, only: ids, sizes: Dictionary(uniqueKeysWithValues: ids.map { ($0, bytes) }),
                                     log: log)
        if let a = report.actions.first(where: { location($0, cfg) == path }) {
            return RemoveOutput(path: path, category: a.category, status: a.status, bytes: a.bytes, reason: a.reason,
                                salvage: a.salvage, error: a.error)
        }
        if let s = report.skips.first(where: { location($0, cfg) == path }) {
            throw JanitorError("not removed: \(s.reason)")
        }
        throw JanitorError("not removed: no category would remove \(path) now; see `janitor inspect`")
    }

    /// Shows what a run would do with `path` and asks on the terminal.
    static func confirmRemoval(_ path: String, _ cfg: Config) throws -> Bool {
        let report = try Janitor.run(cfg, dryRun: true, only: ids(for: path, cfg))
        guard let a = report.actions.first(where: { location($0, cfg) == path }) else { return true }
        FileHandle.standardError.write(Data("\(row(a.category, a.bytes, path)): \(a.reason)\nRemove it? [y/N] ".utf8))
        return readAnswer()?.lowercased().hasPrefix("y") == true
    }

    /// The action ids a run would give `path`, in every category that can name it.
    static func ids(for path: String, _ cfg: Config) -> Set<String> {
        var ids = Set(JanitorCore.Category.allCases.filter { $0 != .dockerImage }.map { "\($0.rawValue):\(path)" })
        let name = (path as NSString).lastPathComponent
        if (path as NSString).deletingLastPathComponent == FS.canonical(cfg.avdHome), name.hasSuffix(".avd") {
            ids.insert("\(JanitorCore.Category.avd.rawValue):\(name.dropLast(4))")
        }
        return ids
    }

    struct PinOutput: Encodable {
        var path: String
        var pinned: Bool
        var keep: [String]
    }

    static func pin(_ path: String, _ cfg: Config, _ out: Output) throws -> Int32 {
        var cfg = cfg
        cfg.pin(path)
        return try savePin(path, cfg, out)
    }

    static func unpin(_ path: String, _ cfg: Config, _ out: Output) throws -> Int32 {
        var cfg = cfg
        cfg.unpin(path)
        return try savePin(path, cfg, out)
    }

    static func savePin(_ path: String, _ cfg: Config, _ out: Output) throws -> Int32 {
        try cfg.save(to: configURL)
        let entries = cfg.keepEntries(for: path)
        out.emit(PinOutput(path: path, pinned: !entries.isEmpty, keep: entries)) {
            [entries.isEmpty ? "\(path) is not pinned" : "\(path) is pinned by \(entries.joined(separator: ", "))"]
        }
        return 0
    }

    // MARK: - Helpers

    static func preview(_ cfg: Config) throws -> (Report, Janitor.RunDetails) {
        let details = Janitor.RunDetails()
        return (try Janitor.run(cfg, dryRun: true, details: details), details)
    }

    static func location(_ a: Action, _ cfg: Config) -> String { Revalidation.location(of: a, cfg) ?? a.target }

    static func location(_ s: Skip, _ cfg: Config) -> String {
        location(Action(category: s.category, target: s.target, reason: s.reason, bytes: s.bytes, status: .planned), cfg)
    }

    static func match(_ a: Action, _ cfg: Config) -> Match {
        Match(path: location(a, cfg), category: a.category, status: .remove, reason: a.reason, bytes: a.bytes)
    }

    static func match(_ s: Skip, _ cfg: Config) -> Match {
        Match(path: location(s, cfg), category: s.category, status: s.kept ? .kept : .skip, reason: s.reason, bytes: s.bytes)
    }

    /// The facts of the worktree at or around `path`, the innermost one.
    static func worktree(containing path: String, _ details: Janitor.RunDetails) -> WorktreeFacts? {
        details.worktrees.filter { path == $0.path || path.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }
    }

    /// One entry per process and kind of hold; watchman alone can hold thousands of files.
    static func distinct(_ holders: [Holder]) -> [Holder] {
        var seen = Set<String>()
        return holders.filter { seen.insert("\($0.process)|\($0.pid ?? -1)|\($0.kind.rawValue)").inserted }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func row(_ category: JanitorCore.Category, _ bytes: Int64, _ path: String) -> String {
        "\(category.rawValue) \(size(bytes)) \(path)"
    }

    static func holderLine(_ h: Holder) -> String {
        "\(h.process)\(h.pid.map { " (pid \($0))" } ?? "") \(h.kind.rawValue) \(h.path)"
    }

    static func issueLine(_ i: Issue) -> String { "issue \(i.category.rawValue): \(i.message)" }

    /// Prints a value as JSON, or as lines of text.
    struct Output {
        var json: Bool

        func emit<T: Encodable>(_ value: T, text: () -> [String]) {
            if json {
                FileHandle.standardOutput.write((try? JSONEncoder.janitor.encode(value)) ?? Data("{}".utf8))
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                FileHandle.standardOutput.write(Data(text().map { $0 + "\n" }.joined().utf8))
            }
        }

        /// Reports why nothing was done, and returns the exit status for it.
        func refuse(_ message: String) -> Int32 {
            if json {
                emit(["error": message]) { [] }
            } else {
                CLI.printError("janitor: \(message)")
            }
            return 1
        }
    }
}
