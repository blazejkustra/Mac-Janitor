import AppKit
import Foundation
import JanitorCore
import ServiceManagement

/// What a preview in progress has found so far.
struct ScanState {
    var step = "Starting"
    var folder: String?
    var done: Set<JanitorCore.Category> = []
    var actions: [Action] = []
    var skips: [Skip] = []

    mutating func apply(_ event: ScanEvent) {
        switch event {
        case .step(let text):
            step = text
            folder = nil
        case .folder(let path):
            folder = path
        case .found(let category, let found, let kept):
            done.insert(category)
            actions.removeAll { $0.category == category }
            skips.removeAll { $0.category == category }
            actions += found
            skips += kept
        }
    }

    var report: Report {
        Report(startedAt: Date(), finishedAt: Date(), dryRun: true, freeBytesBefore: 0, freeBytesAfter: 0,
               actions: actions, skips: skips, issues: [])
    }
}

/// One line in a category's list.
struct Item: Identifiable {
    enum Kind {
        case planned, failed, kept, guarded
        /// Unpinned since the preview; whether it is planned is known after the next one.
        case pending
    }

    var id: String
    var target: String
    var name: String
    var bytes: Int64
    var kind: Kind
    var detail: String
    var label: ItemLabel
}

@MainActor
final class Store: ObservableObject {
    enum Busy { case previewing, cleaning, scheduled }

    @Published private(set) var config: Config
    @Published private(set) var freeBytes: Int64
    @Published private(set) var totalBytes: Int64
    /// The last real run, as the CLI recorded it in `Paths.lastRun`.
    @Published private(set) var lastRun: Report?
    /// What a clean would remove: a dry run, or after a clean the items that failed.
    @Published private(set) var preview: Report?
    /// `preview` is the one saved by an earlier launch, shown until a fresh one replaces it.
    @Published private(set) var restored: Bool
    @Published private(set) var busy: Busy?
    @Published var problem: String?
    private var configProblem: String?
    @Published private(set) var loginStatus: SMAppService.Status
    @Published private(set) var agentStatus: SMAppService.Status
    @Published private(set) var fullDiskAccess: Bool
    /// Space earlier cleans moved aside that is not deleted yet.
    @Published private(set) var purgeBacklog: Int64
    /// A preview in progress, shown until it finishes when there is no earlier preview.
    @Published private(set) var scan: ScanState?
    /// The category whose items the panel shows instead of the overview.
    @Published var selected: JanitorCore.Category?
    @Published var confirmingClean = false
    @Published var hoveredItem: String?

    /// The config `preview` was planned with.
    private var previewedWith: Config?
    /// Identifies the latest preview; a clean bumps it to discard one in flight.
    private var previewID = 0
    private let live: Bool
    private var panelOpen = false
    private var timer: Timer?
    private var watchTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var measuringPurge = false

    static let previewMaxAge: TimeInterval = 300

    /// Unless `live`, the state stays as given: no disk, CLI or timers.
    init(config: Config = Config(), freeBytes: Int64, totalBytes: Int64, lastRun: Report? = nil,
         preview: Report? = nil, restored: Bool = false, busy: Busy? = nil, problem: String? = nil,
         loginStatus: SMAppService.Status = .notRegistered, agentStatus: SMAppService.Status = .notRegistered,
         fullDiskAccess: Bool = true, purgeBacklog: Int64 = 0, scan: ScanState? = nil, live: Bool = false) {
        self.config = config
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.lastRun = lastRun
        self.preview = preview
        self.previewedWith = preview == nil ? nil : config
        self.restored = restored
        self.busy = busy
        self.problem = problem
        self.loginStatus = loginStatus
        self.agentStatus = agentStatus
        self.fullDiskAccess = fullDiskAccess
        self.purgeBacklog = purgeBacklog
        self.scan = scan
        self.live = live
    }

