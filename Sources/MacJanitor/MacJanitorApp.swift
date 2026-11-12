import AppKit
import SwiftUI

struct MacJanitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Windows.shared.store = Store.live()
    }

    /// SwiftUI needs a scene; the menu-bar item and its panel are StatusPanel's.
    var body: some Scene {
        MenuBarExtra("Mac Janitor", isInserted: .constant(false)) { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when run as a bare binary without the bundle's LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        MainActor.assumeIsolated { DebugCapture.install() }
        #endif
        MainActor.assumeIsolated {
            if let store = Windows.shared.store { StatusPanel.shared.install(store: store) }
            Updates.shared.start()
        }
        guard !Windows.setupDone else { return }
        MainActor.assumeIsolated { Windows.shared.showOnboarding() }
    }
}
