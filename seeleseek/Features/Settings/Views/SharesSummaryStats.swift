import SwiftUI
import SeeleseekCore

/// Folder / file / size totals, self-observing.
///
/// Split out of `SharesSettingsSection` for the same reason as
/// `SharesScanControl`: `totalFiles` reads `fileIndex`, which the scan
/// replaces wholesale on completion. Reading it in the parent's body
/// rebuilt every folder row — and every row's pop-up button — along with
/// these three labels.
struct SharesSummaryStats: View {
    @Environment(\.appState) private var appState

    private var shares: ShareState {
        appState.networkClient.shareManager.state
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            SharesStatItem(
                icon: "folder.fill",
                value: "\(shares.totalFolders)",
                label: "Folders",
                color: SeeleColors.warning
            )
            SharesStatItem(
                icon: "doc.fill",
                value: "\(shares.totalFiles)",
                label: "Files",
                color: SeeleColors.accent
            )
            SharesStatItem(
                icon: "externaldrive.fill",
                value: shares.totalSize.formattedBytes,
                label: "Size",
                color: SeeleColors.info
            )
            Spacer()
        }
    }
}

struct SharesStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(color)
            Text(value)
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
