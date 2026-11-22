import XCTest
@testable import JanitorCore

final class WorkingDirectoryGuardTests: XCTestCase {
    func testLsofOutputSeparatesWorkingDirectoriesFromOpenFiles() {
        let output = "p1\nfcwd\nn/wt\nftxt\nn/bin/zsh\np2\nf3\nn/wt/log.txt\nfmem\nn/lib/x.dylib\n"
        let parsed = Guards.parseLsof(output)
        XCTAssertEqual(parsed.cwd, ["/wt"])
        XCTAssertEqual(parsed.open, ["/bin/zsh", "/wt/log.txt", "/lib/x.dylib"])
    }

    func testWorkingDirectoryVetoesUnlessAllowed() {
        let g = Guards(openPaths: [], cwdPaths: ["/wt/sub"], launchAgentStrings: [])
        XCTAssertEqual(g.veto("/wt"), "in use (working directory: /wt/sub)")
        XCTAssertNil(g.veto("/wt", allowingWorkingDirectories: true))
        XCTAssertEqual(g.workingDirectory(in: "/wt"), "/wt/sub")
    }

    func testOpenFilesAndLaunchAgentsStillVetoWhenWorkingDirectoriesAreAllowed() {
        let open = Guards(openPaths: ["/wt/server.log"], cwdPaths: ["/wt"], launchAgentStrings: [])
        XCTAssertEqual(open.veto("/wt", allowingWorkingDirectories: true), "in use (open: /wt/server.log)")
        let agent = Guards(openPaths: [], cwdPaths: ["/wt"], launchAgentStrings: [(plist: "x.plist", value: "/wt/run.sh")])
        XCTAssertEqual(agent.veto("/wt", allowingWorkingDirectories: true), "referenced by LaunchAgent x.plist")
    }

    func testLsofOutputSeparatesWatchmanFromOtherProcesses() {
        let output = "p1802\ncwatchman\nfcwd\nn/\nf5\nn/wt\np9\ncnode\nf7\nn/wt/metro.log\n"
        let parsed = Guards.parseLsof(output)
        XCTAssertEqual(parsed.watchman, ["/wt"])
        XCTAssertEqual(parsed.open, ["/wt/metro.log"])
        XCTAssertEqual(parsed.cwd, ["/"])
    }

    func testWatchmanVetoesUnlessAllowed() {
        let g = Guards(openPaths: [], watchmanPaths: ["/wt"], launchAgentStrings: [])
        XCTAssertEqual(g.veto("/wt", allowingWorkingDirectories: true), "in use (open: /wt)")
        XCTAssertNil(g.veto("/wt", allowingWatchman: true))
        XCTAssertEqual(g.idleHolders(in: "/wt"), "held only by watchman")
        let both = Guards(openPaths: [], cwdPaths: ["/wt"], watchmanPaths: ["/wt"], launchAgentStrings: [])
        XCTAssertEqual(both.idleHolders(in: "/wt"), "in use only as a shell's working directory and by watchman")
    }

    func testOpenFilesStillVetoWhenWatchmanIsAllowed() {
        let g = Guards(openPaths: ["/wt/metro.log"], watchmanPaths: ["/wt"], launchAgentStrings: [])
        XCTAssertEqual(g.veto("/wt", allowingWorkingDirectories: true, allowingWatchman: true), "in use (open: /wt/metro.log)")
    }

    func testOnlyMergedFullyPushedIdleWorktreesIgnoreWorkingDirectories() {
        let cfg = Config()
        var merged = WorktreeFacts(path: "/wt", isGit: true, idleDays: 6)
        merged.mergedPR = 455
        XCTAssertTrue(WorktreeRules.allowsIdleHolders(merged, cfg))

        var dirty = merged
        dirty.dirty = true
        var fresh = merged
        fresh.idleDays = 0.5
        var locked = merged
        locked.locked = true
        var abandoned = WorktreeFacts(path: "/wt", isGit: true, idleDays: 40)
        abandoned.headOnRemote = true
        for f in [dirty, fresh, locked, abandoned] { XCTAssertFalse(WorktreeRules.allowsIdleHolders(f, cfg)) }
    }
}

final class SimulatorJanitorTests: XCTestCase {
    var root = ""
    let none = Guards(openPaths: [], launchAgentStrings: [])
    let now = ISO8601DateFormatter().date(from: "2026-11-22T12:00:00Z")!

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-sims-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func device(_ udid: String, state: String, available: Bool = true, used: String?, key: String = "lastUsedAt") throws -> String {
        try FileManager.default.createDirectory(atPath: "\(root)/\(udid)/data", withIntermediateDirectories: true)
        let date = used.map { "\"\(key)\": \"\($0)\"," } ?? ""
        return """
        {"udid": "\(udid)", "name": "\(udid) phone", "state": "\(state)", "isAvailable": \(available), \(date)
         "dataPath": "\(root)/\(udid)/data", "deviceTypeIdentifier": "x"}
        """
    }

    func listing(_ devices: [String]) -> Data {
        Data("""
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [\(devices.joined(separator: ","))],
                     "com.apple.CoreSimulator.SimRuntime.iOS-18-0": []}}
        """.utf8)
    }

