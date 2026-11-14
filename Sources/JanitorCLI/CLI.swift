import Foundation
import JanitorCore

/// `janitor run ...`: what launchd runs, and what the applet runs to preview and clean.
/// `janitor reset-cache` drops the saved preview, so the applet scans from scratch next launch.
/// `janitor purge` unlinks what cleans moved aside; runs start it detached.
/// The applet's own executable takes the same arguments, so one code identity holds Full Disk Access.
public enum CLI {
    public static let usage = """
    usage: janitor run [--dry-run] [--json] [--scheduled] [--progress] [--only <file>]
           janitor reset-cache
           janitor purge

      --dry-run      plan only; delete nothing and leave last-run.json alone
      --json         print the report as JSON instead of one line per action
      --scheduled    the launchd entry point: runs only when unpaused and either
                     intervalHours have passed or free space is below lowDiskGB
      --progress     stream what the run is doing to stderr, one "\(ScanEvent.linePrefix)<json>" line per event
      --only <file>  act only on these action ids (one per line), if still planned;
                     "<id>\t<bytes>" also gives the size a preview measured

      reset-cache    forget the saved preview; the app scans from scratch next launch
      purge          delete what earlier cleans moved aside but did not finish deleting
    """

    public struct Options: Equatable {
        public var dryRun = false
        public var json = false
        public var scheduled = false
        public var progress = false
        public var onlyFile: String?

        public static func parse(_ arguments: [String]) -> Options? {
            var args = arguments
            var options = Options()
            if let i = args.firstIndex(of: "--only") {
                guard i + 1 < args.count else { return nil }
                options.onlyFile = args[i + 1]
                args.removeSubrange(i...i + 1)
            }
            guard args.first == "run" else { return nil }
            for flag in args.dropFirst() {
                switch flag {
                case "--dry-run": options.dryRun = true
                case "--json": options.json = true
                case "--scheduled": options.scheduled = true
                case "--progress": options.progress = true
                default: return nil
                }
            }
            return options
        }
    }

    /// Whether these arguments ask for a headless command rather than the applet.
    public static func handles(_ arguments: [String]) -> Bool { ["run", "reset-cache", "purge"].contains(arguments.first) }

    public static func main(_ arguments: [String]) -> Int32 {
        if arguments == ["reset-cache"] { return resetCache() }
        if arguments == ["purge"] { return purge() }
        guard let options = Options.parse(arguments) else {
            printError(usage)
            return 2
        }
        let cfg: Config
        do {
            cfg = try Config.load()
        } catch {
            printError("janitor: \(error)")
            return 1
        }
        let log = RunLog(dryRun: options.dryRun, quiet: options.json)

        if options.scheduled,
           Janitor.scheduledSkipReason(cfg, lastStart: Report.load()?.startedAt, freeBytes: freeDiskBytes()) != nil {
            return 0
        }

        var only: Set<String>?
        var sizes: [String: Int64] = [:]
        if let file = options.onlyFile {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
                printError("janitor: cannot read \(file)")
                return 2
            }
            (only, sizes) = parseOnly(text)
        }
        if options.progress {
            ScanProgress.sink = { event in printError(event.line) }
        }

        do {
            log.write("run started")
            let report = try Janitor.run(cfg, dryRun: options.dryRun, only: only, sizes: sizes, log: log.write)
            let freed = ByteCountFormatter.string(fromByteCount: report.freeBytesAfter - report.freeBytesBefore, countStyle: .file)
            let planned = ByteCountFormatter.string(fromByteCount: report.actions.reduce(0) { $0 + $1.bytes }, countStyle: .file)
            log.write("run finished: \(report.actions.count) actions (\(planned)), free space change \(freed)")
            if options.json {
                FileHandle.standardOutput.write(try JSONEncoder.janitor.encode(report))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return report.actions.contains { $0.status == .failed } ? 1 : 0
        } catch {
            log.write("run failed: \(error)")
            printError("janitor: \(error)")
            return 1
        }
    }

    /// One action id per line, optionally followed by a tab and its measured size.
    static func parseOnly(_ text: String) -> (ids: Set<String>, sizes: [String: Int64]) {
        var ids: Set<String> = []
        var sizes: [String: Int64] = [:]
        for line in text.split(separator: "\n").map(String.init) {
            guard let tab = line.lastIndex(of: "\t"), let bytes = Int64(line[line.index(after: tab)...]) else {
                ids.insert(line)
                continue
            }
            let id = String(line[..<tab])
            ids.insert(id)
            sizes[id] = bytes
        }
        return (ids, sizes)
    }

    static func purge() -> Int32 {
        Janitor.purgeLeftovers(log: RunLog(dryRun: false, quiet: false).write).failures.isEmpty ? 0 : 1
    }

    static func resetCache() -> Int32 {
        let text = SavedPreview.discard() ? "Removed the saved preview." : "No saved preview."
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        return 0
    }

    static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Prints each line unless quiet, and appends real runs to `Paths.log`.
public struct RunLog {
    let dryRun: Bool
    let quiet: Bool
    private let stamp = ISO8601DateFormatter()

    public init(dryRun: Bool, quiet: Bool) {
        self.dryRun = dryRun
        self.quiet = quiet
    }

    public func write(_ text: String) {
        let line = "\(stamp.string(from: Date())) \(dryRun ? "[dry-run] " : "")\(text)\n"
        if !quiet { FileHandle.standardOutput.write(Data(line.utf8)) }
        // Dry runs come from people previewing; the log is the record of real runs.
        guard !dryRun else { return }
        append(line)
    }

    private func append(_ line: String) {
        try? FileManager.default.createDirectory(at: Paths.log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? FileManager.default.attributesOfItem(atPath: Paths.log.path)[.size] as? Int, size > 5_000_000 {
            let old = Paths.log.path + ".1"
            try? FileManager.default.removeItem(atPath: old)
            try? FileManager.default.moveItem(atPath: Paths.log.path, toPath: old)
        }
        if let h = FileHandle(forWritingAtPath: Paths.log.path) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            h.closeFile()
        } else {
            try? Data(line.utf8).write(to: Paths.log)
        }
    }
}
