import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(\.appState) private var appState
    @State private var statsState = StatisticsState()
    @State private var selectedTimeRange: TimeRange = .minute

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
                // Header with live stats
                liveStatsHeader

                // Speed chart
                speedChartSection

                // Connection metrics
                HStack(spacing: SeeleSpacing.lg) {
                    connectionMetricsCard
                    transferMetricsCard
                }

                // Network topology (live peer connections)
                if !peerPool.connections.isEmpty {
                    networkTopologySection
                }

                // Peer activity visualization
                peerActivitySection

                // Transfer history
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
            // Download speed
            SpeedGaugeView(
                title: "Download",
                currentSpeed: downloadSpeed,
                maxSpeed: maxSpeed,
                color: SeeleColors.success
            )

            // Upload speed
            SpeedGaugeView(
                title: "Upload",
                currentSpeed: uploadSpeed,
                maxSpeed: maxSpeed,
                color: SeeleColors.accent
            )

            Spacer()

            // Session totals
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
                .pickerStyle(.segmented)
                .frame(width: 150)
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
                // Active connections ring
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }

    // MARK: - Transfer Metrics

    private var transferMetricsCard: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Transfers")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            HStack(spacing: SeeleSpacing.xl) {
                // Transfer ratio visualization
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
                LazyVStack(spacing: 1) {
                    ForEach(combinedHistory.prefix(10)) { entry in
                        TransferHistoryRow(entry: entry)
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }

    private var combinedHistory: [StatisticsState.TransferHistoryEntry] {
        (statsState.downloadHistory + statsState.uploadHistory)
            .sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Supporting Views

struct SpeedGaugeView: View {
    let title: String
    let currentSpeed: Double
    let maxSpeed: Double
    let color: Color

    private var percentage: Double {
        min(currentSpeed / maxSpeed, 1.0)
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.xs) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(SeeleColors.surfaceSecondary, lineWidth: 8)
                    .rotationEffect(.degrees(135))

                // Progress arc
                Circle()
                    .trim(from: 0, to: percentage * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.5), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .animation(.easeInOut(duration: 0.3), value: percentage)

                // Speed text
                VStack(spacing: 0) {
                    Text(ByteFormatter.formatSpeed(Int64(currentSpeed)))
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                }
            }
            .frame(width: 100, height: 100)

            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}

struct SpeedChartView: View {
    let samples: [StatisticsState.SpeedSample]
    let timeRange: Int

    private var filteredSamples: [StatisticsState.SpeedSample] {
        let cutoff = Date().addingTimeInterval(-Double(timeRange))
        return samples.filter { $0.timestamp > cutoff }
    }

    var body: some View {
        Chart {
            ForEach(filteredSamples) { sample in
                // Download area
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Speed", sample.downloadSpeed)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [SeeleColors.success.opacity(0.3), SeeleColors.success.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Speed", sample.downloadSpeed)
                )
                .foregroundStyle(SeeleColors.success)
                .lineStyle(StrokeStyle(lineWidth: 2))

                // Upload area
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Speed", sample.uploadSpeed)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [SeeleColors.accent.opacity(0.3), SeeleColors.accent.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Speed", sample.uploadSpeed)
                )
                .foregroundStyle(SeeleColors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(SeeleColors.surfaceSecondary)
                AxisValueLabel()
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(SeeleColors.surfaceSecondary)
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        Text(ByteFormatter.formatSpeed(Int64(speed)))
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .trailing) {
            HStack(spacing: SeeleSpacing.md) {
                Label("Download", systemImage: "circle.fill")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)
                Label("Upload", systemImage: "circle.fill")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)
            }
        }
    }
}

struct ConnectionRingView: View {
    let active: Int
    let total: Int
    let maxDisplay: Int

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return min(Double(active) / Double(min(total, maxDisplay)), 1.0)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(SeeleColors.surfaceSecondary, lineWidth: 6)

            // Active ring
            Circle()
                .trim(from: 0, to: percentage)
                .stroke(
                    SeeleColors.success,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: percentage)

            // Center text
            VStack(spacing: 0) {
                Text("\(active)")
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
    }
}

struct TransferRatioView: View {
    let downloaded: Int
    let uploaded: Int

    private var total: Int { downloaded + uploaded }
    private var downloadRatio: Double {
        guard total > 0 else { return 0.5 }
        return Double(downloaded) / Double(total)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Download portion
                Circle()
                    .trim(from: 0, to: downloadRatio)
                    .stroke(SeeleColors.success, lineWidth: 8)
                    .rotationEffect(.degrees(-90))

                // Upload portion
                Circle()
                    .trim(from: downloadRatio, to: 1)
                    .stroke(SeeleColors.accent, lineWidth: 8)
                    .rotationEffect(.degrees(-90))

                // Center
                VStack(spacing: 0) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 20))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
        }
    }
}

struct PeerActivityHeatmap: View {
    let downloadHistory: [StatisticsState.TransferHistoryEntry]
    let uploadHistory: [StatisticsState.TransferHistoryEntry]

    private let buckets = 24 // One per hour

    private var activityData: [Int: (downloads: Int, uploads: Int)] {
        var data: [Int: (downloads: Int, uploads: Int)] = [:]

        for i in 0..<buckets {
            data[i] = (0, 0)
        }

        let calendar = Calendar.current

        for entry in downloadHistory {
            let hour = calendar.component(.hour, from: entry.timestamp)
            data[hour]?.downloads += 1
        }

        for entry in uploadHistory {
            let hour = calendar.component(.hour, from: entry.timestamp)
            data[hour]?.uploads += 1
        }

        return data
    }

    private var maxActivity: Int {
        activityData.values.map { $0.downloads + $0.uploads }.max() ?? 1
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<buckets, id: \.self) { hour in
                let data = activityData[hour] ?? (0, 0)
                let intensity = Double(data.downloads + data.uploads) / Double(max(maxActivity, 1))

                VStack(spacing: 2) {
                    // Download bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SeeleColors.success.opacity(0.3 + intensity * 0.7))
                        .frame(height: CGFloat(data.downloads) / CGFloat(max(maxActivity, 1)) * 40)

                    // Upload bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SeeleColors.accent.opacity(0.3 + intensity * 0.7))
                        .frame(height: CGFloat(data.uploads) / CGFloat(max(maxActivity, 1)) * 40)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)

                if hour % 6 == 0 {
                    Text("\(hour)")
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(width: 20)
                }
            }
        }
    }
}

struct StatRow: View {
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

struct TransferHistoryRow: View {
    let entry: StatisticsState.TransferHistoryEntry

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Direction indicator
            Image(systemName: entry.isDownload ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(entry.isDownload ? SeeleColors.success : SeeleColors.accent)
                .font(.system(size: 20))

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.filename.split(separator: "\\").last.map(String.init) ?? entry.filename)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                Text(entry.username)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.format(Int64(entry.size)))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(ByteFormatter.formatSpeed(Int64(entry.averageSpeed)))
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            // Time
            Text(formatTime(entry.timestamp))
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .frame(width: 50)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(SeeleColors.surfaceSecondary.opacity(0.5))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    StatisticsView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 800)
}
