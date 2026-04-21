import SwiftUI
import SeeleseekCore

struct NetworkOverviewTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            HStack(spacing: SeeleSpacing.lg) {
                ActivePeersMetricCard()
                DownloadedMetricCard()
                UploadedMetricCard()
                SharesMetricCard()
            }

            MonitorBandwidthChartCard()

            MonitorConnectionHealthCard()

            LiveActivityFeed()
                .frame(maxHeight: 250)
        }
        .padding(SeeleSpacing.lg)
    }
}

// MARK: - Self-observing metric cards

private struct ActivePeersMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Peers",
            value: "\(appState.networkClient.peerConnectionPool.activeConnections)",
            subtitle: "active connections",
            icon: "person.2.fill",
            color: SeeleColors.info
        )
    }
}

private struct DownloadedMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Downloaded",
            value: appState.networkClient.peerConnectionPool.totalBytesReceived.formattedBytes,
            subtitle: "this session",
            icon: "arrow.down.circle.fill",
            color: SeeleColors.success
        )
    }
}

private struct UploadedMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Uploaded",
            value: appState.networkClient.peerConnectionPool.totalBytesSent.formattedBytes,
            subtitle: "this session",
            icon: "arrow.up.circle.fill",
            color: SeeleColors.accent
        )
    }
}

private struct SharesMetricCard: View {
    @Environment(\.appState) private var appState

    var body: some View {
        MonitorMetricCard(
            title: "Shares",
            value: "\(appState.networkClient.shareManager.totalFiles)",
            subtitle: "\(appState.networkClient.shareManager.totalFolders) folders",
            icon: "folder.fill",
            color: SeeleColors.warning
        )
    }
}

// MARK: - Metric Card

struct MonitorMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Text(value)
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(subtitle)")
    }
}
