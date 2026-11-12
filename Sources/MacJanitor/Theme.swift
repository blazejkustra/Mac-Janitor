import AppKit
import JanitorCore
import SwiftUI

/// Colours and building blocks shared by the panel, settings and setup.
enum Palette {
    static let window = dynamic(dark: NSColor(white: 0.11, alpha: 1), light: NSColor(red: 0.955, green: 0.955, blue: 0.965, alpha: 1))
    static let card = dynamic(dark: NSColor(white: 1, alpha: 0.06), light: NSColor.white)
    static let cardHover = dynamic(dark: NSColor(white: 1, alpha: 0.1), light: NSColor(white: 0, alpha: 0.04))
    static let stroke = dynamic(dark: NSColor(white: 1, alpha: 0.06), light: NSColor(white: 0, alpha: 0.07))
    static let divider = dynamic(dark: NSColor(white: 1, alpha: 0.08), light: NSColor(white: 0, alpha: 0.08))
    static let selection = dynamic(dark: NSColor(white: 1, alpha: 0.1), light: NSColor(white: 0, alpha: 0.07))
    /// Glacier blue from the app icon, a shade lighter in dark mode.
    static let accent = dynamic(dark: NSColor(srgbRed: 0.25, green: 0.55, blue: 0.75, alpha: 1),
                                light: NSColor(srgbRed: 0.15, green: 0.40, blue: 0.58, alpha: 1))
    static let accentFill = dynamic(dark: NSColor(srgbRed: 0.18, green: 0.44, blue: 0.63, alpha: 1),
                                    light: NSColor(srgbRed: 0.15, green: 0.40, blue: 0.58, alpha: 1))
    static let track = dynamic(dark: NSColor(white: 1, alpha: 0.1), light: NSColor(white: 0, alpha: 0.08))
    static let well = dynamic(dark: NSColor(white: 1, alpha: 0.08), light: NSColor(white: 0, alpha: 0.05))
    static let icon = dynamic(dark: NSColor(white: 1, alpha: 0.6), light: NSColor(white: 0, alpha: 0.55))
    static let warning = dynamic(dark: NSColor(srgbRed: 0.85, green: 0.64, blue: 0.25, alpha: 1),
                                 light: NSColor(srgbRed: 0.72, green: 0.47, blue: 0.12, alpha: 1))
    static let critical = dynamic(dark: NSColor(srgbRed: 0.90, green: 0.40, blue: 0.35, alpha: 1),
                                  light: NSColor(srgbRed: 0.75, green: 0.22, blue: 0.17, alpha: 1))
    static let criticalFill = dynamic(dark: NSColor(srgbRed: 0.70, green: 0.25, blue: 0.22, alpha: 1),
                                      light: NSColor(srgbRed: 0.75, green: 0.22, blue: 0.17, alpha: 1))

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// A neutral rounded square with a monochrome symbol: how every section is marked.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 26
    var symbolStyle: Color = Palette.icon

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Palette.well)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(symbolStyle)
            )
            .frame(width: size, height: size)
    }
}

/// Grouped rows on a lighter rounded surface, divided by hairlines.
struct Card<Content: View>: View {
    var radius: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            _VariadicView.Tree(DividedLayout()) { content }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.stroke))
    }
}

private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Rectangle().fill(Palette.divider).frame(height: 1).padding(.leading, 14)
            }
        }
    }
}

/// A title, a grey line under it and a control on the right.
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { IconTile(symbol: symbol, size: 28) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Small grey heading above a card, with an optional text action on the right.
struct SectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .pointingCursor()
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct PageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .padding(.bottom, 2)
    }
}

/// A grey line under a card.
struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

/// "Granted" with an accent dot or "Off" with an amber one, in a neutral capsule.
struct StatusPill: View {
    let text: String
    let good: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(good ? Palette.accent : Palette.warning).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Palette.well, in: Capsule())
    }
}

/// A ring that fills with `fraction`, with content in the middle.
struct Ring<Center: View>: View {
    let fraction: Double
    let tint: Color
    var lineWidth: CGFloat = 7
    @ViewBuilder let center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            center
        }
    }
}

/// A ring with a short arc going round, for work whose length is unknown yet.
struct SpinningRing<Center: View>: View {
    var lineWidth: CGFloat = 7
    @ViewBuilder let center: Center

    var body: some View {
        TimelineView(.animation) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            ZStack {
                Circle().stroke(Palette.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360 - 90))
                center
            }
        }
    }
}

/// The large pill buttons used for the main action of a view.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Palette.accentFill
    var active = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = isEnabled || active
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(lit ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.well), in: Capsule())
            .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .contentShape(Capsule())
    }
}

/// A quieter pill for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Palette.well, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// The translucent material behind sidebars.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// One row of a window sidebar: a symbol, a name and a soft highlight when selected.
struct SidebarItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    var done = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(symbol: done ? "checkmark" : symbol, size: 24,
                         symbolStyle: done ? Palette.accent : selected ? .primary : Palette.icon)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(selected ? Palette.selection : hovering ? Palette.selection.opacity(0.5) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingCursor()
    }
}

/// The app's name and mark at the foot of a sidebar.
struct AppSignature: View {
    var body: some View {
        HStack(spacing: 8) {
            AppMark(size: 22)
            Text("Mac Janitor").font(.system(size: 13, weight: .semibold))
        }
    }
}

/// The mark from assets/logo.svg; a bare binary outside the bundle shows a tile in its colours instead.
struct AppMark: View {
    var size: CGFloat

    private static let icon = Bundle.main.image(forResource: "Logo")

    var body: some View {
        if let icon = Self.icon {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            IconTile(symbol: "trash.fill", size: size, symbolStyle: Palette.accent)
        }
    }
}

/// A window with a sidebar on the left and a scrolling page on the right.
struct SidebarWindowLayout<Sidebar: View, Page: View>: View {
    var sidebarWidth: CGFloat = 210
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let page: Page

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                sidebar
            }
            .padding(.horizontal, 10)
            .padding(.top, 52)
            .padding(.bottom, 16)
            .frame(width: sidebarWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(SidebarMaterial())
            Rectangle().fill(Palette.divider).frame(width: 1)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.window)
        }
        .ignoresSafeArea()
    }
}
