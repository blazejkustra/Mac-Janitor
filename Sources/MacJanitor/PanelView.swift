import AppKit
import JanitorCore
import SwiftUI

enum Metrics {
    static let width: CGFloat = 360
    static let inset: CGFloat = 14
    static let listHeight: CGFloat = 400
    static let windowRadius: CGFloat = 22
    static let cardRadius: CGFloat = 12
}

struct PanelView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Group {
            if let category = store.selected {
                CategoryDetailView(category: category)
            } else {
                OverviewView()
            }
        }
        .frame(width: Metrics.width)
        .tint(Palette.accent)
    }
}

// MARK: - Overview

private struct OverviewView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeroCard()
            if !store.fullDiskAccess { AccessBanner() }
            if let problem = store.problem {
                ProblemBanner(text: problem) { store.problem = nil }
            }
            CategoryGrid()
                .opacity(store.restored ? 0.5 : 1)
                .animation(.easeOut(duration: 0.2), value: store.restored)
            CleanArea()
            FooterView().padding(.horizontal, 2).padding(.top, 2)
        }
        .padding(Metrics.inset)
    }
}

/// The headline: what can be freed, or what the scan is doing, beside a ring.
private struct HeroCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if scanning && store.scanProgress == 0 {
                    SpinningRing { ringCenter }
                } else {
                    Ring(fraction: ringFraction, tint: ringTint, lineWidth: 7) { ringCenter }
                }
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 3) {
                headline
                Text("\(Format.bytes(store.freeBytes)) free of \(Format.bytes(store.totalBytes))"
                     + (store.isLowDisk ? ", running low" : ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(store.isLowDisk ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.secondary))
                if store.purgeBacklog > 0 {
                    Text("\(Format.bytes(store.purgeBacklog)) from earlier cleans still being deleted")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.trailing, 22)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.stroke))
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "gearshape", label: "Settings") { Windows.shared.showSettings() }
                .padding(8)
        }
    }

    private var scanning: Bool { store.busy == .previewing }

    private var ringFraction: Double {
        scanning ? max(store.scanProgress, 0.04) : store.usedFraction
    }

    private var ringTint: Color {
        if scanning { return Palette.accent }
        if store.isLowDisk { return Palette.critical }
        return store.usedFraction > 0.95 ? Palette.warning : Palette.accent
    }

    @ViewBuilder
    private var ringCenter: some View {
        if scanning && store.scanProgress == 0 {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
        } else if scanning {
            Text("\(Int(store.scanProgress * 100))%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        } else {
            VStack(spacing: 0) {
                Text("\(Int(store.usedFraction * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text("used").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch store.busy {
        case .previewing:
            if store.restored {
                BigNumber(text: "Refreshing…", caption: "")
            } else if store.preview != nil {
                BigNumber(text: Format.bytes(store.plannedBytes), caption: "refreshing")
            } else if store.plannedBytes > 0 {
                BigNumber(text: Format.bytes(store.plannedBytes), caption: "found so far")
            } else {
                BigNumber(text: "Scanning", caption: "")
            }
            Text(store.scan?.step ?? "Starting")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let folder = store.scan?.folder {
                Text(Format.path(folder))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .cleaning:
            BigNumber(text: "Cleaning", caption: "\(store.planned.count) items")
        case .scheduled:
            BigNumber(text: "Cleaning", caption: "scheduled run")
        case nil:
            if store.preview == nil {
                BigNumber(text: "Not scanned", caption: "")
            } else if store.plannedBytes > 0 {
                BigNumber(text: Format.bytes(store.plannedBytes), caption: "can be freed")
            } else {
                BigNumber(text: "All clean", caption: "")
            }
        }
    }
}

private struct BigNumber: View {
    let text: String
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "lock.shield", size: 28, symbolStyle: Palette.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("Full Disk Access is off").font(.system(size: 12, weight: .semibold))
                Text("Desktop, Documents, Downloads and the Trash are skipped.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button("Fix") { Windows.shared.showOnboarding(step: .access) }
                .buttonStyle(SoftButtonStyle())
                .pointingCursor()
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.stroke))
    }
}

struct ProblemBanner: View {
    let text: String
    let dismiss: () -> Void

    static func shorten(_ s: String) -> String {
        (s.hasPrefix("janitor: ") ? String(s.dropFirst(9)) : s)
            .replacingOccurrences(of: Paths.support.path + "/", with: "")
            .replacingOccurrences(of: Paths.home.path, with: "~")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "xmark.octagon.fill")
            Text(Self.shorten(text))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "xmark", label: "Dismiss", action: dismiss)
        }
        .font(.caption)
        .foregroundStyle(Palette.critical)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.critical.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

private struct CategoryGrid: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(store.enabledCategories, id: \.self) { CategoryTile(category: $0) }
        }
    }
}

