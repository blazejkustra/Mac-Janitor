import XCTest
@testable import JanitorCore

final class RefreshPolicyTests: XCTestCase {
    let hour: TimeInterval = 3600
    let plugged = RefreshPolicy.Power(onBattery: false, lowPowerMode: false)
    let battery = RefreshPolicy.Power(onBattery: true, lowPowerMode: false)
    let lowPower = RefreshPolicy.Power(onBattery: false, lowPowerMode: true)

    func decide(_ trigger: RefreshPolicy.Trigger, age: TimeInterval?, outdated: Bool = false,
                power: RefreshPolicy.Power? = nil) -> RefreshPolicy.Decision {
        RefreshPolicy.decide(trigger, resultAge: age, interval: hour, outdated: outdated, power: power ?? plugged)
    }

    func testOpeningThePanelWithinTheIntervalDoesNotRescan() {
        XCTAssertEqual(decide(.panelOpened, age: 5 * 60), .none)
        XCTAssertEqual(decide(.panelOpened, age: 59 * 60), .none)
        XCTAssertEqual(decide(.timer, age: 59 * 60), .none)
    }

    func testAStaleResultRefreshesQuietly() {
        XCTAssertEqual(decide(.panelOpened, age: 2 * hour), .quiet)
        XCTAssertEqual(decide(.timer, age: hour), .quiet)
        XCTAssertEqual(decide(.panelOpened, age: 60, outdated: true), .quiet)
    }

    func testForcedAlwaysRescansVisibly() {
        XCTAssertEqual(decide(.forced, age: 60), .visible)
        XCTAssertEqual(decide(.forced, age: nil, power: battery), .visible)
    }

    func testChangesTheAppMadeRefreshAtOnce() {
        XCTAssertEqual(decide(.changed, age: 10, power: battery), .quiet)
        XCTAssertEqual(decide(.changed, age: nil), .visible)
    }

    func testWithoutAResultTheScanShowsProgress() {
        XCTAssertEqual(decide(.panelOpened, age: nil), .visible)
        XCTAssertEqual(decide(.timer, age: nil), .visible)
    }

    func testTheTimerWaitsOnBatteryAndLowPower() {
        XCTAssertEqual(decide(.timer, age: 3 * hour, power: battery), .none)
        XCTAssertEqual(decide(.timer, age: 3 * hour, power: lowPower), .none)
        XCTAssertEqual(decide(.timer, age: nil, power: battery), .none)
        XCTAssertEqual(decide(.panelOpened, age: 3 * hour, power: battery), .quiet)
    }

    func testTheIntervalIsNotAPlanInput() {
        var changed = Config()
        changed.refreshMinutes = 15
        XCTAssertFalse(changed.invalidates(previewPlannedWith: Config()))
    }
}

final class RevalidationTests: XCTestCase {
    var root = ""

    override func setUpWithError() throws {
        root = FS.canonical(FileManager.default.temporaryDirectory.path) + "/janitor-revalidate-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func make(_ path: String, bytes: Int = 1) throws -> String {
        let full = root + "/" + path
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(count: bytes).write(to: URL(fileURLWithPath: full))
        return full
    }

    func planned(_ c: JanitorCore.Category, _ target: String, bytes: Int64 = 1) -> Action {
        Action(category: c, target: target, reason: "untouched for 30 days", bytes: bytes, status: .planned)
    }

    func testKeepsFreeItemsAndMeasuresThemAgain() throws {
        let cache = try make("Caches/app/blob", bytes: 2_000_000)
        let checked = Revalidation.check([planned(.cache, cache)], cfg: Config(), guards: Guards(openPaths: [], launchAgentStrings: []))
        XCTAssertEqual(checked.actions.map(\.target), [cache])
        XCTAssertGreaterThanOrEqual(checked.actions[0].bytes, 2_000_000)
        XCTAssertTrue(checked.skips.isEmpty)
    }

    func testDropsItemsNowOpenPinnedOrGone() throws {
        let open = try make("Caches/open/data")
        try make("Caches/pinned/data")
        let gone = root + "/Caches/gone"
        var cfg = Config()
        cfg.keep = [root + "/Caches/pinned"]
        let guards = Guards(openPaths: [open], launchAgentStrings: [])
        let checked = Revalidation.check([planned(.cache, open), planned(.cache, root + "/Caches/pinned"), planned(.cache, gone)],
                                         cfg: cfg, guards: guards)
        XCTAssertTrue(checked.actions.isEmpty)
        let reasons = Dictionary(uniqueKeysWithValues: checked.skips.map { ($0.target, $0) })
        XCTAssertTrue(reasons[open]?.reason.contains("in use") == true)
        XCTAssertEqual(reasons[open]?.kept, false)
        XCTAssertEqual(reasons[root + "/Caches/pinned"]?.kept, true)
        XCTAssertNil(reasons[gone])
    }

    func testDropsPackagesOfAWorktreeSomethingIsOpenIn() throws {
        try make("wt/.git")
        try make("wt/packages/docs/node_modules/x/index.js")
        let source = try make("wt/src/main.ts")
        let packages = root + "/wt/packages/docs/node_modules"
        let checked = Revalidation.check([planned(.nodeModules, packages)], cfg: Config(),
                                         guards: Guards(openPaths: [source], launchAgentStrings: []))
        XCTAssertTrue(checked.actions.isEmpty)
        XCTAssertEqual(checked.skips.map(\.target), [packages])
    }

    func testDropsItemsALaunchAgentNames() throws {
        let tool = try make("tools/bin/agent")
        let guards = Guards(openPaths: [], launchAgentStrings: [(plist: "com.example.plist", value: tool)])
        let checked = Revalidation.check([planned(.largeFile, tool)], cfg: Config(), guards: guards)
        XCTAssertTrue(checked.actions.isEmpty)
        XCTAssertTrue(checked.skips[0].reason.contains("LaunchAgent"))
    }
}
