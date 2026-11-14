import XCTest
@testable import JanitorCLI
@testable import JanitorCore

/// What a clean records, purging, the saved preview, tile states and the legacy agent.
/// Every run here records, purges and logs history inside a scratch tree.
final class CleanReportingTests: XCTestCase {
    var root = ""
    var recorded: Report?
    var spawnedPurges = 0
    let realPurgeDir = FS.purgeDir, realHistory = Janitor.historyURL, realLock = Janitor.lockPath
    let realRecordRun = Janitor.recordRun, realSpawnPurge = Janitor.spawnPurge

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-reporting-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        FS.purgeDir = root + "/purge"
        Janitor.lockPath = root + "/run.lock"
        Janitor.historyURL = URL(fileURLWithPath: root + "/history.jsonl")
        Janitor.recordRun = { [unowned self] in recorded = $0 }
        Janitor.spawnPurge = { [unowned self] in spawnedPurges += 1 }
    }

    override func tearDownWithError() throws {
        FS.purgeDir = realPurgeDir
        Janitor.lockPath = realLock
        Janitor.historyURL = realHistory
        Janitor.recordRun = realRecordRun
        Janitor.spawnPurge = realSpawnPurge
        FS.deferRemoval = false
        try? FileManager.default.removeItem(atPath: root)
    }

    var history: [[String: Any]] {
        let text = (try? String(contentsOf: Janitor.historyURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
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

    var cacheConfig: Config {
        var cfg = Config()
        cfg.worktreeSearchRoot = root
        cfg.cacheRoots = [root + "/Caches"]
        cfg.salvageDir = root + "/salvage"
        return cfg
    }

    // MARK: - Freed space

    func testCleanFromTheAppRecordsThePreviewSizes() throws {
        let entry = try makeStaleCache("com.example.stale")
        let cfg = cacheConfig
        let preview = try Janitor.run(cfg, dryRun: true)
        let planned = try XCTUnwrap(preview.actions.first { $0.target == entry })
        XCTAssertGreaterThan(planned.bytes, 0)

        let report = try Janitor.run(cfg, dryRun: false, only: [planned.id], sizes: [planned.id: planned.bytes])

        XCTAssertFalse(FS.exists(entry))
        let removed = try XCTUnwrap(report.actions.first { $0.id == planned.id })
        XCTAssertEqual(removed.status, .removed)
        XCTAssertEqual(removed.bytes, planned.bytes)
        XCTAssertEqual(report.removalDeferred, true)
        XCTAssertEqual(report.removedBytes, planned.bytes)
        XCTAssertEqual(report.freedBytes, planned.bytes)
        XCTAssertEqual(recorded?.freedBytes, planned.bytes)
        XCTAssertEqual(FS.purgeEntries.count, 1)
        XCTAssertEqual(spawnedPurges, 1)
    }

    // MARK: - Purge

    func makeReadOnlyTree(_ name: String) throws -> String {
        let entry = FS.purgeDir + "/" + name
        try FileManager.default.createDirectory(atPath: entry + "/pkg/mod", withIntermediateDirectories: true)
        try Data(count: 200_000).write(to: URL(fileURLWithPath: entry + "/pkg/mod/a.go"))
        try Data(count: 1000).write(to: URL(fileURLWithPath: entry + "/locked"))
        XCTAssertEqual(chflags(entry + "/locked", UInt32(UF_IMMUTABLE)), 0)
        for dir in [entry + "/pkg/mod", entry + "/pkg"] { chmod(dir, 0o555) }
        return entry
    }

    func testPurgeRemovesReadOnlyAndLockedTreesThatRmCannot() throws {
        let entry = try makeReadOnlyTree("readonly")
        XCTAssertFalse(Shell.run(["/bin/rm", "-rf", "--", entry]).ok)
        XCTAssertTrue(FS.exists(entry))
        XCTAssertGreaterThan(FS.purgeBacklogBytes, 0)

        let result = Janitor.purgeLeftovers(log: { _ in })

        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.failures, [])
        XCTAssertGreaterThan(result.bytes, 200_000)
        XCTAssertFalse(FS.exists(entry))
        XCTAssertEqual(FS.purgeBacklogBytes, 0)
    }

    func testPurgeLogsAndRecordsWhatItFreed() throws {
        _ = try makeReadOnlyTree("one")
        try FileManager.default.createDirectory(atPath: FS.purgeDir + "/two", withIntermediateDirectories: true)
        var lines: [String] = []
        let result = Janitor.purgeLeftovers { lines.append($0) }
        XCTAssertEqual(result.removed, 2)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("purged 2 items"))
        let line = try XCTUnwrap(history.last)
        XCTAssertEqual(line["purged"] as? Int, 2)
        XCTAssertEqual((line["purgedBytes"] as? NSNumber)?.int64Value, result.bytes)
    }

    func testEmptyPurgeRecordsNothing() {
        XCTAssertEqual(Janitor.purgeLeftovers(log: { _ in }).removed, 0)
        XCTAssertTrue(history.isEmpty)
    }

    func testRealRunsPurgeLeftoversFirst() throws {
        try FileManager.default.createDirectory(atPath: FS.purgeDir + "/leftover", withIntermediateDirectories: true)
        _ = try Janitor.run(cacheConfig, dryRun: true)
        XCTAssertEqual(spawnedPurges, 0)
        _ = try Janitor.run(cacheConfig, dryRun: false, only: ["cache:/nowhere/at/all"])
        XCTAssertEqual(spawnedPurges, 2)
        XCTAssertNotNil(recorded)
    }

    func testScheduledRunPurgesBeforeMeasuring() throws {
        try FileManager.default.createDirectory(atPath: FS.purgeDir + "/leftover", withIntermediateDirectories: true)
        var cfg = cacheConfig
        cfg.disabled = JanitorCore.Category.allCases.filter { $0 != .cache }
        _ = try Janitor.run(cfg, dryRun: false)
        XCTAssertTrue(FS.purgeEntries.isEmpty)
        XCTAssertEqual(history.last?["purged"] as? Int, 1)
    }

    func testPurgeIsAHeadlessCommand() {
        XCTAssertTrue(CLI.handles(["purge"]))
    }

    func testFreedBytesIsTheFreeSpaceChangeWhenRemovalWasNotDeferred() {
        let removed = Action(category: .cache, target: "/a/b/c", reason: "", bytes: 900, status: .removed)
        var report = Report(startedAt: Date(), finishedAt: Date(), dryRun: false, freeBytesBefore: 1000,
                            freeBytesAfter: 1600, actions: [removed], skips: [], issues: [])
        XCTAssertEqual(report.freedBytes, 600)
        report.removalDeferred = true
        XCTAssertEqual(report.freedBytes, 900)
    }

    func testOnlyFileCarriesOptionalSizes() {
        let parsed = CLI.parseOnly("cache:/a/b\t1234\ntrash:/x/y z\nbuild:/p/q\tnot-a-size\n")
        XCTAssertEqual(parsed.ids, ["cache:/a/b", "trash:/x/y z", "build:/p/q\tnot-a-size"])
        XCTAssertEqual(parsed.sizes, ["cache:/a/b": 1234])
    }

    // MARK: - Saved preview

    var previewURL: URL { URL(fileURLWithPath: root + "/support/preview.json") }

    func savedPreview(_ cfg: Config, at date: Date = Date()) throws {
        let action = Action(category: .cache, target: "/a/b/c", reason: "unused", bytes: 52_000_000_000, status: .planned)
        let report = Report(startedAt: date, finishedAt: date, dryRun: true, freeBytesBefore: 0, freeBytesAfter: 0,
                            actions: [action], skips: [], issues: [Issue(.dockerImage, "Docker is not running")])
        try SavedPreview(report: report, config: cfg, savedAt: date).save(to: previewURL)
    }

    func testSavedPreviewRoundTrips() throws {
        let cfg = Config()
        try savedPreview(cfg)
        let loaded = try XCTUnwrap(SavedPreview.load(from: previewURL, config: cfg))
        XCTAssertEqual(loaded.schema, SavedPreview.currentSchema)
        XCTAssertEqual(loaded.config, cfg)
        XCTAssertEqual(loaded.report.actions.map(\.bytes), [52_000_000_000])
        XCTAssertEqual(loaded.report.issues, [Issue(.dockerImage, "Docker is not running")])
    }

    func testSavedPreviewExpiresAfterADay() throws {
        try savedPreview(Config(), at: Date().addingTimeInterval(-SavedPreview.maxAge - 60))
        XCTAssertNil(SavedPreview.load(from: previewURL, config: Config()))
        XCTAssertFalse(FS.exists(previewURL.path))
    }

    func testSavedPreviewGoesWhenSettingsChangeWhatItPlans() throws {
        var then = Config()
        then.disabled = [.dockerImage]
        var reenabled = then
        reenabled.disabled = []
        try savedPreview(then)
        XCTAssertNil(SavedPreview.load(from: previewURL, config: reenabled))
        XCTAssertFalse(FS.exists(previewURL.path))

        var longer = Config()
        longer.cacheIdleDays = 60
        try savedPreview(Config())
        XCTAssertNil(SavedPreview.load(from: previewURL, config: longer))
    }

    func testSavedPreviewSurvivesSettingsThatOnlyHideItems() throws {
        var now = Config()
        now.disabled = [.trash]
        now.keep = ["/a/b/c"]
        now.paused = true
        try savedPreview(Config())
        XCTAssertNotNil(SavedPreview.load(from: previewURL, config: now))
    }

    func testSavedPreviewFromAnotherSchemaIsDropped() throws {
        try savedPreview(Config())
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: previewURL)) as! [String: Any]
        json["schema"] = SavedPreview.currentSchema + 1
        try JSONSerialization.data(withJSONObject: json).write(to: previewURL)
        XCTAssertNil(SavedPreview.load(from: previewURL, config: Config()))
    }

    func testDiscardSaysWhetherThereWasOne() throws {
        try savedPreview(Config())
        XCTAssertTrue(SavedPreview.discard(at: previewURL))
        XCTAssertFalse(SavedPreview.discard(at: previewURL))
        XCTAssertNil(SavedPreview.load(from: previewURL, config: Config()))
    }

    func testResetCacheIsAHeadlessCommand() {
        XCTAssertTrue(CLI.handles(["reset-cache"]))
    }

    // MARK: - Tiles

    func testTileWithAnIssueAndNothingFoundCouldNotCheck() {
        XCTAssertEqual(TileState(covered: true, bytes: 0, hasIssue: true), .unchecked)
        XCTAssertEqual(TileState(covered: true, bytes: 0, hasIssue: false), .nothing)
        XCTAssertEqual(TileState(covered: true, bytes: 5, hasIssue: true), .found(5))
        XCTAssertEqual(TileState(covered: false, bytes: 0, hasIssue: true), .checking)
    }

    // MARK: - Legacy agent

    let fakeLabel = "com.example.janitor-test-\(UUID().uuidString)"

    func installFakeAgent() throws -> URL {
        let plist = URL(fileURLWithPath: root + "/LaunchAgents/\(fakeLabel).plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: plist)
        return plist
    }

    func testLegacyAgentIsUnloadedAndItsPlistDeleted() throws {
        let plist = try installFakeAgent()
        var booted: [String] = []
        let done = LegacyAgent.remove(label: fakeLabel, in: plist.deletingLastPathComponent()) { booted.append($0); return 0 }
        XCTAssertEqual(booted, ["gui/\(getuid())/\(fakeLabel)"])
        XCTAssertFalse(FS.exists(plist.path))
        XCTAssertEqual(done, "legacy LaunchAgent: unloaded gui/\(getuid())/\(fakeLabel); deleted \(plist.path)")
    }

    func testLegacyAgentPlistGoesEvenWhenBootoutFails() throws {
        let plist = try installFakeAgent()
        let notLoaded = LegacyAgent.remove(label: fakeLabel, in: plist.deletingLastPathComponent()) { _ in 113 }
        XCTAssertFalse(FS.exists(plist.path))
        XCTAssertTrue(notLoaded?.contains("was not loaded") ?? false)

        _ = try installFakeAgent()
        let failed = LegacyAgent.remove(label: fakeLabel, in: plist.deletingLastPathComponent()) { _ in 5 }
        XCTAssertFalse(FS.exists(plist.path))
        XCTAssertTrue(failed?.contains("failed with status 5") ?? false)
    }

    func testMissingLegacyAgentIsLeftQuietly() {
        var called = false
        let done = LegacyAgent.remove(label: fakeLabel, in: URL(fileURLWithPath: root + "/LaunchAgents")) { _ in
            called = true
            return 0
        }
        XCTAssertNil(done)
        XCTAssertFalse(called)
    }
}
