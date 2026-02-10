import SwiftUI

struct NetworkOverviewTab: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Top row - key metrics
            HStack(spacing: SeeleSpacing.lg) {
                MonitorMetricCard(
                    title: "Peers",
                    value: "\(peerPool.activeConnections)",
                    subtitle: "active connections",
                    icon: "person.2.fill",
                    color: SeeleColors.info
                )

                MonitorMetricCard(
                    title: "Downloaded",
                    value: ByteFormatter.format(Int64(peerPool.totalBytesReceived)),
                    subtitle: "this session",
                    icon: "arrow.down.circle.fill",
                    color: SeeleColors.success
                )

                MonitorMetricCard(
                    title: "Uploaded",
                    value: ByteFormatter.format(Int64(peerPool.totalBytesSent)),
                    subtitle: "this session",
                    icon: "arrow.up.circle.fill",
                    color: SeeleColors.accent
                )

                MonitorMetricCard(
                    title: "Shares",
                    value: "\(appState.networkClient.shareManager.totalFiles)",
                    subtitle: "\(appState.networkClient.shareManager.totalFolders) folders",
                    icon: "folder.fill",
                    color: SeeleColors.warning
                )
            }

            // Bandwidth chart
            MonitorBandwidthChartCard()

            // Bottom row
            HStack(spacing: SeeleSpacing.lg) {
                // Connection health
                MonitorConnectionHealthCard()

                // Quick peers list
                MonitorQuickPeersCard()
            }

            // Activity feed
            LiveActivityFeed()
                .frame(maxHeight: 250)
        }
        .padding(SeeleSpacing.lg)
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

            Text(subtitle)
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}
