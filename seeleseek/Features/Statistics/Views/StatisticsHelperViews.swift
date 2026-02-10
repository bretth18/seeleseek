import SwiftUI

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
                .font(.system(size: SeeleSpacing.iconSizeMedium))

            // File info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
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
            VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
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
