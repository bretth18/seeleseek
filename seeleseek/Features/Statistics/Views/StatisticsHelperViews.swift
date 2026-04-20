import SwiftUI
import SeeleseekCore

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
                Text(entry.size.formattedBytes)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(entry.averageSpeed.formattedSpeed)
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
        date.formatted(date: .omitted, time: .shortened)
    }
}
