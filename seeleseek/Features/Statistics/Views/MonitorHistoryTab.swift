import SwiftUI
import SeeleseekCore

struct MonitorHistoryTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            HStack(spacing: SeeleSpacing.lg) {
                SessionDurationMetricCard()
                FilesDownloadedMetricCard()
                FilesUploadedMetricCard()
                UniquePeersMetricCard()
            }

            PeerActivityHeatmapCard()

            RecentTransfersCard()
        }
        .padding(SeeleSpacing.lg)
    }
}

// MARK: - Self-observing metric cards

private struct SessionDurationMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            MonitorMetricCard(
                title: "Session",
                value: appState.statisticsState.formattedSessionDuration,
                subtitle: "elapsed",
                icon: "clock.fill",
                color: SeeleColors.info
            )
        }
    }
}

private struct FilesDownloadedMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Downloads",
            value: "\(appState.statisticsState.filesDownloaded)",
            subtitle: "files received",
            icon: "arrow.down.circle.fill",
            color: SeeleColors.success
        )
    }
}

private struct FilesUploadedMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Uploads",
            value: "\(appState.statisticsState.filesUploaded)",
            subtitle: "files shared",
            icon: "arrow.up.circle.fill",
            color: SeeleColors.accent
        )
    }
}

private struct UniquePeersMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        let stats = appState.statisticsState
        let count = stats.uniqueUsersDownloadedFrom.count + stats.uniqueUsersUploadedTo.count
        MonitorMetricCard(
            title: "Users",
            value: "\(count)",
            subtitle: "unique peers",
            icon: "person.2.fill",
            color: SeeleColors.warning
        )
    }
}

// MARK: - Activity heatmap

private struct PeerActivityHeatmapCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Peer Activity")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                PeerActivityHeatmap(
                    downloadHistory: appState.statisticsState.downloadHistory,
                    uploadHistory: appState.statisticsState.uploadHistory
                )
                .frame(height: 100)
                .accessibilityLabel("Peer activity heatmap, transfers grouped by hour of day")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Recent transfers

private struct RecentTransfersCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        // Compute once per body evaluation — previously a computed property
        // that was read in both the isEmpty check and the ForEach, causing
        // two concat+sort passes per render.
        let stats = appState.statisticsState
        let history = (stats.downloadHistory + stats.uploadHistory)
            .sorted { $0.timestamp > $1.timestamp }

        return StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Recent Transfers")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                if history.isEmpty {
                    StandardEmptyState(
                        icon: "arrow.up.arrow.down.circle",
                        title: "No Transfers Yet",
                        subtitle: "Completed downloads and uploads will appear here."
                    )
                    .frame(minHeight: 160)
                } else {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(history.prefix(20)) { entry in
                            TransferHistoryRow(entry: entry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
