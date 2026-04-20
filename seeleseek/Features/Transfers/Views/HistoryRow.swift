import SwiftUI
import SeeleseekCore

// MARK: - Layout anchors

/// Fixed widths so the same field lands at the same X coordinate on every
/// history row. Peer sub-cell sizing matches `SearchResultRow` and
/// `TransferRow` so rows across the app feel like one family.
enum HistoryRowLayout {
    static let peerUsernameWidth: CGFloat = 96
    static let peerCellWidth: CGFloat = 168
    static let speedColumnWidth: CGFloat = 84   // "999.9 KB/s"
    static let durationColumnWidth: CGFloat = 64 // "1h 23m"
    static let timestampStackWidth: CGFloat = 110 // size + "4/18/26, 7:42 PM"
}

// MARK: - Row

/// Stats-first history row. Each quantitative metric gets its own fixed
/// column so the eye can scan a single dimension (speed / duration /
/// size) down the list.
///
/// Layout:
///   [⇣]  filename                        128 KB/s    3:12     43 MB
///        ⇣ user                          avg         elapsed   4/18 19:42
struct HistoryRow: View {
    @Environment(\.appState) private var appState
    let item: TransferHistoryItem

    @State private var isHovered = false

    /// True only if the app-wide audio preview is currently playing
    /// *this row's* file. See `RowAudioPreview` — preview state lives on
    /// `AppState` so starting playback on another row flips this row's
    /// button back to "play".
    private var isPlayingPreview: Bool {
        guard let path = item.resolvedLocalPath else { return false }
        return appState.audioPreview.isPlaying(url: path)
    }

    var body: some View {
        StandardListRow(onHoverChanged: { isHovered = $0 }) {
            HStack(alignment: .top, spacing: SeeleSpacing.sm) {
                directionGlyph

                infoColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                statColumns

                actionCluster
            }
        }
        .opacity(item.fileExists ? 1 : SeeleColors.alphaHalf)
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            if item.isAudioFile, item.fileExists {
                Button(isPlayingPreview ? "Stop preview" : "Play preview", action: toggleAudioPreview)
                Button("Edit metadata", action: openMetadataEditor)
            }
            if item.fileExists {
                Button("Reveal in Finder", action: revealInFinder)
            }
        }
    }

    // MARK: - Direction glyph

    private var directionGlyph: some View {
        RowDirectionGlyph(
            direction: item.isDownload ? .download : .upload,
            tint: directionTint
        )
    }

    private var directionTint: Color {
        item.isDownload ? SeeleColors.info : SeeleColors.success
    }

    // MARK: - Info column

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(item.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)

            peerLine
        }
    }

    private var peerLine: some View {
        HStack(spacing: 0) {
            PeerUsernameLabel(
                iconName: item.isDownload ? "arrow.down" : "arrow.up",
                username: item.username,
                width: HistoryRowLayout.peerUsernameWidth
            )

            if !item.fileExists {
                HStack(spacing: SeeleSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeXS))
                    Text("File missing")
                        .font(SeeleTypography.monoSmall)
                }
                .foregroundStyle(SeeleColors.warning)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Stat columns

    private var statColumns: some View {
        HStack(spacing: SeeleSpacing.sm) {
            labelledStat(
                value: item.formattedSpeed,
                label: "avg",
                tint: SeeleColors.info,
                width: HistoryRowLayout.speedColumnWidth
            )

            labelledStat(
                value: item.formattedDuration,
                label: "elapsed",
                tint: SeeleColors.textSecondary,
                width: HistoryRowLayout.durationColumnWidth
            )

            VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
                Text(item.formattedSize)
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(item.formattedDate)
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: HistoryRowLayout.timestampStackWidth, alignment: .trailing)
        }
    }

    private func labelledStat(
        value: String,
        label: String,
        tint: Color,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
            Text(value)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)

            Text(label)
                .font(SeeleTypography.caption2)
                .tracking(SeeleSpacing.trackingWide)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(width: width, alignment: .trailing)
    }

    // MARK: - Action cluster
    //
    // Up to three hover-revealed icons: audio preview + metadata editor
    // (audio files that exist) and reveal-in-Finder (anything that
    // exists). Width is constant so the stat columns never shift on
    // hover.

    private static let secondaryActionCount: CGFloat = 3
    private var clusterWidth: CGFloat {
        SeeleSpacing.buttonHeight * Self.secondaryActionCount
            + SeeleSpacing.xxs * (Self.secondaryActionCount - 1)
    }

    private var actionCluster: some View {
        // Hit-testing stays on even at opacity 0 so Tab focus (and, via
        // `accessibilityAction` on the row, VoiceOver rotor) can reach
        // these actions. The invisible focus ring is an accepted tradeoff.
        HStack(spacing: SeeleSpacing.xxs) {
            if item.isAudioFile, item.fileExists {
                RowIconButton(
                    systemName: isPlayingPreview ? "pause.fill" : "play.fill",
                    help: isPlayingPreview ? "Pause preview" : "Play preview",
                    action: toggleAudioPreview
                )

                RowIconButton(
                    systemName: "tag",
                    help: "Edit metadata",
                    action: openMetadataEditor
                )
            }

            if item.fileExists {
                RowIconButton(
                    systemName: "folder",
                    help: "Reveal in Finder",
                    action: revealInFinder
                )
            }
        }
        .opacity(isHovered ? 1 : 0)
        .frame(width: clusterWidth, alignment: .trailing)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if item.isAudioFile, item.fileExists {
            Button(action: toggleAudioPreview) {
                Label(
                    isPlayingPreview ? "Stop Preview" : "Play Preview",
                    systemImage: isPlayingPreview ? "stop.fill" : "play.fill"
                )
            }
            Button(action: openMetadataEditor) {
                Label("Edit Metadata", systemImage: "tag")
            }
        }

        if item.fileExists {
            Button(action: revealInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Divider()
        }

        UserContextMenuItems(username: item.username)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = [item.displayFilename]
        parts.append(item.isDownload ? "downloaded from \(item.username)" : "uploaded to \(item.username)")
        parts.append(item.formattedSpeed + " average")
        parts.append(item.formattedDuration)
        parts.append(item.formattedSize)
        parts.append(item.formattedDate)
        if !item.fileExists { parts.append("file missing") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func revealInFinder() {
        guard let path = item.resolvedLocalPath else { return }
        FileReveal.inFinder(path)
    }

    private func openMetadataEditor() {
        guard let path = item.resolvedLocalPath else { return }
        appState.metadataState.showEditor(for: path)
    }

    private func toggleAudioPreview() {
        guard let path = item.resolvedLocalPath else { return }
        appState.audioPreview.toggle(url: path)
    }
}

// MARK: - Preview

#Preview("History rows") {
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
        LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
            ForEach(samples) { item in
                HistoryRow(item: item)
            }
        }
        .background(SeeleColors.background)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD))
        .padding(SeeleSpacing.lg)
    }
    .frame(width: 900, height: 520)
    .background(SeeleColors.background)
    .previewAppState()
}
