import SwiftUI

/// Consistent status indicator dot
struct StandardStatusDot: View {
    let status: BuddyStatus
    var size: CGFloat = SeeleSpacing.statusDot

    private var statusColor: Color {
        switch status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.textTertiary
        }
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
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
