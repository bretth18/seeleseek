import SwiftUI
import Charts

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
