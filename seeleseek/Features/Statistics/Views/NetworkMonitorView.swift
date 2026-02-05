import SwiftUI
import Charts
import Combine

/// Comprehensive network monitoring dashboard - Nicotine+ inspired
struct NetworkMonitorView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: MonitorTab = .overview
    @State private var refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    enum MonitorTab: String, CaseIterable {
        case overview = "Overview"
        case peers = "Peers"
        case search = "Search"
        case transfers = "Transfers"

        var icon: String {
            switch self {
            case .overview: "gauge.with.dots.needle.bottom.50percent"
            case .peers: "person.2"
            case .search: "magnifyingglass"
            case .transfers: "arrow.up.arrow.down"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: SeeleSpacing.sm) {
                ForEach(MonitorTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
                Spacer()

                // Live stats badge
                LiveStatsBadge(
                    downloadSpeed: peerPool.currentDownloadSpeed,
                    uploadSpeed: peerPool.currentUploadSpeed,
                    peerCount: peerPool.activeConnections
                )
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.surface)

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Content
            ScrollView {
                switch selectedTab {
                case .overview:
                    NetworkOverviewTab()
                case .peers:
                    PeersTab()
                case .search:
                    SearchTab()
                case .transfers:
                    TransfersTab()
                }
            }
            .background(SeeleColors.background)
        }
        .onReceive(refreshTimer) { _ in
            // Force refresh
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 1, weight: isSelected ? .semibold : .regular))

                Text(title)
                    .font(SeeleTypography.body)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live Stats Badge

private struct LiveStatsBadge: View {
    let downloadSpeed: Double
    let uploadSpeed: Double
    let peerCount: Int

    var body: some View {
        HStack(spacing: SeeleSpacing.lg) {
            // Download
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.success)
                Text(ByteFormatter.formatSpeed(Int64(downloadSpeed)))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.success)
            }

            // Upload
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.up")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.accent)
                Text(ByteFormatter.formatSpeed(Int64(uploadSpeed)))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.accent)
            }

            // Peers
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.info)
                Text("\(peerCount)")
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.info)
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Overview Tab

private struct NetworkOverviewTab: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Top row - key metrics
            HStack(spacing: SeeleSpacing.lg) {
                MetricCard(
                    title: "Peers",
                    value: "\(peerPool.activeConnections)",
                    subtitle: "active connections",
                    icon: "person.2.fill",
                    color: SeeleColors.info
                )

                MetricCard(
                    title: "Downloaded",
                    value: ByteFormatter.format(Int64(peerPool.totalBytesReceived)),
                    subtitle: "this session",
                    icon: "arrow.down.circle.fill",
                    color: SeeleColors.success
                )

                MetricCard(
                    title: "Uploaded",
                    value: ByteFormatter.format(Int64(peerPool.totalBytesSent)),
                    subtitle: "this session",
                    icon: "arrow.up.circle.fill",
                    color: SeeleColors.accent
                )

                MetricCard(
                    title: "Shares",
                    value: "\(appState.networkClient.shareManager.totalFiles)",
                    subtitle: "\(appState.networkClient.shareManager.totalFolders) folders",
                    icon: "folder.fill",
                    color: SeeleColors.warning
                )
            }

            // Bandwidth chart
            BandwidthChartCard()

            // Bottom row
            HStack(spacing: SeeleSpacing.lg) {
                // Connection health
                ConnectionHealthCard()

                // Quick peers list
                QuickPeersCard()
            }

            // Activity feed
            LiveActivityFeed()
                .frame(maxHeight: 250)
        }
        .padding(SeeleSpacing.lg)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
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

// MARK: - Bandwidth Chart Card

private struct BandwidthChartCard: View {
    @Environment(\.appState) private var appState

    private var speedHistory: [PeerConnectionPool.SpeedSample] {
        appState.networkClient.peerConnectionPool.speedHistory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Bandwidth")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Chart {
                ForEach(speedHistory) { sample in
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Download", sample.downloadSpeed)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SeeleColors.success.opacity(0.4), SeeleColors.success.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Download", sample.downloadSpeed)
                    )
                    .foregroundStyle(SeeleColors.success)

                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Upload", sample.uploadSpeed)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SeeleColors.accent.opacity(0.4), SeeleColors.accent.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Upload", sample.uploadSpeed)
                    )
                    .foregroundStyle(SeeleColors.accent)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(ByteFormatter.formatSpeed(Int64(speed)))
                                .font(SeeleTypography.caption2)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 150)

            // Legend
            HStack(spacing: SeeleSpacing.lg) {
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(SeeleColors.success)
                        .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
                    Text("Download")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(SeeleColors.accent)
                        .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
                    Text("Upload")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

// MARK: - Connection Health Card

private struct ConnectionHealthCard: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    private var healthScore: Double {
        let active = Double(peerPool.activeConnections)
        let total = Double(max(peerPool.totalConnections, 1))
        return min(active / total, 1.0) * 100
    }

    private var healthColor: Color {
        if healthScore >= 70 {
            return SeeleColors.success
        } else if healthScore >= 40 {
            return SeeleColors.warning
        } else {
            return SeeleColors.error
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Connection Health")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            HStack(spacing: SeeleSpacing.xl) {
                // Health gauge
                ZStack {
                    Circle()
                        .stroke(SeeleColors.surfaceSecondary, lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: healthScore / 100)
                        .stroke(healthColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: healthScore)

                    VStack {
                        Text(String(format: "%.0f%%", healthScore))
                            .font(SeeleTypography.title2)
                            .foregroundStyle(SeeleColors.textPrimary)
                    }
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    HealthStatRow(
                        label: "Active",
                        value: "\(peerPool.activeConnections)",
                        color: SeeleColors.success
                    )
                    HealthStatRow(
                        label: "Total",
                        value: "\(peerPool.totalConnections)",
                        color: SeeleColors.textSecondary
                    )
                    HealthStatRow(
                        label: "Avg Duration",
                        value: formatDuration(peerPool.averageConnectionDuration),
                        color: SeeleColors.info
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}

private struct HealthStatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Spacer()
            Text(value)
                .font(SeeleTypography.mono)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Quick Peers Card

private struct QuickPeersCard: View {
    @Environment(\.appState) private var appState

    private var topPeers: [PeerConnectionPool.PeerConnectionInfo] {
        appState.networkClient.peerConnectionPool.topPeersByTraffic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Top Peers")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            if topPeers.isEmpty {
                Text("No peer activity")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SeeleSpacing.xl)
            } else {
                ForEach(topPeers.prefix(5)) { peer in
                    QuickPeerRow(peer: peer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

private struct QuickPeerRow: View {
    let peer: PeerConnectionPool.PeerConnectionInfo

    private var displayName: String {
        !peer.username.isEmpty && peer.username != "unknown" ? peer.username : peer.ip
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Circle()
                .fill(peer.state == .connected ? SeeleColors.success : SeeleColors.textTertiary)
                .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)

            Text(displayName)
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(ByteFormatter.format(Int64(peer.bytesReceived + peer.bytesSent)))
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}

// MARK: - Peers Tab

private struct PeersTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Network visualization
            PeerWorldMap()

            // Detailed peer list
            LivePeersView()
        }
        .padding(SeeleSpacing.lg)
    }
}

// MARK: - Search Tab

private struct SearchTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            SearchActivityView()
        }
        .padding(SeeleSpacing.lg)
    }
}

// MARK: - Transfers Tab

private struct TransfersTab: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Active transfers would go here
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Active Transfers")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text("No active transfers")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SeeleSpacing.xl)
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    NetworkMonitorView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 700)
}
