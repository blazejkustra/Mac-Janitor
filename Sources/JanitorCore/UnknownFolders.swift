import Foundation

/// A large folder that no category covers, for someone to look at by hand.
public struct UnknownFolder: Codable, Equatable, Sendable {
    public var path: String
    /// Allocated bytes, not counting the listed folders inside it.
    public var bytes: Int64
    public var lastModified: Date
}

/// Finds large folders in the home folder and `~/Library/Developer` that no rule
/// would ever plan: not a worktree, build output, cache, scratch folder, emulator,
/// simulator, large file or the Trash. Reports the deepest folders that reach
/// `minBytes` once the listed folders below them are taken out.
public enum UnknownFolders {
    public static func find(_ cfg: Config, minBytes: Int64) -> [UnknownFolder] {
        let home = FS.canonical(FS.normalize(cfg.worktreeSearchRoot))
        let developer = home + "/Library/Developer"
        let covered = coveredRoots(cfg, home: home)
        var walk = Walk(skipping: Set(Privacy.unwalked() + [home + "/Library"]).union(FS.mountPoints()),
                        covered: covered, minBytes: minBytes,
                        largeFileBytes: Int64(cfg.largeFileMinGB * 1e9))
        _ = walk.total(home, project: nil, homeScanned: true)
        if FS.isDirectory(developer) { _ = walk.total(developer, project: nil, homeScanned: false) }
        return walk.found.sorted { $0.bytes > $1.bytes }
    }

    /// Folders a category owns as a whole.
    static func coveredRoots(_ cfg: Config, home: String) -> Set<String> {
        let roots = cfg.cacheRoots + cfg.scratchRoots + [
            cfg.scratchpadRoot, cfg.avdHome, cfg.androidSDK + "/system-images", cfg.trashDir, cfg.salvageDir,
            home + "/Library/Developer/CoreSimulator/Devices",
        ]
        return Set(roots.map { FS.canonical(FS.normalize($0)) })
    }

    struct Walk {
        let skipping: Set<String>
        let covered: Set<String>
        let minBytes: Int64
        let largeFileBytes: Int64
        var found: [UnknownFolder] = []

        struct Total {
            var bytes: Int64 = 0
            var newest = Date.distantPast
            /// Bytes already shown in `found`, at this folder or below it.
            var listed: Int64 = 0
        }

        /// `homeScanned`: the run's home walk reaches `dir`, so its build output and large files are covered.
        mutating func total(_ dir: String, project outer: String?, homeScanned: Bool) -> Total {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir),
                  !isLinkedWorktree(dir, names: names) else { return Total() }
            let project = names.contains(".git") ? dir : outer
            var sum = Total()
            for name in names {
                let path = dir + "/" + name
                guard !skipping.contains(path), !covered.contains(path), let st = FS.lstatInfo(path) else { continue }
                sum.newest = max(sum.newest, FS.mtime(st))
                let found = homeScanned ? HomeScan.classify(path, st, project: project, largeFileBytes: largeFileBytes) : nil
                if found == .artifact || found == .largeFile || isWorktreeRoot(name, in: dir) { continue }
                if st.st_mode & S_IFMT == S_IFDIR {
                    let child = total(path, project: project, homeScanned: found == .folder)
                    sum.bytes += child.bytes
                    sum.listed += child.listed
                    sum.newest = max(sum.newest, child.newest)
                } else {
                    sum.bytes += Int64(st.st_blocks) * 512
                }
            }
            if sum.bytes - sum.listed >= minBytes {
                found.append(UnknownFolder(path: dir, bytes: sum.bytes - sum.listed, lastModified: sum.newest))
                sum.listed = sum.bytes
            }
            return sum
        }

        func isLinkedWorktree(_ dir: String, names: [String]) -> Bool {
            names.contains(".git") && WorktreeJanitor.gitdir(of: dir).map(WorktreeJanitor.isWorktreeGitdir) == true
        }

        func isWorktreeRoot(_ name: String, in dir: String) -> Bool {
            name.hasSuffix("-worktrees") && FS.exists(dir + "/" + name.dropLast("-worktrees".count) + "/.git")
        }
    }
}
