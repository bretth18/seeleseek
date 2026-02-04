import SwiftUI

struct SearchResultRow: View {
    @Environment(\.appState) private var appState
    let result: SearchResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // File type icon
            fileIcon

            // File info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(result.displayFilename)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SeeleSpacing.md) {
                    Label(result.username, systemImage: "person")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)

                    if !result.folderPath.isEmpty {
                        Text(result.folderPath)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Metadata badges
            HStack(spacing: SeeleSpacing.sm) {
                if let bitrate = result.formattedBitrate {
                    metadataBadge(bitrate, color: bitrateColor)
                }

                if let duration = result.formattedDuration {
                    metadataBadge(duration, color: SeeleColors.textTertiary)
                }

                metadataBadge(result.formattedSize, color: SeeleColors.textTertiary)

                // Queue/slot indicator
                if result.freeSlots {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SeeleColors.success)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 12))
                        Text("\(result.queueLength)")
                            .font(SeeleTypography.monoSmall)
                    }
                    .foregroundStyle(SeeleColors.warning)
                }
            }

            // Download button
            Button {
                downloadFile()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isHovered ? SeeleColors.accent : SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconColor.opacity(0.15))
                .frame(width: 36, height: 36)

            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        if result.isLossless {
            return "waveform"
        } else if result.isAudioFile {
            return "music.note"
        } else {
            return "doc"
        }
    }

    private var iconColor: Color {
        if result.isLossless {
            return SeeleColors.success
        } else if result.isAudioFile {
            return SeeleColors.accent
        } else {
            return SeeleColors.textTertiary
        }
    }

    private var bitrateColor: Color {
        guard let bitrate = result.bitrate else { return SeeleColors.textTertiary }
        if bitrate >= 320 || result.isLossless {
            return SeeleColors.success
        } else if bitrate >= 256 {
            return SeeleColors.info
        } else if bitrate >= 192 {
            return SeeleColors.warning
        } else {
            return SeeleColors.textTertiary
        }
    }

    private func metadataBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(color)
            .padding(.horizontal, SeeleSpacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func downloadFile() {
        print("Download: \(result.filename) from \(result.username)")
        appState.downloadManager.queueDownload(from: result)
    }
}

#Preview {
    VStack(spacing: 1) {
        SearchResultRow(result: SearchResult(
            username: "musiclover42",
            filename: "Music\\Albums\\Pink Floyd\\The Dark Side of the Moon\\03 - Time.flac",
            size: 45_000_000,
            bitrate: 1411,
            duration: 413,
            isVBR: false,
            freeSlots: true,
            uploadSpeed: 1_500_000,
            queueLength: 0
        ))

        SearchResultRow(result: SearchResult(
            username: "vinylcollector",
            filename: "Music\\MP3\\Pink Floyd - Time.mp3",
            size: 8_500_000,
            bitrate: 320,
            duration: 413,
            isVBR: false,
            freeSlots: false,
            uploadSpeed: 800_000,
            queueLength: 5
        ))

        SearchResultRow(result: SearchResult(
            username: "jazzfan",
            filename: "Downloads\\time.mp3",
            size: 4_200_000,
            bitrate: 128,
            duration: 413,
            isVBR: true,
            freeSlots: true,
            uploadSpeed: 256_000,
            queueLength: 0
        ))
    }
    .background(SeeleColors.background)
}
