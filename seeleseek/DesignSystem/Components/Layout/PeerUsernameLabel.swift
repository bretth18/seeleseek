import SwiftUI
import SeeleseekCore

/// Fixed-width username sub-cell with a leading arrow glyph. Used in the
/// peer cell of every list row (SearchResultRow, TransferRow, HistoryRow)
/// so the peer's name lands at the same X on every row and anything
/// rendered *after* the sub-cell (peer speed, folder, error, retry count,
/// file-missing warning) lines up across rows too.
///
/// When `peerStatus` is non-nil a small badge dot sits at the arrow's
/// bottom-trailing corner (online → success, away → warning, offline →
/// tertiary). Overlaying the dot costs no horizontal space, so the 96pt
/// sub-cell still holds the full username width — important for
/// cross-row alignment.
struct PeerUsernameLabel: View {
    let iconName: String
    let username: String
    let width: CGFloat
    var peerStatus: BuddyStatus? = nil

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: iconName)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                .foregroundStyle(SeeleColors.textTertiary)
                .accessibilityHidden(true)
                .overlay(alignment: .bottomTrailing) {
                    if let peerStatus {
                        Circle()
                            .fill(statusColor(for: peerStatus))
                            .frame(
                                width: SeeleSpacing.statusDotSmall,
                                height: SeeleSpacing.statusDotSmall
                            )
                            .overlay(
                                Circle()
                                    .stroke(SeeleColors.surface, lineWidth: SeeleSpacing.strokeThin)
                            )
                            .offset(x: SeeleSpacing.xxs, y: SeeleSpacing.xxs)
                            .accessibilityLabel(peerStatus.accessibilityLabel)
                    }
                }

            Text(username)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: width, alignment: .leading)
    }

    private func statusColor(for status: BuddyStatus) -> Color {
        switch status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.error
        }
    }
}

private extension BuddyStatus {
    var accessibilityLabel: String {
        switch self {
        case .online: "online"
        case .away: "away"
        case .offline: "offline"
        }
    }
}
