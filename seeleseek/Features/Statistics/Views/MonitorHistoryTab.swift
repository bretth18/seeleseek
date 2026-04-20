import SwiftUI
import SeeleseekCore

struct MonitorHistoryTab: View {
    @Environment(\.appState) private var appState

    private var statsState: StatisticsState {
        appState.statisticsState
    }

    private var combinedHistory: [StatisticsState.TransferHistoryEntry] {
        (statsState.downloadHistory + statsState.uploadHistory)
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Session summary
            HStack(spacing: SeeleSpacing.lg) {
                MonitorMetricCard(
                    title: "Session",
                    value: statsState.formattedSessionDuration,
                    subtitle: "elapsed",
                    icon: "clock.fill",
                    color: SeeleColors.info
                )
                MonitorMetricCard(
                    title: "Downloads",
                    value: "\(statsState.filesDownloaded)",
                    subtitle: "files received",
                    icon: "arrow.down.circle.fill",
                    color: SeeleColors.success
                )
                MonitorMetricCard(
                    title: "Uploads",
                    value: "\(statsState.filesUploaded)",
                    subtitle: "files shared",
                    icon: "arrow.up.circle.fill",
                    color: SeeleColors.accent
                )
                MonitorMetricCard(
                    title: "Users",
                    value: "\(statsState.uniqueUsersDownloadedFrom.count + statsState.uniqueUsersUploadedTo.count)",
                    subtitle: "unique peers",
                    icon: "person.2.fill",
                    color: SeeleColors.warning
                )
            }

            // Peer activity heatmap
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Peer Activity")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                PeerActivityHeatmap(
                    downloadHistory: statsState.downloadHistory,
                    uploadHistory: statsState.uploadHistory
                )
                .frame(height: 100)
            }
            .padding(SeeleSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))

            // Recent transfers
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Recent Transfers")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                if combinedHistory.isEmpty {
                    Text("No transfers yet")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SeeleSpacing.xl)
                } else {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(combinedHistory.prefix(20)) { entry in
                            TransferHistoryRow(entry: entry)
                        }
                    }
                }
            }
            .padding(SeeleSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .padding(SeeleSpacing.lg)
    }
}
