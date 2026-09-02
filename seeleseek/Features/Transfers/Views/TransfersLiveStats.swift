import SwiftUI
import SeeleseekCore

/// Speed / slot readout for the transfers tab bar, self-observing.
///
/// Deliberately its own view rather than inline in `TransfersView`:
/// `StandardTabBar` stores its `trailing` content as a built value, so a
/// closure written inline is evaluated during `TransfersView.body`. Reading
/// the speed counters there registered them as dependencies of the whole
/// view — and they tick about once a second, so every tick re-evaluated the
/// transfer list too (up to 200 `HistoryRow`s on the History tab, where
/// nothing else was changing). Same pattern as `MonitorLiveStatsBadge`.
struct TransfersLiveStats: View {
    @Environment(\.appState) private var appState

    private var transferState: TransferState { appState.transferState }
    private var uploads: UploadState { appState.uploadManager.state }

    var body: some View {
        StandardStatCluster {
            // Gate on upload activity only — a selectedTab condition here
            // reflows the cluster on every tab switch.
            if uploads.activeUploadCount > 0 || uploads.queueDepth > 0 {
                StandardLiveStat(
                    icon: "person.2.fill",
                    value: "\(uploads.slotsSummary) · \(uploads.queueDepth) queued",
                    accessibilityLabel: "Upload slots: \(uploads.slotsSummary), queue: \(uploads.queueDepth)"
                )
            }

            StandardLiveStat(
                icon: "arrow.down",
                value: transferState.totalDownloadSpeed.formattedSpeed,
                iconColor: SeeleColors.info,
                accessibilityLabel: "Download speed \(transferState.totalDownloadSpeed.formattedSpeed)"
            )
            StandardLiveStat(
                icon: "arrow.up",
                value: transferState.totalUploadSpeed.formattedSpeed,
                iconColor: SeeleColors.success,
                accessibilityLabel: "Upload speed \(transferState.totalUploadSpeed.formattedSpeed)"
            )
        }
    }
}
