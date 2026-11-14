import SwiftUI

/// The panel's reminder of an update a scheduled check found; opens Sparkle's dialog.
struct UpdateBanner: View {
    @EnvironmentObject private var reminder: UpdateReminder
    @State private var hovering = false

    var body: some View {
        if let version = reminder.version {
            Button(action: showUpdate) {
                HStack(spacing: 10) {
                    IconTile(symbol: "arrow.down", size: 22, symbolStyle: Palette.accent)
                    Text("Update available: \(version)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(hovering ? Palette.cardHover : Palette.card,
                            in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.stroke))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .pointingCursor()
        }
    }

    private func showUpdate() {
        StatusPanel.shared.close()
        Updates.shared.check()
    }
}
