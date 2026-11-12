import AppKit
import Combine
import SwiftUI

/// The menu-bar item and its panel. A borderless panel of our own, because SwiftUI's
/// MenuBarExtra window fixes its corner (6pt, or 16pt with the macOS 26 SDK).
@MainActor
final class StatusPanel: NSObject, NSWindowDelegate {
    static let shared = StatusPanel()

    private var item: NSStatusItem?
    private var panel: NSPanel?
    private var outsideClicks: Any?
    private var storeChanges: AnyCancellable?
    private var top: NSPoint?

    func install(store: Store) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        self.item = item
        updateIcon(store)
        storeChanges = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak store] in
            guard let store else { return }
            MainActor.assumeIsolated { self?.updateIcon(store) }
        }
        panel = makePanel(store: store)
    }

    @objc private func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        guard let panel, let button = item?.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.minX, screen.minX + 6), screen.maxX - panel.frame.width - 6)
        top = NSPoint(x: x, y: anchor.minY - 6)
        panel.setFrameTopLeftPoint(top!)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        panel?.orderOut(nil)
        item?.button?.highlight(false)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, let top else { return }
        panel.setFrameTopLeftPoint(top)
        panel.invalidateShadow()
    }

    private func makePanel(store: Store) -> NSPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = .roundedMask(radius: Metrics.windowRadius)

        let shape = RoundedRectangle(cornerRadius: Metrics.windowRadius, style: .circular)
        let host = NSHostingView(rootView: PanelView()
            .environmentObject(store)
            .overlay(shape.strokeBorder(Palette.stroke)))
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        return panel
    }

    private func updateIcon(_ store: Store) {
        if store.busy == .cleaning || store.busy == .scheduled {
            item?.button?.image = Self.hourglass
        } else if store.isLowDisk {
            item?.button?.image = Self.warning
        } else {
            item?.button?.image = Self.glyph
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

    private static let hourglass: NSImage = {
        let image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Cleaning")!
        image.isTemplate = true
        return image
    }()

    /// Menu-bar images render as templates; a non-template image keeps its red.
    private static let warning: NSImage = {
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Low disk space")!
            .withSymbolConfiguration(config)!
        image.isTemplate = false
        return image
    }()

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) {
            MainActor.assumeIsolated { StatusPanel.shared.close() }
        }
    }
}

private extension NSImage {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
