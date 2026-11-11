#if DEBUG
import AppKit
import JanitorCore
import SwiftUI

/// Debug builds only: with MACJANITOR_CAPTURE_DIR set, SIGUSR1 runs the commands in
/// `<dir>/cmd` (one per line) so the live UI can be driven and captured without
/// Screen Recording access: `open-panel`, `select <category>`, `back`, `confirm`,
/// `onboarding <step>`, `settings`, `capture <name>`.
@MainActor
enum DebugCapture {
    private static var source: DispatchSourceSignal?

    static func install() {
        guard let dir = ProcessInfo.processInfo.environment["MACJANITOR_CAPTURE_DIR"] else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { runCommands(in: URL(fileURLWithPath: dir)) } }
        source.resume()
        self.source = source
    }

    private static func runCommands(in dir: URL) {
        let text = (try? String(contentsOf: dir.appendingPathComponent("cmd"), encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            run(parts[0], parts.count > 1 ? parts[1] : "", dir: dir)
        }
    }

    private static func run(_ command: String, _ argument: String, dir: URL) {
        let store = Windows.shared.store
        switch command {
        case "open-panel": openPanel()
        case "select": store?.selected = JanitorCore.Category(rawValue: argument)
        case "back": store?.selected = nil
        case "confirm": store?.confirmingClean = argument != "off"
        case "onboarding": Windows.shared.showOnboarding(step: step(argument))
        case "settings": Windows.shared.showSettings()
        case "capture": capture(to: dir, name: argument)
        case "windows":
            let lines = NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \($0.frame) \($0.title)" }
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("windows.txt"), atomically: true, encoding: .utf8)
        default: break
        }
    }

    private static func step(_ name: String) -> OnboardingModel.Step {
        switch name {
        case "access": return .access
        case "schedule": return .schedule
        case "done": return .done
        default: return .welcome
        }
    }

    /// The menu-bar panel's view in a plain window: synthetic clicks cannot open a MenuBarExtra.
    private static var panel: NSWindow?

    private static func openPanel() {
        guard let store = Windows.shared.store else { return }
        let window = panel ?? KeyWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        if panel == nil {
            window.contentViewController = NSHostingController(rootView: PanelView().environmentObject(store))
        }
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: 900, y: 900))
        panel = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private static func capture(to dir: URL, name: String) {
        for (i, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.height > 40 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let label = window.title.isEmpty ? "panel" : "window\(i)"
            try? rep.representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name)-\(label).png"))
        }
    }
}
#endif
