import SwiftUI
import AVFoundation

struct HistoryRow: View {
    @Environment(\.appState) private var appState
    let item: TransferHistoryItem
    @State private var isHovered = false
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Direction icon
            ZStack {
                Circle()
                    .fill((item.isDownload ? SeeleColors.info : SeeleColors.success).opacity(0.15))
                    .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)

                Image(systemName: item.isDownload ? "arrow.down" : "arrow.up")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(item.isDownload ? SeeleColors.info : SeeleColors.success)
            }

            // File info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(item.displayFilename)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SeeleSpacing.md) {
                    Label(item.username, systemImage: "person")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)

                    Text(item.formattedDate)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
                Text(item.formattedSize)
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textSecondary)

                HStack(spacing: SeeleSpacing.sm) {
                    Text(item.formattedSpeed)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text(item.formattedDuration)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            // Action buttons (visible on hover)
            HStack(spacing: SeeleSpacing.sm) {
                if item.isAudioFile && item.fileExists {
                    IconButton(icon: isPlaying ? "pause.fill" : "play.fill") {
                        toggleAudioPreview()
                    }

                    IconButton(icon: "tag") {
                        if let path = item.resolvedLocalPath {
                            appState.metadataState.showEditor(for: path)
                        }
                    }
                }

                if item.fileExists {
                    IconButton(icon: "folder") {
                        revealInFinder()
                    }
                }
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onDisappear {
            audioPlayer?.stop()
        }
        .contextMenu {
            if item.isAudioFile && item.fileExists {
                Button {
                    toggleAudioPreview()
                } label: {
                    Label(isPlaying ? "Stop Preview" : "Play Preview", systemImage: isPlaying ? "stop.fill" : "play.fill")
                }

                Button {
                    if let path = item.resolvedLocalPath {
                        appState.metadataState.showEditor(for: path)
                    }
                } label: {
                    Label("Edit Metadata", systemImage: "tag")
                }
            }

            if item.fileExists {
                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()
            }

            UserContextMenuItems(username: item.username)
        }
    }

    private func revealInFinder() {
        guard let path = item.resolvedLocalPath else { return }
        NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: path.deletingLastPathComponent().path)
    }

    private func toggleAudioPreview() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        } else {
            guard let path = item.resolvedLocalPath else { return }
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: path)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                isPlaying = true

                // Stop after 30 seconds preview
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak audioPlayer] in
                    audioPlayer?.stop()
                    isPlaying = false
                }
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }
}
