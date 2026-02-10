import SwiftUI
import Charts

struct MonitorBandwidthChartCard: View {
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
