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
            DetailHeader(category: category, bytes: store.plannedBytes(category), count: going.count)
            ForEach(store.issues(category), id: \.self) { issue in
                Label(ProblemBanner.shorten(issue), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if items.isEmpty {
                EmptyCategory(scanning: !store.covers(category)).padding(.top, 10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ItemSection(title: "Will be removed", note: nil, items: going)
                        ItemSection(title: "Kept by you", note: "You pinned these. They stay until you unpin them.", items: kept)
                        ItemSection(title: "Left alone", note: "These match the rules but are in use or unsafe to remove.",
                                    items: protected)
                    }
                }
                .frame(height: min(Metrics.listHeight, estimatedHeight(going, kept, protected)))
            }
        }
        .padding(Metrics.inset)
    }

    /// A ScrollView in a MenuBarExtra window collapses unless given a height.
    private func estimatedHeight(_ sections: [Item]...) -> CGFloat {
        sections.filter { !$0.isEmpty }.reduce(0) { $0 + CGFloat($1.count) * 66 + 44 }
    }
}

private struct DetailHeader: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category
    let bytes: Int64
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { store.selected = nil } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("All categories")
                }
            }
            .buttonStyle(SoftButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Back (Esc)")
            .pointingCursor()
            HStack(alignment: .center, spacing: 12) {
                IconTile(symbol: category.symbol, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title).font(.system(size: 17, weight: .semibold))
                    Text(bytes > 0 ? "\(Format.bytes(bytes)) in \(count) items" : "Nothing to remove")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(category.explanation(store.config))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmptyCategory: View {
    let scanning: Bool

    var body: some View {
        VStack(spacing: 8) {
            if scanning {
                ProgressView().controlSize(.small)
                Text("Still checking…").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.icon)
                Text("Nothing to remove here right now").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

private struct ItemSection: View {
    let title: String
    let note: String?
    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            SectionHeader(title: "\(title) (\(items.count))")
            Card(radius: Metrics.cardRadius) {
                ForEach(items) { ItemRow(item: $0) }
            }
            if let note { Footnote(text: note) }
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var store: Store
    let item: Item

    var body: some View {
        let hovering = store.hoveredItem == item.id
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(item.kind == .failed ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.label.context.isEmpty {
                    Text(item.label.contextLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(Format.sentence(item.detail))
                    .font(.system(size: 11))
                    .foregroundStyle(item.kind == .failed ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.tertiary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if item.bytes > 0 {
                Text(Format.bytes(item.bytes))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            ItemActions(item: item, hovering: hovering)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Palette.cardHover : .clear)
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
        HStack(spacing: 0) {
            if item.target.hasPrefix("/") {
                IconButton(symbol: "folder", label: "Show in Finder") { store.reveal(item.target) }
            }
            switch item.kind {
            case .planned, .failed:
                IconButton(symbol: "pin", label: "Keep this") { store.pin(item.target) }
            case .kept:
                IconButton(symbol: "pin.fill", label: "Stop keeping this", tint: Palette.accent) { store.unpin(item.target) }
            case .pending:
                Image(systemName: "hourglass").foregroundStyle(.tertiary).frame(width: 22, height: 22)
            case .guarded:
                Image(systemName: "lock.fill").foregroundStyle(.tertiary).frame(width: 22, height: 22)
            }
        }
        .opacity(hovering || item.kind == .kept ? 1 : 0.55)
    }
}
