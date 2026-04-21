import SwiftUI
import Charts
import SeeleseekCore

struct MonitorBandwidthChartCard: View {
    @Environment(\.appState) private var appState

    private var speedHistory: [PeerConnectionPool.SpeedSample] {
        appState.networkClient.peerConnectionPool.speedHistory
    }

    var body: some View {
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Bandwidth")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Chart {
                    ForEach(speedHistory) { sample in
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Download", sample.downloadSpeed),
                            series: .value("Direction", "Download")
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
                            y: .value("Download", sample.downloadSpeed),
                            series: .value("Direction", "Download")
                        )
                        .foregroundStyle(SeeleColors.success)

                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Upload", sample.uploadSpeed),
                            series: .value("Direction", "Upload")
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
                            y: .value("Upload", sample.uploadSpeed),
                            series: .value("Direction", "Upload")
                        )
                        .foregroundStyle(SeeleColors.accent)
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, position: .bottom) { value in
                        AxisGridLine().foregroundStyle(SeeleColors.surfaceSecondary.opacity(0.5))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(SeeleColors.surfaceSecondary.opacity(0.5))
                        AxisValueLabel {
                            if let speed = value.as(Double.self) {
                                Text(speed.formattedSpeed)
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("Bandwidth chart, last 2 minutes of download and upload speed")

                HStack(spacing: SeeleSpacing.lg) {
                    legendItem(color: SeeleColors.success, label: "Download")
                    legendItem(color: SeeleColors.accent, label: "Upload")
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}
