import Foundation
import JanitorCore

enum Format {
    /// "812 MB", "3.1 GB", "124 GB": decimal units like Finder, at most one decimal.
    static func bytes(_ n: Int64) -> String {
        let parts = byteParts(n)
        return "\(parts.number) \(parts.unit)"
    }

    static func byteParts(_ n: Int64) -> (number: String, unit: String) {
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(max(n, 0)) / 1000
        var i = 0
        while value >= 999.5, i < units.count - 1 {
            value /= 1000
            i += 1
        }
        let digits = value >= 99.95 ? 0 : 1
        return (value.formatted(.number.precision(.fractionLength(0...digits))), units[i])
    }

    /// `/Users/me/x` -> `~/x`.
    static func path(_ p: String) -> String {
        let home = Paths.home.path
        if p == home { return "~" }
        return p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
    }

    /// "now", "5m", "2h", "3d".
    static func span(_ seconds: TimeInterval) -> String {
        let s = abs(seconds)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = span(now.timeIntervalSince(date))
        return s == "now" ? s : "\(s) ago"
    }

    static func absolute(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "worktree untouched for 6 days" -> "Worktree untouched for 6 days."
    static func sentence(_ s: String) -> String {
        guard let first = s.first else { return s }
        let text = first.uppercased() + s.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }

    /// 3 -> "3", 0.5 -> "0.5".
    static func number(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }
}

extension JanitorCore.Category {
    var title: String {
        switch self {
        case .worktree: return "Old worktrees"
        case .nodeModules: return "Worktree dependencies"
        case .dockerImage: return "Docker images"
        case .avd: return "Android emulators"
        case .scratchpad: return "Agent scratch files"
        case .build: return "Build output"
        case .cache: return "Caches"
        case .trash: return "Trash"
        case .largeFile: return "Large forgotten files"
        }
    }

    /// One line under the title in the overview.
    var summary: String {
        switch self {
        case .worktree: return "Merged or abandoned git checkouts"
        case .nodeModules: return "node_modules in idle worktrees"
        case .dockerImage: return "Images no container uses"
        case .avd: return "Unused emulators and images"
        case .scratchpad: return "Old agent session folders"
        case .build: return "Compiled files in idle projects"
        case .cache: return "Data nothing has read lately"
        case .trash: return "Items trashed a while ago"
        case .largeFile: return "Big files unopened for months"
        }
    }

    /// What it is and what removing it costs, for the category's own page and settings.
    func explanation(_ c: Config) -> String {
        switch self {
        case .worktree:
            return "Git worktrees whose branch is merged with nothing left to push (after \(days(c.mergedIdleDays))), "
                + "whose pull request is open but untouched for \(days(c.openPRIdleDays)), or that nobody touched for "
                + "\(days(c.abandonedIdleDays)). Uncommitted changes are saved to a patch first."
        case .nodeModules:
            return "Installed packages inside worktrees untouched for \(days(c.nodeModulesIdleDays)). "
                + "The code stays; run your package manager's install to get them back."
        case .dockerImage:
            return "Docker images no container has used for \(days(c.dockerImageUnusedDays)). Docker downloads them again when needed."
        case .avd:
            return "Android emulators and system images unused for \(days(c.avdUnusedDays)). Android Studio can recreate them."
        case .scratchpad:
            return "Claude Code session folders in /private/tmp untouched for \(days(c.scratchpadIdleDays))."
        case .build:
            return "Build folders such as node_modules, .next, Pods, build and target in git projects that have not "
                + "changed for \(days(c.buildIdleDays)). The next build makes them again."
        case .cache:
            return "Cache entries nothing wrote or read for \(days(c.cacheIdleDays)). Apps and tools rebuild them. "
                + "macOS's own caches are left alone."
        case .trash:
            return "Items that have been in the Trash for over \(days(c.trashIdleDays))."
        case .largeFile:
            return "Files over \(Format.number(c.largeFileMinGB)) GB in your home folder that nobody opened for "
                + "\(days(c.largeFileIdleDays)). Only removed when you clean by hand, and then moved to the Trash."
        }
    }

    private func days(_ n: Double) -> String { n == 1 ? "1 day" : "\(Format.number(n)) days" }

    var symbol: String {
        switch self {
        case .worktree: return "arrow.triangle.branch"
        case .nodeModules: return "shippingbox"
        case .dockerImage: return "square.stack.3d.up"
        case .avd: return "iphone"
        case .scratchpad: return "note.text"
        case .build: return "hammer"
        case .cache: return "archivebox"
        case .trash: return "trash"
        case .largeFile: return "doc.badge.clock"
        }
    }
}
