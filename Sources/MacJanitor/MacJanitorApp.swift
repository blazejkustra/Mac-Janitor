import AppKit
import SwiftUI

struct MacJanitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: Store

    init() {
        let store = Store.live()
        Windows.shared.store = store
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: Store

    var body: some View {
        if store.busy == .cleaning || store.busy == .scheduled {
            Image(systemName: "hourglass")
        } else if store.isLowDisk {
            // Menu-bar images render as templates; a non-template image keeps its red.
            Image(nsImage: Self.warning)
        } else {
            Image(nsImage: Self.glyph)
        }
    }

    /// Drawn by scripts/icons.swift; a bare binary outside the bundle falls back to a symbol.
    private static let glyph: NSImage = {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)!
        image.isTemplate = true
        image.accessibilityDescription = "Mac Janitor"
        return image
    }()

    private static let warning: NSImage = {
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Low disk space")!
            .withSymbolConfiguration(config)!
        image.isTemplate = false
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when run as a bare binary without the bundle's LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        MainActor.assumeIsolated { DebugCapture.install() }
        #endif
        guard !Windows.setupDone else { return }
        MainActor.assumeIsolated { Windows.shared.showOnboarding() }
    }
}
