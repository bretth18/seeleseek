import SwiftUI

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
        HStack(spacing: SeeleSpacing.xxs) {
            ForEach(0..<buckets, id: \.self) { hour in
                let data = activityData[hour] ?? (0, 0)
                let intensity = Double(data.downloads + data.uploads) / Double(max(maxActivity, 1))

                VStack(spacing: SeeleSpacing.xxs) {
                    // Download bar
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                        .fill(SeeleColors.success.opacity(0.3 + intensity * 0.7))
                        .frame(height: CGFloat(data.downloads) / CGFloat(max(maxActivity, 1)) * 40)

                    // Upload bar
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
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