/// A category as a tile: its symbol, how much it would free, and its name.
private struct CategoryTile: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category
    @State private var hovering = false

    var body: some View {
        let issues = store.issues(category)
        let state = TileState(covered: store.covers(category), bytes: store.plannedBytes(category), hasIssue: !issues.isEmpty)
        let empty = state == .nothing
        Button { store.selected = category } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(empty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.icon))
                        .frame(height: 18)
                    Spacer()
                    if !issues.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Palette.warning)
                    }
                }
                Spacer(minLength: 8)
                sizeText(state)
                Text(category.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(hovering ? Palette.cardHover : Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.stroke))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(issues.map(ProblemBanner.shorten).joined(separator: "\n"))
        .accessibilityLabel("\(category.title), \(Self.spoken(state))")
        .pointingCursor()
    }

    private static func spoken(_ state: TileState) -> String {
        switch state {
        case .checking: return "checking"
        case .found(let bytes): return Format.bytes(bytes)
        case .nothing: return "none"
        case .unchecked: return "couldn't check"
        }
    }

    @ViewBuilder
    private func sizeText(_ state: TileState) -> some View {
        switch state {
        case .found(let bytes):
            Text(Format.bytes(bytes))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
        case .nothing:
            Text("None")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tertiary)
        case .unchecked:
            Text("Couldn't check")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 21)
        case .checking:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Checking").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            }
            .frame(height: 21)
        }
    }
}

// MARK: - Clean

private struct CleanArea: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        if store.confirmingClean {
            CleanConfirmation()
        } else {
            CleanButton()
        }
    }
}

private struct CleanButton: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let total = store.plannedBytes
        Button { store.confirmingClean = true } label: {
            HStack(spacing: 6) {
                if store.busy == .cleaning {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Cleaning")
                } else {
                    Image(systemName: "trash")
                    Text(title(total)).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle(active: store.busy == .cleaning))
        .disabled(!store.canClean)
        .pointingCursor(enabled: store.canClean)
    }

    private func title(_ total: Int64) -> String {
        if total > 0 { return "Clean \(Format.bytes(total))…" }
        return store.isFirstScan ? "Scanning…" : "Nothing to clean"
    }
}

private struct CleanConfirmation: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let groups = store.enabledCategories
            .map { ($0, store.items($0).filter { $0.kind == .planned }) }
            .filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 10) {
            BigNumber(text: Format.bytes(store.plannedBytes), caption: "in \(store.planned.count) items")
            VStack(alignment: .leading, spacing: 5) {
                ForEach(groups, id: \.0) { category, items in
                    HStack(spacing: 8) {
                        Image(systemName: category.symbol)
                            .foregroundStyle(Palette.icon)
                            .frame(width: 18)
                        Text(category.title)
                        Spacer()
                        Text(Format.bytes(items.reduce(0) { $0 + $1.bytes })).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
            Text("This cannot be undone, except large files, which go to the Trash. Uncommitted work in worktrees is saved first.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Cancel") { store.confirmingClean = false }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .pointingCursor()
                Spacer()
                Button("Clean now") { Task { await store.clean() } }
                    .buttonStyle(PillButtonStyle(tint: Palette.criticalFill))
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.stroke))
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(store.automatic ? Palette.accent : Palette.icon.opacity(0.5)).frame(width: 6, height: 6)
                Text(scheduleText).lineLimit(1)
                Spacer()
                Button(store.automatic ? "Pause" : "Turn on") { toggleAutomatic() }
                    .buttonStyle(SoftButtonStyle())
                    .pointingCursor()
            }
            .font(.system(size: 11.5))
            Text(lastRunText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// Turning it on for the first time goes through setup, which explains what will run.
    private func toggleAutomatic() {
        if store.automatic {
            store.setAutomatic(false)
        } else {
            Windows.shared.showOnboarding(step: .schedule)
        }
    }

    private var lastRunText: String {
        guard let run = store.lastRun else { return "Mac Janitor has not cleaned anything yet." }
        let freed = run.freedBytes
        let removed = run.actions.filter { $0.status == .removed }.count
        let what = freed > 0 ? "freed \(Format.bytes(freed))" : "removed \(removed) items"
        return "Last clean \(Format.ago(run.finishedAt)), \(what)."
    }

    private var scheduleText: String {
        guard let next = store.nextRun else { return "Automatic cleaning is off" }
        let s = Format.span(next.timeIntervalSinceNow)
        return "Cleans every \(Format.number(store.config.intervalHours)) h, next " + (s == "now" ? "soon" : "in \(s)")
    }
}

// MARK: - Shared controls

struct IconButton: View {
    let symbol: String
    let label: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
        .help(label)
        .accessibilityLabel(label)
        .pointingCursor()
    }
}

extension View {
    /// The pointing hand over something clickable; not-allowed when it is disabled.
    func pointingCursor(enabled: Bool = true) -> some View {
        onHover { inside in
            if inside {
                (enabled ? NSCursor.pointingHand : NSCursor.operationNotAllowed).push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