    static func live() -> Store {
        let (free, total) = Self.diskSpace()
        let store = Store(config: Config(), freeBytes: free, totalBytes: total, lastRun: Report.load(),
                          loginStatus: SMAppService.mainApp.status, agentStatus: Background.status,
                          fullDiskAccess: Privacy.hasFullDiskAccess, live: true)
        store.reloadConfig()
        store.restoreSavedPreview()
        store.startObserving()
        return store
    }

    private func startObserving() {
        // The menu-bar icon is visible with the panel closed, so free space and the
        // launchd job are checked on a timer as well as on open.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if self.busy == nil, Janitor.isRunning() { self.watchScheduledRun() }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.windowBecameKey(note.object as? NSWindow) }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.windowResignedKey(note.object as? NSWindow) }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    // MARK: - Derived state

    var isLowDisk: Bool { freeBytes > 0 && Double(freeBytes) < config.lowDiskGB * 1e9 }

    var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - freeBytes) / Double(totalBytes) : 0
    }

    /// The report the panel lists: the last preview, or what the one running found so far.
    private var shown: Report? { preview ?? scan?.report }

    /// Whether the panel has data for this category yet.
    func covers(_ c: JanitorCore.Category) -> Bool {
        if preview != nil { return previewedWith?.enabled(c) ?? false }
        return scan?.done.contains(c) ?? false
    }

    /// Categories the user has turned on, in display order.
    var enabledCategories: [JanitorCore.Category] { JanitorCore.Category.allCases.filter(config.enabled) }

    /// How far the running preview is, by categories finished.
    var scanProgress: Double {
        guard let scan, !enabledCategories.isEmpty else { return 0 }
        return Double(scan.done.intersection(enabledCategories).count) / Double(enabledCategories.count)
    }

    /// A clean or preview has nothing to show for any category yet.
    var isFirstScan: Bool { preview == nil && busy == .previewing }

    func items(_ c: JanitorCore.Category) -> [Item] {
        guard let preview = shown, config.enabled(c) else { return [] }
        var items: [Item] = []
        for a in preview.actions where a.category == c {
            let kind: Item.Kind = a.status == .failed ? .failed : config.isKept(a.target) ? .kept : .planned
            let label = ItemLabel.describe(a.target, c)
            items.append(Item(id: a.id, target: a.target, name: label.title, bytes: a.bytes,
                              kind: kind, detail: a.error ?? a.reason, label: label))
        }
        for s in preview.skips where s.category == c {
            let kind: Item.Kind = !s.kept ? .guarded : config.isKept(s.target) ? .kept : .pending
            let label = ItemLabel.describe(s.target, c)
            items.append(Item(id: s.id, target: s.target, name: label.title, bytes: s.bytes,
                              kind: kind, detail: s.reason, label: label))
        }
        func rank(_ k: Item.Kind) -> Int {
            switch k {
            case .failed: return 0
            case .planned: return 1
            case .pending: return 2
            case .kept: return 3
            case .guarded: return 4
            }
        }
        return items.sorted { (rank($0.kind), -$0.bytes, $0.name) < (rank($1.kind), -$1.bytes, $1.name) }
    }

    func plannedBytes(_ c: JanitorCore.Category) -> Int64 {
        items(c).filter { $0.kind == .planned }.reduce(0) { $0 + $1.bytes }
    }

    /// Exactly the items shown as planned; a clean removes these and nothing else.
    var planned: [Item] {
        JanitorCore.Category.allCases.flatMap { items($0) }.filter { $0.kind == .planned }
    }

    var plannedBytes: Int64 { planned.reduce(0) { $0 + $1.bytes } }

    func issues(_ c: JanitorCore.Category) -> [String] {
        (preview ?? lastRun)?.issues.filter { $0.category == c }.map(\.message) ?? []
    }

    /// The config changed in a way the preview cannot reflect locally: another plan
    /// input, a re-enabled category, or an unpinned target.
    private var previewIsStale: Bool {
        guard let then = previewedWith else { return true }
        return config.invalidates(previewPlannedWith: then)
    }

    /// A real run started after the preview did, so some of what it plans may be gone.
    private var previewPredatesRun: Bool {
        guard let preview, let lastRun else { return false }
        return lastRun.startedAt > preview.startedAt
    }

    /// Scheduled runs happen: the background job is registered and not paused.
    var automatic: Bool { agentStatus.isOn && !config.paused }

    /// When the next scheduled run is due, or nil when automatic cleaning is off.
    var nextRun: Date? {
        guard automatic else { return nil }
        guard let lastRun, !isLowDisk else { return Date() }
        return max(Date(), lastRun.startedAt.addingTimeInterval(config.intervalHours * 3600))
    }

    // MARK: - Lifecycle

    private static func diskSpace() -> (free: Int64, total: Int64) {
        let total = (try? Paths.home.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity
        return (freeDiskBytes(), Int64(total ?? 0))
    }

    func refresh() {
        guard live else { return }
        (freeBytes, totalBytes) = Self.diskSpace()
        lastRun = Report.load()
        reloadConfig()
        loginStatus = SMAppService.mainApp.status
        agentStatus = Background.status
        Task { await refreshAccess() }
        measurePurgeBacklog()
    }

    /// Walks the purge folder off the main thread; it can hold hundreds of GB.
    private func measurePurgeBacklog() {
        guard !measuringPurge else { return }
        measuringPurge = true
        Task {
            purgeBacklog = await Task.detached(priority: .utility) { FS.purgeBacklogBytes }.value
            measuringPurge = false
        }
    }

    func refreshAccess() async {
        guard live else { return }
        let granted = await AccessCheck.run()
        if granted && !fullDiskAccess {
            // Folders the last preview could not read are readable now.
            previewedWith = nil
        }
        if granted != fullDiskAccess { fullDiskAccess = granted }
        agentStatus = Background.status
    }

    /// The menu-bar panel is the only window without a title.
    private func isPanel(_ window: NSWindow?) -> Bool {
        window.map { $0.className.contains("MenuBarExtra") || $0.title.isEmpty } ?? false
    }

    private func windowBecameKey(_ window: NSWindow?) {
        guard isPanel(window) else { return refresh() }
        panelOpened()
    }

    private func windowResignedKey(_ window: NSWindow?) {
        guard isPanel(window) else { return }
        panelOpen = false
        confirmingClean = false
    }

    private func restoreSavedPreview() {
        guard let saved = SavedPreview.load(config: config),
              lastRun.map({ $0.startedAt < saved.report.startedAt }) ?? true else { return }
        preview = saved.report
        previewedWith = saved.config
        restored = true
    }

    /// Drops the preview, in memory and on disk, so the next one starts from scratch.
    private func forgetPreview() {
        preview = nil
        previewedWith = nil
        restored = false
        SavedPreview.discard()
    }

    /// Opening the panel with Option held rescans from scratch.
    private func panelOpened() {
        panelOpen = true
        refresh()
        guard busy == nil else { return }
        if NSEvent.modifierFlags.contains(.option) { forgetPreview() }
        if Janitor.isRunning() {
            watchScheduledRun()
        } else if restored || previewIsStale || previewPredatesRun
                    || preview.map({ -$0.finishedAt.timeIntervalSinceNow > Self.previewMaxAge }) ?? true {
            Task { await runPreview() }
        }
    }

    /// Polls until another run releases the lock; what it removed makes the preview stale.
    private func watchScheduledRun() {
        busy = .scheduled
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, !Janitor.isRunning() else { return }
                timer.invalidate()
                self.busy = nil
                self.forgetPreview()
                self.refresh()
                if self.panelOpen { await self.runPreview() }
            }
        }
    }

    func runPreview() async {
        guard live, busy == nil else { return }
        if Janitor.isRunning() { return watchScheduledRun() }
        busy = .previewing
        previewID += 1
        let id = previewID
        let cfg = config
        scan = ScanState()
        let outcome = await JanitorRunner.run(dryRun: true) { [weak self] event in
            Task { @MainActor in
                guard let self, id == self.previewID else { return }
                self.scan?.apply(event)
            }
        }
        // A clean started meanwhile; this plan predates it.
        guard id == previewID else { return }
        busy = nil
        scan = nil
        refresh()
        if Janitor.isRunning() { return watchScheduledRun() }
        problem = outcome.problem
        if let report = outcome.report {
            preview = report
            previewedWith = cfg
            restored = false
            try? SavedPreview(report: report, config: cfg).save()
            // Settings changed, or a real run came and went, while it ran.
            if previewIsStale || previewPredatesRun, panelOpen { await runPreview() }
        }
    }

    /// Can run while a preview refreshes, as the CLI acts only on ids it still plans, but
    /// never from a saved preview.
    var canClean: Bool { !restored && (busy == nil || busy == .previewing) && !planned.isEmpty }

    func clean() async {
        let targets = planned.map { (id: $0.id, bytes: $0.bytes) }
        guard live, canClean else { return }
        previewID += 1
        confirmingClean = false
        scan = nil
        busy = .cleaning
        problem = nil
        let outcome = await JanitorRunner.run(dryRun: false, only: targets)
        busy = nil
        refresh()
        if outcome.locked { return watchScheduledRun() }
        problem = outcome.problem
        guard var report = outcome.report else { return }
        // Removed items go and failures stay. Kept and guarded items were not part of
        // the run, so they carry over from the preview.
        let before = preview
        report.actions = report.actions.filter { $0.status == .failed }
            + (before?.actions.filter { config.isKept($0.target) } ?? [])
        report.skips = before?.skips ?? []
        preview = report
        previewedWith = config
    }

    // MARK: - Settings

    /// A broken config.json stays broken until fixed by hand: saving over it would
    /// drop whatever the user meant, and the CLI refuses to run on it meanwhile.
    @discardableResult
    private func reloadConfig() -> Bool {
        do {
            config = try Config.load()
            if configProblem != nil, problem == configProblem { problem = nil }
            configProblem = nil
            return true
        } catch {
            configProblem = "\(error)"
            problem = configProblem
            return false
        }
    }

    func update(_ change: (inout Config) -> Void) {
        guard !live || reloadConfig() else { return }
        var c = config
        change(&c)
        guard c != config else { return }
        guard live else { config = c; return }
        do {
            try c.save()
        } catch {
            problem = "Could not save \(Format.path(Paths.config.path)): \(error.localizedDescription)"
        }
        reloadConfig()
    }

    /// Applies config changes made in settings to the preview.
    func settingsClosed() {
        if previewIsStale, panelOpen { Task { await runPreview() } }
    }

    func setEnabled(_ c: JanitorCore.Category, _ on: Bool) {
        update { cfg in
            cfg.disabled.removeAll { $0 == c }
            if !on { cfg.disabled.append(c) }
        }
        if on, previewIsStale { Task { await runPreview() } }
    }

    func pin(_ target: String) {
        update { $0.keep.append(target) }
    }

    /// Removes every `keep` entry that protects `target`.
    func unpin(_ target: String) {
        update { cfg in
            let entries = cfg.keepEntries(for: target)
            cfg.keep.removeAll { entries.contains($0) }
        }
        if panelOpen, previewIsStale { Task { await runPreview() } }
    }

    func setLaunchAtLogin(_ on: Bool) {
        problem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = "Launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    /// Turns scheduled runs on (registering the background job) or off (pausing them).
    func setAutomatic(_ on: Bool) {
        problem = nil
        defer { agentStatus = Background.status }
        if on {
            do {
                try Background.enable()
            } catch {
                problem = "Could not turn on automatic cleaning: \(error.localizedDescription)"
                return
            }
        }
        update { $0.paused = !on }
    }

    func reveal(_ target: String) {
        guard target.hasPrefix("/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    func openLog() {
        guard FileManager.default.fileExists(atPath: Paths.log.path) else {
            problem = "No log yet at \(Format.path(Paths.log.path))"
            return
        }
        NSWorkspace.shared.open(Paths.log)
    }
}

