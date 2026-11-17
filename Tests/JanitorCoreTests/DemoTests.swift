#if DEMO
import XCTest
@testable import JanitorCore

/// Only in demo builds: `swift test -Xswiftc -DDEMO --filter DemoTests`.
final class DemoTests: XCTestCase {
    var root = ""
    var recorded: Report?
    var spawnedPurges = 0
    let realPurgeDir = FS.purgeDir, realLock = Janitor.lockPath
    let realRecordRun = Janitor.recordRun, realSpawnPurge = Janitor.spawnPurge

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-demo-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        FS.purgeDir = root + "/purge"
        Janitor.lockPath = root + "/run.lock"
        Janitor.recordRun = { [unowned self] in recorded = $0 }
        Janitor.spawnPurge = { [unowned self] in spawnedPurges += 1 }
    }

    override func tearDownWithError() throws {
        FS.purgeDir = realPurgeDir
        Janitor.lockPath = realLock
        Janitor.recordRun = realRecordRun
        Janitor.spawnPurge = realSpawnPurge
        FS.deferRemoval = false
        try? FileManager.default.removeItem(atPath: root)
    }

    func makeStale(_ path: String, bytes: Int = 300_000) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(count: bytes).write(to: URL(fileURLWithPath: path))
    }

    func ageEverything() {
        let t = time_t(Date().addingTimeInterval(-90 * 86400).timeIntervalSince1970)
        var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
        FS.walk(root) { path, _, _, _ in
            lutimes(path, &times)
            return true
        }
    }

    func fixtureFiles() throws -> [String] {
        try ["/home", "/Caches"].flatMap { try FileManager.default.subpathsOfDirectory(atPath: root + $0).sorted() }
    }

    func testCleanReportsRealSizesAndRemovesNothing() throws {
        try makeStale(root + "/Caches/com.example.stale/blob")
        try makeStale(root + "/home/app/package.json", bytes: 10)
        try makeStale(root + "/home/app/node_modules/left-pad/index.js")
        try FileManager.default.createDirectory(atPath: root + "/home/app/.git", withIntermediateDirectories: true)
        try makeStale(root + "/home/videos/old.mov", bytes: 2_000_000)
        ageEverything()
        var cfg = Config()
        cfg.worktreeSearchRoot = root + "/home"
        cfg.cacheRoots = [root + "/Caches"]
        cfg.salvageDir = root + "/salvage"
        cfg.largeFileMinGB = 0.001

        let preview = try Janitor.run(cfg, dryRun: true)
        let planned = preview.actions
        XCTAssertGreaterThanOrEqual(planned.count, 3, "\(planned.map(\.id))")
        let before = try fixtureFiles()

        let report = try Janitor.run(cfg, dryRun: false, only: Set(planned.map(\.id)),
                                     sizes: Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0.bytes) }))

        XCTAssertEqual(Set(report.actions.map(\.id)), Set(planned.map(\.id)))
        XCTAssertTrue(report.actions.allSatisfy { $0.status == .removed })
        XCTAssertEqual(report.freedBytes, planned.reduce(0) { $0 + $1.bytes })
        XCTAssertGreaterThan(report.freedBytes, 2_000_000)
        XCTAssertFalse(report.dryRun)
        XCTAssertNotNil(recorded)
        XCTAssertEqual(try fixtureFiles(), before)
        for a in planned { XCTAssertTrue(FS.exists(a.target), a.target) }
        XCTAssertEqual(spawnedPurges, 0)
    }

    func testRemovalAndPurgeRefuse() throws {
        let file = root + "/keep/me"
        try makeStale(file)
        XCTAssertThrowsError(try FS.remove(file))
        try makeStale(FS.purgeDir + "/parked/blob")

        let result = Janitor.purgeLeftovers(log: { _ in })

        XCTAssertEqual(result.removed, 0)
        XCTAssertTrue(FS.exists(file))
        XCTAssertTrue(FS.exists(FS.purgeDir + "/parked/blob"))
    }

    func testStateLivesInItsOwnFolder() {
        XCTAssertTrue(Paths.support.path.hasSuffix("/Application Support/MacJanitor Demo"))
        XCTAssertTrue(Paths.log.path.hasPrefix(Paths.support.path + "/"))
        XCTAssertNil(LegacyAgent.remove())
    }
}
#endif
