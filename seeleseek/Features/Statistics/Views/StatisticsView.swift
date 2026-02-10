import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTimeRange: TimeRange = .minute

    private var statsState: StatisticsState {
        appState.statisticsState
    }

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    enum TimeRange: String, CaseIterable {
        case minute = "1m"
        case fiveMinutes = "5m"
        case hour = "1h"

        var seconds: Int {
            switch self {
            case .minute: return 60
            case .fiveMinutes: return 300
            case .hour: return 3600
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SeeleSpacing.xl) {
                liveStatsHeader
                speedChartSection
                HStack(spacing: SeeleSpacing.lg) {
                    connectionMetricsCard
                    transferMetricsCard
                }
                if !peerPool.connections.isEmpty {
                    networkTopologySection
                }
                peerActivitySection
                transferHistorySection
            }
            .padding(SeeleSpacing.xl)
        }
        .background(SeeleColors.background)
    }

    // MARK: - Live Stats Header

    private var liveStatsHeader: some View {
        let downloadSpeed = peerPool.currentDownloadSpeed
        let uploadSpeed = peerPool.currentUploadSpeed
        let maxSpeed = max(downloadSpeed, uploadSpeed, 1_000_000)
        let downloaded = peerPool.totalBytesReceived
        let uploaded = peerPool.totalBytesSent

        return HStack(spacing: SeeleSpacing.xl) {
            SpeedGaugeView(
                title: "Download",
                currentSpeed: downloadSpeed,
                maxSpeed: maxSpeed,
                color: SeeleColors.success
            )

            SpeedGaugeView(
                title: "Upload",
                currentSpeed: uploadSpeed,
                maxSpeed: maxSpeed,
                color: SeeleColors.accent
            )

            Spacer()

            VStack(alignment: .trailing, spacing: SeeleSpacing.sm) {
                Text("Session")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                HStack(spacing: SeeleSpacing.lg) {
                    VStack(alignment: .trailing) {
                        Text("↓ \(ByteFormatter.format(Int64(downloaded)))")
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.success)
                        Text("Downloaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }

                    VStack(alignment: .trailing) {
                        Text("↑ \(ByteFormatter.format(Int64(uploaded)))")
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.accent)
                        Text("Uploaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }

                Text(statsState.formattedSessionDuration)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Speed Chart

    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Bandwidth")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .font(SeeleTypography.caption2)
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            SpeedChartView(
                samples: peerPool.speedHistory.map { sample in
                    StatisticsState.SpeedSample(
                        timestamp: sample.timestamp,
                        downloadSpeed: sample.downloadSpeed,
                        uploadSpeed: sample.uploadSpeed
                    )
                },
                timeRange: selectedTimeRange.seconds
            )
            .frame(height: 200)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Connection Metrics

    private var connectionMetricsCard: some View {
        let activeConns = peerPool.activeConnections
        let totalConns = Int(peerPool.totalConnections)
        let successRate = totalConns > 0 ? Double(activeConns) / Double(totalConns) : 0

        return VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Connections")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            HStack(spacing: SeeleSpacing.xl) {
                ConnectionRingView(
                    active: activeConns,
                    total: max(totalConns, 1),
                    maxDisplay: 50
                )
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    StatRow(label: "Active", value: "\(activeConns)", color: SeeleColors.success)
                    StatRow(label: "Total", value: "\(totalConns)", color: SeeleColors.textSecondary)
                    StatRow(label: "Success Rate", value: String(format: "%.0f%%", successRate * 100), color: SeeleColors.info)
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Transfer Metrics

    private var transferMetricsCard: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Transfers")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            HStack(spacing: SeeleSpacing.xl) {
                TransferRatioView(
                    downloaded: statsState.filesDownloaded,
                    uploaded: statsState.filesUploaded
                )
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    StatRow(label: "Downloads", value: "\(statsState.filesDownloaded)", color: SeeleColors.success)
                    StatRow(label: "Uploads", value: "\(statsState.filesUploaded)", color: SeeleColors.accent)
                    StatRow(label: "Unique Users", value: "\(statsState.uniqueUsersDownloadedFrom.count + statsState.uniqueUsersUploadedTo.count)", color: SeeleColors.info)
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Network Topology

    private var networkTopologySection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Network Topology")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(peerPool.activeConnections) active")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            NetworkTopologyView(
                connections: Array(peerPool.connections.values),
                centerUsername: appState.connection.username ?? "You"
            )
            .frame(height: 300)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Peer Activity

    private var peerActivitySection: some View {
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
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    // MARK: - Transfer History

    private var transferHistorySection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Recent Transfers")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            if statsState.downloadHistory.isEmpty && statsState.uploadHistory.isEmpty {
                Text("No transfers yet")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(SeeleSpacing.xl)
            } else {
                LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                    ForEach(combinedHistory.prefix(10)) { entry in
                        TransferHistoryRow(entry: entry)
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private var combinedHistory: [StatisticsState.TransferHistoryEntry] {
        (statsState.downloadHistory + statsState.uploadHistory)
            .sorted { $0.timestamp > $1.timestamp }
    }
}

#Preview {
    StatisticsView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 800)
}
