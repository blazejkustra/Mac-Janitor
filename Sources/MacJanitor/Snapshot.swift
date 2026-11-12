import AppKit
import JanitorCore
import SwiftUI

/// Renders the panel and windows for fixture states, light and dark, to `<dir>/<fixture>-<appearance>.png`.
/// Offscreen AppKit rendering, because ImageRenderer cannot draw switches and steppers.
@MainActor
enum Snapshot {
    static func render(to dir: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.setVolatileDomain(["AppleLocale": "en_US", "AppleLanguages": ["en"]],
                                                forName: UserDefaults.argumentDomain)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, make) in fixtures {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let url = dir.appendingPathComponent("\(name)-\(suffix).png")
                write(image(make(), NSAppearance(named: appearance)!), to: url)
            }
        }
        write(image(panel(site), NSAppearance(named: .darkAqua)!, background: .clear),
              to: dir.appendingPathComponent("site-panel.png"))
    }

    private static func write(_ png: Data?, to url: URL) {
        guard let png else {
            FileHandle.standardError.write(Data("could not render \(url.lastPathComponent)\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: url)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
        print(url.path)
    }

    /// `background: .clear` leaves the panel transparent, for compositing onto a material.
    private static func image(_ view: AnyView, _ appearance: NSAppearance,
                              background: NSColor = .windowBackgroundColor) -> Data? {
        let host = NSHostingView(rootView: view.background(Color(nsColor: background)))
        let window = ActiveWindow(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 600),
                                  styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        // Measured heights (the item list) land a few layout passes later.
        for _ in 0..<2 {
            settle(host)
            window.setContentSize(host.fittingSize)
        }
        settle(host)
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                         pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Switches draw their grey, inactive look unless the app is active, which this
    /// process cannot become without stealing focus. Overrides a private AppKit hook.
    /// The fixed 3x scale keeps text sharp whatever display this runs on.
    private final class ActiveWindow: NSWindow {
        @objc func _hasActiveControls() -> Bool { true }
        override var backingScaleFactor: CGFloat { 3 }
    }

    private static func settle(_ view: NSView) {
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Fixtures

    private static let gb: Int64 = 1_000_000_000
    private static let total: Int64 = 994 * gb
    private static let home = Paths.home.path
    private static let worktrees = "\(home)/dev/engineering/argent-worktrees"

    private static func ago(_ hours: Double) -> Date { Date().addingTimeInterval(-hours * 3600) }

    private static var lastRun: Report {
        Report(startedAt: ago(2.1), finishedAt: ago(2), dryRun: false, freeBytesBefore: 120 * gb,
               freeBytesAfter: 124_900_000_000, actions: [], skips: [], issues: [])
    }

    private static func dryRun(_ actions: [Action], skips: [Skip] = [], issues: [Issue] = []) -> Report {
        Report(startedAt: ago(0.02), finishedAt: ago(0.01), dryRun: true, freeBytesBefore: 124 * gb,
               freeBytesAfter: 124 * gb, actions: actions, skips: skips, issues: issues)
    }

    private static func planned(_ c: JanitorCore.Category, _ target: String, _ bytes: Int64,
                                _ reason: String = "untouched for 4.2 days") -> Action {
        Action(category: c, target: target, reason: reason, bytes: bytes, status: .planned)
    }

    private static var mixedPreview: Report {
        dryRun([
            planned(.worktree, "\(worktrees)/harmony-flag", 2_310_000_000, "merged (PR #767 merged), untouched for 2.0 days"),
            planned(.worktree, "\(worktrees)/fix-tap-retry", 812_000_000, "PR #1490 open, untouched for 3.4 days"),
        ] + nodeModules + [
            planned(.avd, "Pixel_6_API_34", 7_400_000_000, "unused for 9.3 days"),
            planned(.scratchpad, "/private/tmp/claude-501/-Users-me-dev/0c1d2e3f", 48_000_000, "untouched for 15.0 days"),
            planned(.cache, "\(home)/Library/Caches/com.spotify.client", 1_210_000_000, "unused for 41 days"),
            planned(.trash, "\(home)/.Trash/Screen Recording 2026-09-02.mov", 640_000_000, "in the Trash for 12 days"),
        ], issues: [Issue(.dockerImage, "Docker is not running")])
    }

    /// The node_modules list from the bug report, with the context each row now carries.
    private static var nodeModules: [Action] {
        let dev = "\(home)/Developer"
        return [
            planned(.nodeModules, "\(dev)/witryna-landing-clay/node_modules", 1_160_000_000, "worktree untouched for 6.6 days"),
            planned(.nodeModules, "\(dev)/uncut/.claude/worktrees/agent-a578b48dc68f31141/node_modules", 1_120_000_000,
                    "worktree untouched for 8.9 days"),
            planned(.nodeModules, "\(dev)/uncut/.claude/worktrees/factory-gates/node_modules", 1_110_000_000,
                    "worktree untouched for 9.5 days"),
            planned(.nodeModules, "\(dev)/argent/.claude/worktrees/agent-a7b1251c0208dde89/packages/docs/node_modules",
                    818_000_000, "worktree untouched for 14.7 days"),
            planned(.nodeModules, "\(dev)/uncut/.claude/worktrees/agent-a393c0ea3e1f4cdf9/node_modules", 708_000_000,
                    "worktree untouched for 19.2 days"),
            planned(.nodeModules, "\(home)/.t3/worktrees/argent/t3-a6c8cef2/node_modules", 367_000_000,
                    "worktree untouched for 14.7 days"),
            planned(.nodeModules, "\(dev)/argent/.claude/worktrees/agent-a7b1251c0208dde89/packages/tool-server/node_modules",
                    3_200_000, "worktree untouched for 14.7 days"),
            planned(.nodeModules, "\(home)/.t3/worktrees/argent/t3-a6c8cef2/packages/tool-server/node_modules", 3_200_000,
                    "worktree untouched for 14.7 days"),
        ]
    }

    /// The landing page panel: every agent category holds something, only large files stay empty.
    private static var sitePreview: Report {
        let dev = "\(home)/Developer"
        return dryRun([
            planned(.worktree, "\(worktrees)/harmony-flag", 2_310_000_000, "merged (PR #767 merged), untouched for 2.0 days"),
            planned(.worktree, "\(worktrees)/fix-tap-retry", 812_000_000, "PR #1490 open, untouched for 3.4 days"),
            planned(.worktree, "\(dev)/uncut/.claude/worktrees/factory-gates", 1_460_000_000, "merged, untouched for 9.5 days"),
        ] + nodeModules + [
            planned(.dockerImage, "agent-sandbox:latest (3f9a1c27be04)", 2_140_000_000, "no container used it for 11 days"),
            planned(.dockerImage, "<none> (9b2e77d1a0c3)", 760_000_000, "no container used it for 23 days"),
            planned(.avd, "Pixel_6_API_34", 7_400_000_000, "unused for 9.3 days"),
            planned(.scratchpad, "/private/tmp/claude-501/-Users-me-dev/0c1d2e3f", 312_000_000, "untouched for 15.0 days"),
            planned(.scratchpad, "/private/tmp/claude-501/-Users-me-dev/7a4b9e01", 168_000_000, "untouched for 18.2 days"),
            planned(.build, "\(dev)/witryna-landing-clay/.next", 1_240_000_000, "witryna-landing-clay untouched for 8 days"),
            planned(.build, "\(home)/Library/Developer/Xcode/DerivedData/Uncut-bxq", 1_860_000_000, "Uncut untouched for 12 days"),
            planned(.cache, "\(home)/Library/Caches/com.spotify.client", 1_210_000_000, "unused for 41 days"),
            planned(.trash, "\(home)/.Trash/Screen Recording 2026-09-02.mov", 640_000_000, "in the Trash for 12 days"),
        ])
    }

    private static var partialScan: ScanState {
        var scan = ScanState()
        scan.apply(.found(.worktree, actions: Array(mixedPreview.actions.prefix(2)), skips: []))
        scan.apply(.found(.nodeModules, actions: nodeModules, skips: []))
        scan.apply(.step("Searching your home folder for build output and large files"))
        scan.apply(.folder("\(home)/Developer/argent/packages/tool-server/src"))
        return scan
    }

    private static func panel(_ store: Store) -> AnyView {
        AnyView(PanelView().environmentObject(store))
    }

    private static func window<V: View>(_ view: V, _ store: Store) -> AnyView {
        AnyView(view.environmentObject(store))
    }

    private static func onboarding(_ step: OnboardingModel.Step, _ store: Store) -> AnyView {
        let model = OnboardingModel()
        model.step = step
        return window(OnboardingView(model: model), store)
    }

    private static var normal: Store {
        Store(freeBytes: 124 * gb, totalBytes: total, lastRun: lastRun, preview: mixedPreview, agentStatus: .enabled)
    }

    private static var site: Store {
        Store(freeBytes: 124 * gb, totalBytes: total, lastRun: lastRun, preview: sitePreview, agentStatus: .enabled)
    }

    private static var fixtures: [(String, () -> AnyView)] {
        [
            ("a-overview", { panel(normal) }),
            ("b-scanning", {
                panel(Store(freeBytes: 124 * gb, totalBytes: total, busy: .previewing, fullDiskAccess: false, scan: partialScan))
            }),
            ("c-detail", {
                var cfg = Config()
                cfg.keep = ["\(home)/Developer/uncut/.claude/worktrees/factory-gates/node_modules"]
                let s = Store(config: cfg, freeBytes: 124 * gb, totalBytes: total, lastRun: lastRun, preview: mixedPreview)
                s.selected = .nodeModules
                s.hoveredItem = "node_modules:\(home)/Developer/witryna-landing-clay/node_modules"
                return panel(s)
            }),
            ("d-confirm", {
                let s = normal
                s.confirmingClean = true
                return panel(s)
            }),
            ("e-empty", {
                var cfg = Config()
                cfg.paused = true
                return panel(Store(config: cfg, freeBytes: 312 * gb, totalBytes: total, lastRun: lastRun, preview: dryRun([])))
            }),
            ("f-error", {
                panel(Store(freeBytes: 12_400_000_000, totalBytes: total, lastRun: lastRun, preview: mixedPreview,
                            problem: "lsof failed, so nothing in use can be told apart"))
            }),
            ("g-settings", { window(SettingsView(), normal) }),
            ("g-settings-categories", { window(SettingsView(page: .categories), normal) }),
            ("g-settings-about", { window(SettingsView(page: .about), normal) }),
            ("g-settings-kept", {
                var cfg = Config()
                cfg.keep = ["\(home)/Developer/uncut/.claude/worktrees/factory-gates", "\(home)/Movies/Final Cut", "Pixel_9_API_36"]
                return window(SettingsView(page: .kept), Store(config: cfg, freeBytes: 124 * gb, totalBytes: total))
            }),
            ("h-onboarding-welcome", { onboarding(.welcome, normal) }),
            ("i-onboarding-access", {
                onboarding(.access, Store(freeBytes: 124 * gb, totalBytes: total, fullDiskAccess: false))
            }),
            ("j-onboarding-access-granted", { onboarding(.access, normal) }),
            ("k-onboarding-schedule", { onboarding(.schedule, normal) }),
            ("l-onboarding-done", { onboarding(.done, normal) }),
        ]
    }
}
