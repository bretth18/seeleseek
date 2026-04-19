import SwiftUI
#if os(macOS)
import AppKit
#endif
import SeeleseekCore

// MARK: - Variant A — Timeline

/// Date is promoted to the leftmost visual anchor as a stacked tag. Makes
/// the history list scannable by *when* the transfer happened, which is
/// the usual reason someone visits this view (e.g. "find what I downloaded
/// yesterday"). Everything else is a single muted meta line.
///
/// Layout:
///   ┌────┐  filename                                           43 MB
///   │Apr │  ⇣ user · Pink Floyd / Dark Side · 128 KB/s · 3m 12s
///   │18  │
///   └────┘
struct HistoryRowTimeline: View {
    let item: TransferHistoryItem
    var onReveal: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: SeeleSpacing.md) {
            dateTag
            info
            Spacer(minLength: SeeleSpacing.sm)
            Text(item.formattedSize)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textSecondary)
                .monospacedDigit()
            actions
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm + 1)
        .background(isHovered ? SeeleColors.surfaceSecondary : Color.clear)
        .contentShape(Rectangle())
        .opacity(item.fileExists ? 1 : 0.55)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: SeeleSpacing.animationFast)) { isHovered = hovering }
        }
    }

    private var dateTag: some View {
        VStack(spacing: 0) {
            Text(monthShort)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(SeeleColors.textSecondary)
            Text(dayOfMonth)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(SeeleColors.textPrimary)
                .monospacedDigit()
        }
        .frame(width: 38, height: 38)
        .background(
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusSM, style: .continuous)
                .fill(SeeleColors.surfaceSecondary)
        )
    }

    private var monthShort: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: item.timestamp).uppercased()
    }

    private var dayOfMonth: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: item.timestamp)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 0) {
                Image(systemName: item.isDownload ? "arrow.down" : "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.isDownload ? SeeleColors.info : SeeleColors.success)
                    .padding(.trailing, 4)

                Text(item.username).foregroundStyle(SeeleColors.textSecondary)

                sep; Text(item.formattedSpeed)
                    .font(SeeleTypography.monoXSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .monospacedDigit()

                sep; Text(item.formattedDuration)
                    .font(SeeleTypography.monoXSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .monospacedDigit()

                if !item.fileExists {
                    sep
                    Text("file missing")
                        .font(SeeleTypography.monoXSmall)
                        .foregroundStyle(SeeleColors.warning)
                }
            }
            .font(SeeleTypography.caption)
            .lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if item.fileExists {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SeeleColors.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isHovered ? 1 : 0.35)
    }

    private var sep: some View {
        Text(" · ").foregroundStyle(SeeleColors.textTertiary.opacity(0.6))
    }
}

// MARK: - Variant B — Stats-first

/// Demotes filename slightly to promote the stats that differentiate one
/// historical transfer from another: average throughput and wall-clock
/// duration. Good for the "how healthy are my transfers" kind of question,
/// e.g. when looking at upload history to understand peer behaviour.
///
/// Layout:
///   [⇣]  filename                 128 KB/s          3m 12s      43 MB
///        user · Pink Floyd / Dark Side                          4/18 19:42
struct HistoryRowStats: View {
    let item: TransferHistoryItem
    var onReveal: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: SeeleSpacing.md) {
            directionGlyph
            info
            Spacer(minLength: SeeleSpacing.sm)

            stat(value: item.formattedSpeed, label: "avg", tint: SeeleColors.info)
                .frame(width: 84, alignment: .trailing)

            stat(value: item.formattedDuration, label: "elapsed", tint: SeeleColors.textSecondary)
                .frame(width: 72, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(item.formattedSize)
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .monospacedDigit()
                Text(item.formattedDate)
                    .font(SeeleTypography.monoXSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .monospacedDigit()
            }
            .frame(minWidth: 110, alignment: .trailing)

            actions
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm + 2)
        .background(isHovered ? SeeleColors.surfaceSecondary : Color.clear)
        .contentShape(Rectangle())
        .opacity(item.fileExists ? 1 : 0.55)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: SeeleSpacing.animationFast)) { isHovered = hovering }
        }
    }

    private var directionGlyph: some View {
        ZStack {
            Circle()
                .fill((item.isDownload ? SeeleColors.info : SeeleColors.success).opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: item.isDownload ? "arrow.down" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(item.isDownload ? SeeleColors.info : SeeleColors.success)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 0) {
                Text(item.username).foregroundStyle(SeeleColors.textSecondary)
                if !item.fileExists {
                    sep
                    Text("file missing")
                        .font(SeeleTypography.monoXSmall)
                        .foregroundStyle(SeeleColors.warning)
                }
            }
            .font(SeeleTypography.caption)
            .lineLimit(1)
        }
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(SeeleColors.textTertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if item.fileExists {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SeeleColors.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isHovered ? 1 : 0.35)
    }

    private var sep: some View {
        Text(" · ").foregroundStyle(SeeleColors.textTertiary.opacity(0.6))
    }
}

// MARK: - Preview

#Preview("History rows — A: Timeline / B: Stats") {
    let samples: [TransferHistoryItem] = [
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date().addingTimeInterval(-3600 * 3),
            filename: "@@music\\Pink Floyd\\The Dark Side of the Moon\\03 - Time.flac",
            username: "musiclover42",
            size: 45_000_000,
            duration: 192,
            averageSpeed: 230_000,
            isDownload: true,
            localPath: URL(fileURLWithPath: "/tmp/placeholder.flac")
        ),
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date().addingTimeInterval(-86400 * 1 - 3200),
            filename: "@@rock\\Led Zeppelin\\IV\\01 - Black Dog.flac",
            username: "vinylcollector",
            size: 40_000_000,
            duration: 820,
            averageSpeed: 48_000,
            isDownload: true,
            localPath: nil
        ),
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date().addingTimeInterval(-86400 * 2),
            filename: "@@music\\Radiohead\\OK Computer\\06 - Karma Police.flac",
            username: "hifihead",
            size: 68_000_000,
            duration: 305,
            averageSpeed: 220_000,
            isDownload: true,
            localPath: URL(fileURLWithPath: "/tmp/placeholder2.flac")
        ),
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date().addingTimeInterval(-86400 * 5),
            filename: "@@shares\\my-mixtape.mp3",
            username: "stranger",
            size: 12_000_000,
            duration: 78,
            averageSpeed: 155_000,
            isDownload: false,
            localPath: URL(fileURLWithPath: "/tmp/placeholder3.mp3")
        ),
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date().addingTimeInterval(-86400 * 14),
            filename: "@@shares\\album.flac",
            username: "anon_peer",
            size: 280_000_000,
            duration: 1_840,
            averageSpeed: 150_000,
            isDownload: false,
            localPath: URL(fileURLWithPath: "/tmp/placeholder4.flac")
        ),
    ]

    return ScrollView {
        VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
            DesignVariantSection(title: "A — Timeline (date as left anchor)") {
                ForEach(samples) { item in
                    HistoryRowTimeline(item: item)
                    Divider().opacity(0.25)
                }
            }
            DesignVariantSection(title: "B — Stats-first (speed · duration · size promoted)") {
                ForEach(samples) { item in
                    HistoryRowStats(item: item)
                    Divider().opacity(0.25)
                }
            }
        }
        .padding(.vertical, SeeleSpacing.lg)
    }
    .frame(width: 900, height: 700)
    .background(SeeleColors.background)
    .previewAppState()
}
