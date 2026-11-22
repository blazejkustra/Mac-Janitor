import XCTest
@testable import JanitorCLI
@testable import JanitorCore

/// The agent commands: holders, JSON shapes, and `remove` refusing what a run would not remove.
/// Every run here records, purges and logs history inside a scratch tree.
final class AgentCommandsTests: XCTestCase {
    var root = ""
    let realPurgeDir = FS.purgeDir, realHistory = Janitor.historyURL, realLock = Janitor.lockPath
    let realRecordRun = Janitor.recordRun, realSpawnPurge = Janitor.spawnPurge
    let realConfigURL = AgentCLI.configURL, realInteractive = AgentCLI.isInteractive, realLog = AgentCLI.log

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-agent-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/Caches", withIntermediateDirectories: true)
        FS.purgeDir = root + "/purge"
        Janitor.lockPath = root + "/run.lock"
        Janitor.historyURL = URL(fileURLWithPath: root + "/history.jsonl")
        Janitor.recordRun = { _ in }
        Janitor.spawnPurge = {}
        AgentCLI.configURL = URL(fileURLWithPath: root + "/config.json")
        AgentCLI.isInteractive = { false }
        AgentCLI.log = { _ in }
    }

    override func tearDownWithError() throws {
        FS.purgeDir = realPurgeDir
        Janitor.lockPath = realLock
        Janitor.historyURL = realHistory
        Janitor.recordRun = realRecordRun
        Janitor.spawnPurge = realSpawnPurge
        AgentCLI.configURL = realConfigURL
        AgentCLI.isInteractive = realInteractive
        AgentCLI.log = realLog
        FS.deferRemoval = false
        try? FileManager.default.removeItem(atPath: root)
    }

    var cfg: Config {
        var cfg = Config()
        cfg.worktreeSearchRoot = root
        cfg.cacheRoots = [root + "/Caches"]
        cfg.scratchRoots = []
        cfg.scratchpadRoot = root + "/scratchpad"
        cfg.trashDir = root + "/Trash"
        cfg.avdHome = root + "/avd"
        cfg.androidSDK = root + "/sdk"
        cfg.salvageDir = root + "/salvage"
        cfg.disabled = [.simulator, .dockerImage]
        return cfg
    }

    func makeStaleCache(_ name: String) throws -> String {
        let entry = root + "/Caches/" + name
        try FileManager.default.createDirectory(atPath: entry, withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: URL(fileURLWithPath: entry + "/blob"))
        let t = time_t(Date().addingTimeInterval(-90 * 86400).timeIntervalSince1970)
        var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
        for path in [entry + "/blob", entry] { lutimes(path, &times) }
        return entry
    }

    func json(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.janitor.encode(value)) as? [String: Any])
    }

    func refusal(_ body: () throws -> Any) -> String? {
        do {
            _ = try body()
            return nil
        } catch {
            return "\(error)"
        }
    }

    // MARK: - Arguments

    func testArgumentsNeedAPathExactlyWhereOneIsTaken() {
        XCTAssertEqual(AgentCLI.Arguments.parse(["remove", "/x", "--yes", "--json"]),
                       AgentCLI.Arguments(command: "remove", path: "/x", json: true, yes: true))
        XCTAssertEqual(AgentCLI.Arguments.parse(["unknown", "--min-gb", "2.5"])?.minGB, 2.5)
        XCTAssertNil(AgentCLI.Arguments.parse(["remove"]))
        XCTAssertNil(AgentCLI.Arguments.parse(["skips", "/x"]))
        XCTAssertNil(AgentCLI.Arguments.parse(["inspect", "/x", "--yes"]))
        XCTAssertNil(AgentCLI.Arguments.parse(["unknown", "--min-gb", "lots"]))
    }

    func testAgentCommandsAreHeadless() {
        for command in ["plan", "skips", "unknown", "inspect", "remove", "pin", "unpin"] {
            XCTAssertTrue(CLI.handles([command]), command)
        }
    }

    // MARK: - Holders

    func testLsofHoldersCarryProcessPidAndKind() {
        let output = "p12\ncnode\nfcwd\nn/wt\nftxt\nn/wt/bin/node\nf5\nn/wt/log.txt\np40\ncvim\nf3\nn/other\n"
        let guards = Guards(openPaths: [], launchAgentStrings: [(plist: "x.plist", value: "/wt/run.sh")],
                            holders: Guards.parseLsof(output).holders)
        let held = guards.holders(in: "/wt")
        XCTAssertEqual(held.map(\.kind), [.cwd, .executable, .openFile, .launchAgent])
        XCTAssertEqual(held.first, Holder(path: "/wt", process: "node", pid: 12, kind: .cwd))
        XCTAssertEqual(held.last?.process, "x.plist")
        XCTAssertTrue(guards.holders(in: "/w").isEmpty)
    }

    // MARK: - JSON shapes

    func testSkipsListKeptAndHeldItemsWithTheirHolders() throws {
        let kept = try makeStaleCache("kept")
        let held = try makeStaleCache("held")
        let handle = try XCTUnwrap(FileHandle(forReadingAtPath: held + "/blob"))
        defer { handle.closeFile() }
        var cfg = self.cfg
        cfg.keep = [kept]

        let output = try json(AgentCLI.skipsOutput(cfg))

        let items = try XCTUnwrap(output["items"] as? [[String: Any]])
        XCTAssertNotNil(output["issues"] as? [Any])
        let keptItem = try XCTUnwrap(items.first { $0["path"] as? String == kept })
        XCTAssertEqual(keptItem["kept"] as? Bool, true)
        XCTAssertEqual(keptItem["category"] as? String, "cache")
        XCTAssertGreaterThan(keptItem["bytes"] as? Int ?? 0, 0)
        let heldItem = try XCTUnwrap(items.first { $0["path"] as? String == held })
        XCTAssertEqual(heldItem["kept"] as? Bool, false)
        XCTAssertTrue((heldItem["reason"] as? String ?? "").contains("in use"))
        let holders = try XCTUnwrap(heldItem["holders"] as? [[String: Any]])
        let me = try XCTUnwrap(holders.first { $0["pid"] as? Int == Int(getpid()) })
        XCTAssertEqual(me["kind"] as? String, "open-file")
        XCTAssertEqual(me["path"] as? String, held + "/blob")
        XCTAssertNotNil(me["process"] as? String)
    }

    func testInspectSaysWhatARunWouldDo() throws {
        let entry = try makeStaleCache("stale")

        let output = try json(AgentCLI.inspection(entry, cfg))

        XCTAssertEqual(output["path"] as? String, entry)
        XCTAssertEqual(output["exists"] as? Bool, true)
        XCTAssertEqual(output["pinnedBy"] as? [String], [])
        XCTAssertNil(output["protected"])
        XCTAssertNotNil(output["lastModified"] as? String)
        XCTAssertNotNil(output["holders"] as? [Any])
        let matches = try XCTUnwrap(output["matches"] as? [[String: Any]])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?["status"] as? String, "remove")
        XCTAssertEqual(matches.first?["category"] as? String, "cache")
        XCTAssertTrue((output["verdict"] as? String ?? "").hasPrefix("a run removes it (cache)"))

        let parent = try json(AgentCLI.inspection(root + "/Caches", cfg))
        XCTAssertEqual((parent["matches"] as? [Any])?.count, 0)
        XCTAssertEqual((parent["inside"] as? [[String: Any]])?.first?["path"] as? String, entry)
        XCTAssertTrue((parent["verdict"] as? String ?? "").hasPrefix("never removed: refusing to remove"))
    }

    // MARK: - Remove

    func testRemoveNeedsYesWhenNotAtATerminal() throws {
        let entry = try makeStaleCache("stale")
        XCTAssertEqual(refusal { try AgentCLI.removal(entry, self.cfg, yes: false) },
                       "remove needs --yes when not run at a terminal")
        XCTAssertTrue(FS.exists(entry))
    }

    func testRemoveAsksAtATerminal() throws {
        let entry = try makeStaleCache("stale")
        AgentCLI.isInteractive = { true }
        let realAnswer = AgentCLI.readAnswer
        defer { AgentCLI.readAnswer = realAnswer }
        AgentCLI.readAnswer = { "n" }
        XCTAssertEqual(refusal { try AgentCLI.removal(entry, self.cfg, yes: false) }, "not removed: not confirmed")
        XCTAssertTrue(FS.exists(entry))
    }

    func testRemoveRefusesAPathNoCategoryMatches() throws {
        let folder = root + "/projects/notes"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        XCTAssertEqual(refusal { try AgentCLI.removal(folder, self.cfg, yes: true) },
                       "not removed: no category would remove \(folder) now; see `janitor inspect`")
        XCTAssertTrue(FS.exists(folder))
    }

    func testRemoveRefusesWhatAGuardKeeps() throws {
        let held = try makeStaleCache("held")
        let handle = try XCTUnwrap(FileHandle(forReadingAtPath: held + "/blob"))
        defer { handle.closeFile() }
        let why = try XCTUnwrap(refusal { try AgentCLI.removal(held, self.cfg, yes: true) })
        XCTAssertTrue(why.hasPrefix("not removed: unused for"), why)
        XCTAssertTrue(why.contains("in use (open: \(held)/blob)"), why)
        XCTAssertTrue(FS.exists(held))
    }

    func testRemoveRefusesWhatIsPinned() throws {
        let kept = try makeStaleCache("kept")
        var cfg = self.cfg
        cfg.keep = [kept]
        XCTAssertEqual(refusal { try AgentCLI.removal(kept, cfg, yes: true) }, "not removed: kept")
        XCTAssertTrue(FS.exists(kept))
    }

    func testRemoveTakesOnlyThatItem() throws {
        let entry = try makeStaleCache("stale")
        let other = try makeStaleCache("other")

        let removed = try AgentCLI.removal(entry, cfg, yes: true)

        XCTAssertEqual(removed.status, .removed)
        XCTAssertEqual(removed.category, .cache)
        XCTAssertGreaterThan(removed.bytes, 0)
        XCTAssertFalse(FS.exists(entry))
        XCTAssertTrue(FS.exists(other))
    }

    // MARK: - Pin

    func testPinAndUnpinEditTheKeepList() throws {
        let entry = try makeStaleCache("stale")
        XCTAssertEqual(AgentCLI.main(["pin", entry, "--json"]), 0)
        XCTAssertEqual(try Config.load(from: AgentCLI.configURL).keep, [entry])
        XCTAssertEqual(AgentCLI.main(["pin", entry, "--json"]), 0)
        XCTAssertEqual(try Config.load(from: AgentCLI.configURL).keep, [entry])
        XCTAssertEqual(AgentCLI.main(["unpin", entry + "/blob", "--json"]), 0)
        XCTAssertEqual(try Config.load(from: AgentCLI.configURL).keep, [])
    }

    // MARK: - Unknown folders

    func testUnknownListsBigFoldersNoCategoryCovers() throws {
        let big = root + "/datasets/raw"
        try FileManager.default.createDirectory(atPath: big, withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: URL(fileURLWithPath: big + "/a.bin"))
        _ = try makeStaleCache("stale")
        let project = root + "/app"
        try FileManager.default.createDirectory(atPath: project + "/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: project + "/node_modules", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: project + "/package.json", contents: Data())
        try Data(count: 2_000_000).write(to: URL(fileURLWithPath: project + "/node_modules/b.bin"))
        var cfg = self.cfg
        cfg.largeFileMinGB = 1

        let found = UnknownFolders.find(cfg, minBytes: 1_000_000)

        XCTAssertEqual(found.map(\.path), [big])
        XCTAssertGreaterThanOrEqual(found.first?.bytes ?? 0, 2_000_000)
    }
}
