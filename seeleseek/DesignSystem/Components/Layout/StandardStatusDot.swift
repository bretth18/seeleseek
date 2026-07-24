import SwiftUI
import SeeleseekCore

/// Consistent status indicator dot
struct StandardStatusDot: View {
    let status: BuddyStatus
    var size: CGFloat = SeeleSpacing.statusDot

    /// Convenience init for simple online/offline state
    init(isOnline: Bool, size: CGFloat = SeeleSpacing.statusDot) {
        self.status = isOnline ? .online : .offline
        self.size = size
    }

    init(status: BuddyStatus, size: CGFloat = SeeleSpacing.statusDot) {
        self.status = status
        self.size = size
    }

    private var statusColor: Color {
        switch status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.textTertiary
        }
    }

    private var statusName: String {
        switch status {
        case .online: "Online"
        case .away: "Away"
        case .offline: "Offline"
        }
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: SeeleSpacing.animationFast), value: status)
            // Only the color shows this state, so the label speaks it.
            // Rows that put the status into a combined label replace or
            // hide this label.
            .accessibilityLabel(statusName)
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.md) {
        StandardStatusDot(status: .online)
        StandardStatusDot(status: .away)
        StandardStatusDot(status: .offline)
    }
    .padding()
    .background(SeeleColors.background)
}
