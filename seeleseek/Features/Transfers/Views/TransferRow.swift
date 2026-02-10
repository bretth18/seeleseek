import SwiftUI
import AVFoundation

struct TransferRow: View {
    @Environment(\.appState) private var appState
    let transfer: Transfer
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Status icon
            statusIcon

            // File info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(transfer.displayFilename)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SeeleSpacing.md) {
                    // Show folder path if available
                    if let folderPath = transfer.folderPath {
                        Text(folderPath)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .lineLimit(1)

                        Text("•")
                            .foregroundStyle(SeeleColors.textTertiary)
                    }

                    Label(transfer.username, systemImage: "person")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)

                    if transfer.status == .transferring {
                        Text(transfer.formattedSpeed)
                            .font(SeeleTypography.monoSmall)
                            .foregroundStyle(SeeleColors.accent)
                    } else if let error = transfer.error {
                        Text(error)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.error)
                            .lineLimit(1)
                    } else if let queuePosition = transfer.queuePosition {
                        Text("Queue: \(queuePosition)")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.warning)
                    } else if transfer.status != .completed {
                        Text(transfer.status.displayText)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(transfer.statusColor)
                    }
                }
            }

            Spacer()

            // Progress or size
            VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
                if transfer.status == .transferring || transfer.status == .completed {
                    Text(transfer.formattedProgress)
                        .font(SeeleTypography.monoSmall)
                        .foregroundStyle(SeeleColors.textSecondary)
                } else {
                    Text(ByteFormatter.format(Int64(transfer.size)))
                        .font(SeeleTypography.monoSmall)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

                if transfer.isActive {
                    ProgressIndicator(progress: transfer.progress)
                        .frame(width: 100)
                }
            }

            // Action buttons
            HStack(spacing: SeeleSpacing.sm) {
                // Audio preview for completed audio files
                if transfer.status == .completed && transfer.isAudioFile && transfer.localPath != nil {
                    IconButton(icon: isPlaying ? "pause.fill" : "play.fill") {
                        toggleAudioPreview()
                    }

                    // Edit metadata button
                    IconButton(icon: "tag") {
                        if let path = transfer.localPath {
                            appState.metadataState.showEditor(for: path)
                        }
                    }
                }

                // Reveal in Finder for completed downloads
                if transfer.status == .completed && transfer.localPath != nil {
                    IconButton(icon: "folder") {
                        revealInFinder()
                    }
                }

                if transfer.canCancel {
                    IconButton(icon: "xmark") {
                        onCancel()
                    }
                }
                if transfer.canRetry {
                    IconButton(icon: "arrow.clockwise") {
                        onRetry()
                    }
                }
                if !transfer.isActive {
                    IconButton(icon: "trash") {
                        onRemove()
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
        .contextMenu {
            UserContextMenuItems(username: transfer.username)
        }
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(transfer.statusColor.opacity(0.15))
                .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)

            if transfer.status == .transferring {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .tint(transfer.statusColor)
            } else {
                Image(systemName: transfer.status.icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(transfer.statusColor)
            }
        }
    }

    private func revealInFinder() {
        guard let path = transfer.localPath else { return }
        NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: path.deletingLastPathComponent().path)
    }

    private func toggleAudioPreview() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        } else {
            guard let path = transfer.localPath else { return }
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
