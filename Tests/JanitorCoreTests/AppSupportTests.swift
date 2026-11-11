import XCTest
@testable import JanitorCLI
@testable import JanitorCore

final class ItemLabelTests: XCTestCase {
    let home = "/Users/me"
    func label(_ target: String, _ c: JanitorCore.Category, checkouts: Set<String> = []) -> ItemLabel {
        ItemLabel.describe(target, c, home: home, isCheckout: { checkouts.contains($0) })
    }

    func testClaudeWorktreeNodeModulesNameTheRepoAndWorktree() {
        let l = label("/Users/me/Developer/uncut/.claude/worktrees/agent-a578b48dc68f31141/node_modules", .nodeModules)
        XCTAssertEqual(l, ItemLabel(title: "uncut · agent-a578b4"))
    }

    func testSameFolderNameInTwoWorktreesStaysDistinct() {
        let a = label("/Users/me/Developer/argent/.claude/worktrees/agent-a7b1251c0208dde89/packages/tool-server/node_modules", .nodeModules)
        let b = label("/Users/me/.t3/worktrees/argent/t3-a6c8cef2/packages/tool-server/node_modules", .nodeModules)
        XCTAssertEqual(a, ItemLabel(title: "argent · agent-a7b125", context: ["packages/tool-server"]))
        XCTAssertEqual(b, ItemLabel(title: "argent · t3-a6c8cef2", context: ["packages/tool-server"]))
        XCTAssertNotEqual(a.title, b.title)
    }

    func testSiblingWorktreesFolder() {
        let l = label("/Users/me/dev/app-worktrees/fix-login", .worktree)
        XCTAssertEqual(l, ItemLabel(title: "app · fix-login", context: ["worktree"]))
    }

    func testPlainCheckoutFoundByGit() {
        let l = label("/Users/me/Developer/site/apps/web/.next", .build, checkouts: ["/Users/me/Developer/site"])
        XCTAssertEqual(l, ItemLabel(title: "site", context: ["apps/web/.next"]))
    }

    func testCachesAndFiles() {
        XCTAssertEqual(label("/Users/me/Library/Caches/com.spotify.client", .cache),
                       ItemLabel(title: "com.spotify.client", context: ["App caches"]))
        XCTAssertEqual(label("/Users/me/Movies/old.mov", .largeFile), ItemLabel(title: "old.mov", context: ["~/Movies"]))
        XCTAssertEqual(label("Pixel_6_API_34", .avd), ItemLabel(title: "Pixel 6 API 34", context: ["emulator"]))
        XCTAssertEqual(label("/private/tmp/claude-501/-Users-me-dev-app/0c1d2e3f4a", .scratchpad),
                       ItemLabel(title: "Session 0c1d2e3f", context: ["dev-app"]))
        XCTAssertEqual(label("ghcr.io/acme/api:1.2 (24eda6a4098f)", .dockerImage),
                       ItemLabel(title: "api:1.2", context: ["ghcr.io/acme", "24eda6a4098f"]))
    }

    func testShortenOnlyTrimsLongHexIds() {
        XCTAssertEqual(ItemLabel.shorten("agent-a578b48dc68f31141"), "agent-a578b4")
        XCTAssertEqual(ItemLabel.shorten("factory-gates"), "factory-gates")
        XCTAssertEqual(ItemLabel.shorten("t3-a6c8cef2"), "t3-a6c8cef2")
    }
}

final class ScanEventTests: XCTestCase {
    func testLinesRoundTrip() {
        let action = Action(category: .cache, target: "/x/y", reason: "unused", bytes: 42, status: .planned)
        let events: [ScanEvent] = [.step("Checking"), .folder("/a b/c"), .found(.cache, actions: [action], skips: [])]
        for event in events {
            let parsed = ScanEvent.parse(Substring(event.line))
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed?.line, event.line)
        }
        XCTAssertNil(ScanEvent.parse("janitor: another janitor run is in progress"))
    }

    func testRunReportsEveryEnabledCategory() throws {
        var cfg = Config()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("scan-events-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        cfg.worktreeSearchRoot = tmp
        cfg.scratchpadRoot = tmp + "/scratch"
        cfg.avdHome = tmp + "/avd"
        cfg.androidSDK = tmp + "/sdk"
        cfg.trashDir = tmp + "/trash"
        cfg.cacheRoots = []
        cfg.disabled = [.dockerImage]
        var found: [JanitorCore.Category] = []
        var steps = 0
        ScanProgress.sink = { event in
            switch event {
            case .found(let c, _, _): found.append(c)
            case .step: steps += 1
            case .folder: break
            }
        }
        defer { ScanProgress.sink = nil }
        _ = try Janitor.run(cfg, dryRun: true)
        XCTAssertEqual(Set(found), Set(JanitorCore.Category.allCases))
        XCTAssertGreaterThan(steps, 3)
    }
}

final class CLIOptionsTests: XCTestCase {
    func testParsesFlagsAndOnly() {
        XCTAssertEqual(CLI.Options.parse(["run", "--dry-run", "--progress", "--only", "/tmp/ids"]),
                       CLI.Options(dryRun: true, progress: true, onlyFile: "/tmp/ids"))
        XCTAssertEqual(CLI.Options.parse(["run", "--scheduled"]), CLI.Options(scheduled: true))
    }

    func testRejectsUnknownInput() {
        XCTAssertNil(CLI.Options.parse(["run", "--force"]))
        XCTAssertNil(CLI.Options.parse(["clean"]))
        XCTAssertNil(CLI.Options.parse(["run", "--only"]))
        XCTAssertFalse(CLI.isRun(["--snapshot", "/tmp"]))
        XCTAssertTrue(CLI.isRun(["run", "--scheduled"]))
    }
}
