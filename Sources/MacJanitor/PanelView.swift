import AppKit
import JanitorCore
import SwiftUI

enum Metrics {
    static let width: CGFloat = 340
    static let inset: CGFloat = 14
    static let icon: CGFloat = 22
    static let listHeight: CGFloat = 380
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
    }
}

// MARK: - Overview

private struct OverviewView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView()
                .padding(.horizontal, Metrics.inset)
                .padding(.top, Metrics.inset)
                .padding(.bottom, 10)
            VStack(spacing: 8) {
                if !store.fullDiskAccess { AccessBanner() }
                if let problem = store.problem {
                    ProblemBanner(text: problem) { store.problem = nil }
                }
                StatusCard()
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(store.enabledCategories, id: \.self) { CategoryRow(category: $0) }
            }
            .padding(.horizontal, 6)
            CleanArea()
                .padding(.horizontal, Metrics.inset)
                .padding(.top, 10)
            Divider().padding(.top, 12)
            FooterView()
                .padding(.horizontal, Metrics.inset)
                .padding(.vertical, 10)
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let free = Format.byteParts(store.freeBytes)
        let tint: Color = store.isLowDisk ? .red : .primary
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(free.number)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(" \(free.unit)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                    Text("  free on this Mac")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(tint)
                Spacer()
                IconButton(symbol: "gearshape", label: "Settings") { Windows.shared.showSettings() }
            }
            CapacityBar(fraction: store.usedFraction, tint: store.isLowDisk ? .red : .accentColor)
            Text("\(Format.bytes(store.totalBytes - store.freeBytes)) of \(Format.bytes(store.totalBytes)) used"
                 + (store.isLowDisk ? ", running low" : ""))
                .font(.caption)
                .foregroundStyle(store.isLowDisk ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }
}

private struct CapacityBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// What the app is doing right now, or what it found.
private struct StatusCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            content
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch store.busy {
        case .previewing:
            ScanningStatus(scan: store.scan, foundBytes: store.plannedBytes, refreshing: store.preview != nil)
        case .cleaning:
            StatusLine(symbol: nil, title: "Cleaning…",
                       detail: "Moving \(store.planned.count) items out of the way. Space frees up in the background.")
        case .scheduled:
            StatusLine(symbol: nil, title: "A scheduled clean is running",
                       detail: "The list refreshes when it finishes.")
        case nil:
            if store.preview == nil {
                StatusLine(symbol: "magnifyingglass", title: "Not scanned yet",
                           detail: "Open this menu again to look for things to clean.")
            } else if store.plannedBytes > 0 {
                StatusLine(symbol: "checkmark.circle", title: "\(Format.bytes(store.plannedBytes)) can be freed",
                           detail: "\(store.planned.count) items. Click a category to see each one and keep what you need.")
            } else {
                StatusLine(symbol: "checkmark.seal", title: "All clean",
                           detail: "Nothing matches the cleaning rules right now.")
            }
        }
    }
}

private struct ScanningStatus: View {
    let scan: ScanState?
    let foundBytes: Int64
    let refreshing: Bool

    var body: some View {
        ProgressView().controlSize(.small).padding(.top, 1)
        VStack(alignment: .leading, spacing: 3) {
            Text(refreshing ? "Refreshing…" : "Scanning…").font(.callout.weight(.semibold))
            Text(scan?.step ?? "Starting").font(.caption).foregroundStyle(.secondary)
            if let folder = scan?.folder {
                Text(Format.path(folder))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !refreshing {
                Text(foundBytes > 0 ? "Found \(Format.bytes(foundBytes)) so far" : "Nothing found yet")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        }
    }
}

private struct StatusLine: View {
    let symbol: String?
    let title: String
    let detail: String

    var body: some View {
        if let symbol {
            Image(systemName: symbol).foregroundStyle(.secondary).padding(.top, 1)
        } else {
            ProgressView().controlSize(.small).padding(.top, 1)
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Full Disk Access is off").font(.caption.weight(.semibold))
                Text("Desktop, Documents, Downloads and the Trash are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn it on…") { Windows.shared.showOnboarding(step: .access) }
                    .controlSize(.small)
                    .pointingCursor()
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
        .foregroundStyle(.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CategoryRow: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category
    @State private var hovering = false

    var body: some View {
        Button { store.selected = category } label: {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 14))
                    .frame(width: Metrics.icon)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(category.title).foregroundStyle(.primary)
                        if !store.issues(category).isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Text(category.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                SizeLabel(category: category)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingCursor()
    }
}

private struct SizeLabel: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category

    var body: some View {
        if store.covers(category) {
            let bytes = store.plannedBytes(category)
            Text(bytes > 0 ? Format.bytes(bytes) : "Nothing")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(bytes > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        } else if store.busy == .previewing {
            Text("Checking")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
        .buttonStyle(ProminentButtonStyle(active: store.busy == .cleaning))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Remove \(store.planned.count) items, \(Format.bytes(store.plannedBytes))?")
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.0) { category, items in
                    HStack {
                        Text("\(category.title) (\(items.count))")
                        Spacer()
                        Text(Format.bytes(items.reduce(0) { $0 + $1.bytes })).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("This cannot be undone, except large files, which go to the Trash. Uncommitted work in worktrees is saved first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { store.confirmingClean = false }
                    .keyboardShortcut(.cancelAction)
                    .pointingCursor()
                Spacer()
                Button("Clean now") { Task { await store.clean() } }
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Drawn by hand: AppKit's prominent bezel goes grey whenever the app is inactive.
struct ProminentButtonStyle: ButtonStyle {
    /// Keeps the accent look while disabled, for work in progress.
    var active = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = isEnabled || active
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(configuration.isPressed ? 0.15 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Footer

private struct FooterView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lastRunText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: store.automatic ? "clock" : "pause.circle")
                Text(scheduleText).lineLimit(1)
                Spacer()
                Button(store.automatic ? "Pause" : "Turn on…") { toggleAutomatic() }
                    .controlSize(.small)
                    .pointingCursor()
            }
            .font(.caption)
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
        let freed = run.freeBytesAfter - run.freeBytesBefore
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
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
