import SwiftUI

/// The panel's reminder of an update a scheduled check found; opens Sparkle's dialog.
struct UpdateBanner: View {
    @EnvironmentObject private var reminder: UpdateReminder
    @State private var hovering = false

    var body: some View {
        if let version = reminder.version {
            Button(action: showUpdate) {
                HStack(spacing: 12) {
                    IconTile(symbol: "arrow.down", size: 24, symbolStyle: Palette.accent)
                    Text("Update available: \(version)")
                        .font(.system(size: TextSize.body, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: TextSize.label, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .surface(hovering ? Palette.cardHover : Palette.card)

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
