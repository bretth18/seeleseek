import SwiftUI
import SeeleseekCore

/// Left (flex) column of a search row: filename over the peer/folder
/// context line. The ignore list is read here, not in the row, so an
/// ignore-list change re-evaluates this column and not the row's layout.
struct SearchResultInfoColumn: View {
    @Environment(\.appState) private var appState
    let result: SearchResult
    let isNestedInGroup: Bool
    let peerStatus: BuddyStatus?

    var body: some View {
        let isIgnored = appState.socialState.isIgnored(result.username)
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(result.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(isIgnored ? SeeleColors.textTertiary : SeeleColors.textPrimary)
                .strikethrough(isIgnored, color: SeeleColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !isNestedInGroup {
                contextLine
            }
        }
    }

    private var contextLine: some View {
        HStack(spacing: 0) {
            peerCell
                .frame(width: RowLayout.peerCellWidth, alignment: .leading)

            if !result.folderPath.isEmpty {
                FolderPathLabel(
                    FolderPathLabel.compact(result.folderPath),
                    help: result.folderPath.replacingOccurrences(of: "\\", with: "/")
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var peerCell: some View {
        HStack(spacing: 0) {
            // Username sub-cell — fixed width so peer speed lands at the
            // same X on every row.
            PeerUsernameLabel(
                iconName: "arrow.up",
                username: result.username,
                width: RowLayout.peerUsernameWidth,
                peerStatus: peerStatus
            )

            Text(peerSpeedText)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(peerSpeedColor)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    /// Peer's reported upload speed. In SoulSeek this is the rate at which
    /// *they* serve files, which is usually more predictive of download
    /// time than the file size alone.
    private var peerSpeedText: String {
        result.uploadSpeed > 0 ? result.uploadSpeed.formattedSpeed : "unknown"
    }

    /// Tinted by peer quality tier.
    ///   ≥ 1 MB/s: success (fast peer)
    ///   ≥ 200 KB/s: info (decent peer)
    ///   < 200 KB/s: warning (slow peer)
    ///   unknown: tertiary (no signal)
    private var peerSpeedColor: Color {
        let bps = result.uploadSpeed
        if bps == 0 { return SeeleColors.textTertiary }
        if bps >= 1_000_000 { return SeeleColors.success }
        if bps >= 200_000 { return SeeleColors.info }
        return SeeleColors.warning
    }
}
