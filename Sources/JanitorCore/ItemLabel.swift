import Foundation

/// How the applet names a target: a human title first, then where it sits.
public struct ItemLabel: Equatable, Sendable {
    public var title: String
    /// From the outermost place inward, e.g. ["worktree agent-a578b4", "apps/web", "node_modules"].
    public var context: [String]

    public init(title: String, context: [String] = []) {
        self.title = title
        self.context = context
    }

    public var contextLine: String { context.joined(separator: " › ") }
}

extension ItemLabel {
    /// `isCheckout` tells whether a folder is a git checkout (has a `.git`).
    public static func describe(_ target: String, _ category: Category, home: String = Paths.home.path,
                                isCheckout: (String) -> Bool = { FS.exists($0 + "/.git") }) -> ItemLabel {
        switch category {
        case .worktree:
            let place = Checkout.locate(target, isCheckout: { $0 == target || isCheckout($0) })
            return ItemLabel(title: place.title, context: [place.worktree == nil ? "copy of the project" : "worktree"])
        case .nodeModules, .build:
            let place = Checkout.locate(parent(target), isCheckout: isCheckout)
            var inside = place.root.map { relative(target, to: $0) } ?? last(target)
            if category == .nodeModules { inside = inside == "node_modules" ? "" : parent(inside) }
            return ItemLabel(title: place.title, context: inside.isEmpty ? [] : [inside])
        case .cache:
            let root = parent(target)
            return ItemLabel(title: shorten(last(target)), context: [cacheRootName(root, home: home)])
        case .trash:
            return ItemLabel(title: last(target), context: ["Trash"])
        case .largeFile:
            return ItemLabel(title: last(target), context: [tilde(parent(target), home: home)])
        case .scratchpad:
            let session = String(last(target).prefix(8))
            return ItemLabel(title: "Session \(session)", context: [scratchpadProject(last(parent(target)), home: home)])
        case .avd where target.hasPrefix("/"):
            let parts = target.split(separator: "/").suffix(3).map(String.init)
            let api = parts.first.map { $0.replacingOccurrences(of: "android-", with: "Android ") } ?? ""
            return ItemLabel(title: "\(api) system image", context: parts.dropFirst().map { $0.replacingOccurrences(of: "_", with: " ") })
        case .avd:
            return ItemLabel(title: target.replacingOccurrences(of: "_", with: " "), context: ["emulator"])
        case .dockerImage:
            return dockerLabel(target)
        }
    }

    /// Where a path sits relative to the checkout holding it.
    struct Checkout {
        var root: String?
        var project: String
        var worktree: String?

        /// "uncut · agent-a578b4" for a worktree, the project name otherwise.
        var title: String { worktree.map { "\(project) · \($0)" } ?? project }

        static func locate(_ path: String, isCheckout: (String) -> Bool) -> Checkout {
            if let root = conventionalWorktree(in: path) {
                return Checkout(root: root, project: projectName(root), worktree: worktreeName(root))
            }
            var dir = path
            while dir.count > 1 {
                if isCheckout(dir) { return Checkout(root: dir, project: projectName(dir), worktree: worktreeName(dir)) }
                dir = parent(dir)
            }
            return Checkout(root: nil, project: last(path), worktree: nil)
        }

        /// The worktree folder in `path`, when it follows one of the conventions `projectName` knows.
        static func conventionalWorktree(in path: String) -> String? {
            let parts = path.split(separator: "/").map(String.init)
            for i in parts.indices where i >= 2 {
                let root = "/" + parts[...i].joined(separator: "/")
                if projectName(root) != parts[i] { return root }
            }
            return nil
        }

        /// The repo a worktree belongs to, by the folder conventions agents use:
        /// `<repo>/.claude/worktrees/<name>`, `.t3/worktrees/<repo>/<name>`, `<repo>-worktrees/<name>`.
        static func projectName(_ checkout: String) -> String {
            let parts = checkout.split(separator: "/").map(String.init)
            guard parts.count >= 3 else { return last(checkout) }
            let holder = parts[parts.count - 2], above = parts[parts.count - 3]
            if holder == "worktrees" && above == ".claude", parts.count >= 4 { return parts[parts.count - 4] }
            if above == "worktrees", parts.count >= 4, parts[parts.count - 4] != ".claude" { return holder }
            if holder.hasSuffix("-worktrees") { return String(holder.dropLast("-worktrees".count)) }
            return last(checkout)
        }

        static func worktreeName(_ checkout: String) -> String? {
            projectName(checkout) == last(checkout) ? nil : shorten(last(checkout))
        }
    }

    /// `agent-a578b48dc68f31141` -> `agent-a578b4`: long hex ids are noise past a few characters.
    public static func shorten(_ name: String) -> String {
        let pieces = name.split(separator: "-", omittingEmptySubsequences: false)
        guard let tail = pieces.last, tail.count >= 12, tail.allSatisfy(\.isHexDigit) else { return name }
        return (pieces.dropLast() + [tail.prefix(6)]).joined(separator: "-")
    }

    static func cacheRootName(_ root: String, home: String) -> String {
        let names: [String: String] = [
            "Library/Caches": "App caches",
            "Library/Developer/Xcode/DerivedData": "Xcode build data",
            "Library/Developer/Xcode/iOS DeviceSupport": "Xcode iOS device support",
            "Library/Developer/Xcode/watchOS DeviceSupport": "Xcode watchOS device support",
            "Library/Developer/Xcode/tvOS DeviceSupport": "Xcode tvOS device support",
            "Library/Developer/CoreSimulator/Caches": "Simulator caches",
            "Library/pnpm/store": "pnpm store",
            ".gradle/caches": "Gradle caches",
            ".gradle/wrapper/dists": "Gradle downloads",
            ".gradle/daemon": "Gradle daemon logs",
            ".npm/_npx": "npx downloads",
            ".cache": "Tool caches (~/.cache)",
            ".pub-cache/hosted/pub.dev": "Dart packages",
            ".bun/install/cache": "Bun cache",
            ".yarn/berry/cache": "Yarn cache",
            ".android/cache": "Android cache",
        ]
        if root.hasPrefix(home + "/"), let name = names[String(root.dropFirst(home.count + 1))] { return name }
        return root.hasPrefix("/private/var/folders/") || root.hasPrefix("/var/folders/") ? "System temporary caches" : tilde(root, home: home)
    }

    /// Claude Code names a project folder after its path with `/` as `-`: `-Users-me-dev-app`.
    static func scratchpadProject(_ encoded: String, home: String) -> String {
        let homePrefix = home.replacingOccurrences(of: "/", with: "-") + "-"
        let rest = encoded.hasPrefix(homePrefix) ? String(encoded.dropFirst(homePrefix.count)) : encoded
        return rest.isEmpty ? "home folder" : rest
    }

    static func dockerLabel(_ target: String) -> ItemLabel {
        let parts = target.components(separatedBy: " (")
        let id = parts.count > 1 ? String(parts[1].dropLast()) : ""
        let tags = parts[0]
        guard tags != "<none>" else { return ItemLabel(title: "Untagged image", context: [id]) }
        let first = tags.components(separatedBy: ",").first ?? tags
        let name = first.components(separatedBy: "/").last ?? first
        let registry = first.contains("/") ? first.components(separatedBy: "/").dropLast().joined(separator: "/") : ""
        return ItemLabel(title: name, context: [registry, id].filter { !$0.isEmpty })
    }

    public static func tilde(_ path: String, home: String = Paths.home.path) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : last(path)
    }

    static func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    static func last(_ path: String) -> String { (path as NSString).lastPathComponent }
}