    func testOnlyShutDownDevicesUnusedPastTheThresholdOrWithoutARuntimeGo() throws {
        let json = listing([
            try device("A-BOOTED", state: "Booted", used: "2026-10-01T00:00:00Z"),
            try device("B-OLD", state: "Shutdown", used: "2026-11-10T00:00:00Z"),
            try device("C-RECENT", state: "Shutdown", used: "2026-11-20T00:00:00Z"),
            try device("D-UNAVAILABLE", state: "Shutdown", available: false, used: "2026-11-21T00:00:00Z"),
            try device("E-BOOTED-AT", state: "Shutdown", used: "2026-11-01T00:00:00Z", key: "lastBootedAt"),
            try device("F-BOOTING-UNAVAILABLE", state: "Booting", available: false, used: nil),
        ])
        let devices = try SimulatorJanitor.devices(fromJSON: json)
        XCTAssertEqual(devices.count, 6)
        var skips: [Skip] = []
        let plan = SimulatorJanitor.plan(devices, cfg: Config(), guards: none, now: now, skips: &skips)
        XCTAssertEqual(plan.map(\.target), ["\(root)/B-OLD", "\(root)/D-UNAVAILABLE", "\(root)/E-BOOTED-AT"])
        XCTAssertEqual(plan.map(\.reason), ["unused for 12.5 days", "its runtime is no longer installed", "unused for 21.5 days"])
        XCTAssertEqual(plan.map(\.category), [.simulator, .simulator, .simulator])
    }

    func testWithoutADateTheDataFolderTimeCounts() throws {
        let json = listing([try device("G-NODATE", state: "Shutdown", used: nil)])
        let devices = try SimulatorJanitor.devices(fromJSON: json)
        var skips: [Skip] = []
        XCTAssertEqual(SimulatorJanitor.plan(devices, cfg: Config(), guards: none, now: Date(), skips: &skips).map(\.target), [])
        let old = time_t(Date().addingTimeInterval(-10 * 86400).timeIntervalSince1970)
        var times = [timeval(tv_sec: old, tv_usec: 0), timeval(tv_sec: old, tv_usec: 0)]
        lutimes("\(root)/G-NODATE/data", &times)
        XCTAssertEqual(SimulatorJanitor.plan(devices, cfg: Config(), guards: none, now: Date(), skips: &skips).map(\.target),
                       ["\(root)/G-NODATE"])
    }

    func testKeptAndInUseDevicesAreSkipped() throws {
        let json = listing([
            try device("H-KEPT", state: "Shutdown", used: "2026-11-01T00:00:00Z"),
            try device("I-OPEN", state: "Shutdown", used: "2026-11-01T00:00:00Z"),
        ])
        var cfg = Config()
        cfg.keep = ["\(root)/H-KEPT"]
        let guards = Guards(openPaths: ["\(root)/I-OPEN/data/log"], launchAgentStrings: [])
        var skips: [Skip] = []
        let plan = SimulatorJanitor.plan(try SimulatorJanitor.devices(fromJSON: json), cfg: cfg, guards: guards, now: now, skips: &skips)
        XCTAssertEqual(plan.map(\.target), [])
        XCTAssertEqual(skips.map(\.target), ["\(root)/H-KEPT", "\(root)/I-OPEN"])
        XCTAssertEqual(skips.map(\.kept), [true, false])
    }

    func testLabelNamesTheDeviceAndRuntime() throws {
        let dir = root + "/J"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["name": "iPhone 17 Pro", "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: URL(fileURLWithPath: dir + "/device.plist"))
        XCTAssertEqual(ItemLabel.describe(dir, .simulator), ItemLabel(title: "iPhone 17 Pro", context: ["iOS 27.0 simulator"]))
    }
}

final class ScratchRootsTests: XCTestCase {
    var root = ""
    let none = Guards(openPaths: [], launchAgentStrings: [])

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-scratch-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        Safety.protectedPaths = []
        try? FileManager.default.removeItem(atPath: root)
    }

    func folder(_ path: String, days: Double) throws -> String {
        let dir = root + "/" + path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/notes.md", atomically: false, encoding: .utf8)
        let t = time_t(Date().addingTimeInterval(-days * 86400).timeIntervalSince1970)
        var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
        for p in [dir + "/notes.md", dir] { lutimes(p, &times) }
        return dir
    }

    func testThreadFoldersInEveryScratchRootGoOnceIdle() throws {
        var cfg = Config()
        cfg.scratchpadRoot = root + "/claude"
        cfg.scratchRoots = [root + "/t3", root + "/other"]
        let session = try folder("claude/-Users-me-app/0c1d2e3f", days: 5)
        let thread = try folder("t3/2026-11-11-check-it-52fc5e47", days: 5)
        _ = try folder("other/2026-11-21-fresh-1a2b3c4d", days: 1)
        let busy = try folder("other/busy", days: 5)
        let guards = Guards(openPaths: [], cwdPaths: [busy], launchAgentStrings: [])
        var skips: [Skip] = []
        let plan = ScratchpadJanitor.plan(cfg, guards: guards, now: Date(), skips: &skips)
        XCTAssertEqual(plan.map(\.target), [session, thread])
        XCTAssertEqual(skips.map(\.target), [busy])

        Safety.protectedPaths = cfg.scratchRoots + [cfg.scratchpadRoot]
        XCTAssertEqual(plan.map { ScratchpadJanitor.execute($0, cfg).status }, [.removed, .removed])
        XCTAssertFalse(FS.exists(root + "/claude/-Users-me-app"))
        XCTAssertTrue(FS.exists(root + "/t3"))
    }

    func testThreadFolderLabelIsItsName() {
        XCTAssertEqual(ItemLabel.describe("/Users/me/.t3/scratch/2026-11-11-check-it-52fc5e47", .scratchpad, home: "/Users/me"),
                       ItemLabel(title: "2026-11-11-check-it-52fc5e47", context: ["~/.t3/scratch"]))
    }
}
