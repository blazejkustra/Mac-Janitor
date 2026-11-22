import Foundation

/// Checks a preview's planned items again, one by one, without planning anew or walking
/// the search root: each must still exist, not be kept, and pass the guards. Sizes are
/// measured again. A clean still plans the items it is given before removing any.
public enum Revalidation {
    public struct Checked {
        public var actions: [Action]
        /// Items that are now kept or in use.
        public var skips: [Skip]
    }

    public static func check(_ actions: [Action], cfg: Config, guards: Guards) -> Checked {
        let mounts = FS.mountPoints()
        var result = Checked(actions: [], skips: [])
        for var a in actions {
            if cfg.isKept(a.target) {
                result.skips.append(Skip(category: a.category, target: a.target, reason: "kept", kept: true, bytes: a.bytes))
                continue
            }
            guard let path = location(of: a, cfg) else {
                result.actions.append(a)
                continue
            }
            guard FS.exists(path) else { continue }
            if let veto = veto(a, path, guards: guards, mounts: mounts) {
                result.skips.append(Skip(category: a.category, target: a.target, reason: "\(a.reason), but \(veto)"))
                continue
            }
            a.bytes = FS.allocatedSize(path)
            result.actions.append(a)
        }
        return result
    }

    /// The folder or file an action removes; nil for a Docker image.
    static func location(of a: Action, _ cfg: Config) -> String? {
        switch a.category {
        case .dockerImage: return nil
        case .avd: return AVDJanitor.directory(of: a, cfg)
        default: return a.target
        }
    }

    /// The planner's vetoes: something has it open, a LaunchAgent names it, a volume is
    /// mounted inside it, or for packages, something is open in their checkout. Whether a
    /// working directory or watchman keeps a worktree is left to the clean, which plans it again.
    static func veto(_ a: Action, _ path: String, guards: Guards, mounts: Set<String>) -> String? {
        let worktree = a.category == .worktree
        if let veto = guards.veto(path, allowingWorkingDirectories: worktree, allowingWatchman: worktree) { return veto }
        if let mount = mounts.first(where: { $0.hasPrefix(path + "/") }) { return "a volume is mounted at \(mount)" }
        guard a.category == .nodeModules, let checkout = checkout(containing: path) else { return nil }
        return guards.veto(checkout)
    }

    /// The nearest folder above `path` holding a `.git`.
    static func checkout(containing path: String) -> String? {
        var dir = (path as NSString).deletingLastPathComponent
        while dir.count > 1 {
            if FS.exists(dir + "/.git") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}
