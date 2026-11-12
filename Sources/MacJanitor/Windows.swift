import AppKit
import SwiftUI

/// The app's real windows: setup and settings. The menu-bar panel is StatusPanel.
@MainActor
final class Windows: NSObject, NSWindowDelegate {
    static let shared = Windows()

    var store: Store?
    let onboarding = OnboardingModel()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    static let setupDoneKey = "setupCompleted"

    static var setupDone: Bool {
        get { UserDefaults.standard.bool(forKey: setupDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupDoneKey) }
    }

    func showSettings() {
        guard let store else { return }
        settingsWindow = settingsWindow ?? makeWindow(title: "Mac Janitor Settings",
                                                      view: SettingsView().environmentObject(store))
        present(settingsWindow)
    }

    func showOnboarding(step: OnboardingModel.Step = .welcome) {
        guard let store else { return }
        onboarding.step = step
        onboardingWindow = onboardingWindow ?? makeWindow(title: "Welcome to Mac Janitor",
                                                          view: OnboardingView(model: onboarding).environmentObject(store))
        present(onboardingWindow)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    private func makeWindow<V: View>(title: String, view: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            Self.setupDone = true
        } else if window === settingsWindow {
            store?.settingsClosed()
        }
    }
}
