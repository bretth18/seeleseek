import SwiftUI
import Charts
import SeeleseekCore

struct MonitorBandwidthChartCard: View {
    @Environment(\.appState) private var appState

    private var speedHistory: [PeerConnectionPool.SpeedSample] {
        appState.networkClient.monitor.speedHistory
    }

    var body: some View {
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Bandwidth")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

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
                // Swift Charts shows each mark as an element with a role
                // that macOS VoiceOver does not know ("Unknown role" in
                // the accessibility audit). Collapse the chart to one
                // labeled element that speaks the headline numbers.
                .accessibleChart(
                    label: "Bandwidth chart, last 2 minutes",
                    value: bandwidthSummary
                )

                HStack(spacing: SeeleSpacing.lg) {
                    legendItem(color: SeeleColors.success, label: "Download")
                    legendItem(color: SeeleColors.accent, label: "Upload")
                }
            }
        }
    }

    private var bandwidthSummary: String {
        guard let last = speedHistory.last else { return "No data" }
        let peakDownload = speedHistory.map(\.downloadSpeed).max() ?? 0
        let peakUpload = speedHistory.map(\.uploadSpeed).max() ?? 0
        return "Download \(last.downloadSpeed.formattedSpeed), upload \(last.uploadSpeed.formattedSpeed), "
            + "peak download \(peakDownload.formattedSpeed), peak upload \(peakUpload.formattedSpeed)"
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
