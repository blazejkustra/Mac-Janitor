import AppKit
import JanitorCore
import SwiftUI

/// One category's items, replacing the overview until Back (or Escape).
struct CategoryDetailView: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category

    var body: some View {
        let items = store.items(category)
        let going = items.filter { $0.kind == .planned || $0.kind == .failed || $0.kind == .pending }
        let kept = items.filter { $0.kind == .kept }
        let protected = items.filter { $0.kind == .guarded }
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(category: category, bytes: store.plannedBytes(category))
                .padding(.horizontal, Metrics.inset)
                .padding(.top, 10)
            Text(category.explanation(store.config))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.inset)
                .padding(.top, 6)
            ForEach(store.issues(category), id: \.self) { issue in
                Label(ProblemBanner.shorten(issue), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.inset)
                    .padding(.top, 6)
            }
            Divider().padding(.top, 10)
            if items.isEmpty {
                EmptyCategory(scanning: !store.covers(category))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ItemSection(title: "Will be removed", note: nil, items: going)
                        ItemSection(title: "Kept by you", note: "You pinned these. They stay until you unpin them.", items: kept)
                        ItemSection(title: "Left alone", note: "These match the rules but are in use or unsafe to remove.",
                                    items: protected)
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(Metrics.listHeight, estimatedHeight(items)))
            }
        }
        .padding(.bottom, 8)
    }

    /// A ScrollView in a MenuBarExtra window collapses unless given a height.
    private func estimatedHeight(_ items: [Item]) -> CGFloat {
        CGFloat(items.count) * 64 + 3 * 40
    }
}

private struct DetailHeader: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category
    let bytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { store.selected = nil } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("All categories")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Back (Esc)")
            .pointingCursor()
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: category.symbol).foregroundStyle(Color.accentColor)
                Text(category.title).font(.headline)
                Spacer()
                if bytes > 0 {
                    Text(Format.bytes(bytes)).font(.headline).monospacedDigit()
                }
            }
        }
    }
}

private struct EmptyCategory: View {
    let scanning: Bool

    var body: some View {
        VStack(spacing: 6) {
            if scanning {
                ProgressView().controlSize(.small)
                Text("Still checking…").font(.callout).foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.secondary)
                Text("Nothing to remove here right now").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct ItemSection: View {
    let title: String
    let note: String?
    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) (\(items.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 8)
            .padding(.bottom, 2)
            ForEach(items) { ItemRow(item: $0) }
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var store: Store
    let item: Item

    var body: some View {
        let hovering = store.hoveredItem == item.id
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.label.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(item.kind == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    if item.bytes > 0 {
                        Text(Format.bytes(item.bytes))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.label.context.isEmpty {
                    Text(item.label.contextLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(Format.sentence(item.detail))
                    .font(.caption)
                    .foregroundStyle(item.kind == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ItemActions(item: item, hovering: hovering)
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .help(Format.path(item.target))
        .onHover { inside in
            if inside {
                store.hoveredItem = item.id
            } else if store.hoveredItem == item.id {
                store.hoveredItem = nil
            }
        }
    }
}

private struct ItemActions: View {
    @EnvironmentObject private var store: Store
    let item: Item
    let hovering: Bool

    var body: some View {
        HStack(spacing: 2) {
            if item.target.hasPrefix("/") {
                IconButton(symbol: "folder", label: "Show in Finder") { store.reveal(item.target) }
            }
            switch item.kind {
            case .planned, .failed:
                Button("Keep") { store.pin(item.target) }
                    .controlSize(.small)
                    .help("Never remove this")
                    .pointingCursor()
            case .kept:
                Button("Unkeep") { store.unpin(item.target) }
                    .controlSize(.small)
                    .help("Let the rules decide again")
                    .pointingCursor()
            case .pending:
                Image(systemName: "hourglass").foregroundStyle(.tertiary).frame(width: 22, height: 22)
                    .help("Unpinned; checked again on the next scan")
            case .guarded:
                Image(systemName: "lock.fill").foregroundStyle(.tertiary).frame(width: 22, height: 22)
                    .help("In use or unsafe to remove")
            }
        }
        .opacity(hovering || item.kind == .kept ? 1 : 0.6)
    }
}
