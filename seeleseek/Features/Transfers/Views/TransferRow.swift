import SwiftUI
import AVFoundation
import SeeleseekCore

struct TransferRow: View {
    @Environment(\.appState) private var appState
    let transfer: Transfer
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    var onMoveToTop: (() -> Void)? = nil
    var onMoveToBottom: (() -> Void)? = nil

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
                    .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

                    // Edit metadata button
                    IconButton(icon: "tag") {
                        if let path = transfer.localPath {
                            appState.metadataState.showEditor(for: path)
                        }
                    }
                    .accessibilityLabel("Edit metadata")
                }

                // Reveal in Finder for completed downloads
                if transfer.status == .completed && transfer.localPath != nil {
                    IconButton(icon: "folder") {
                        revealInFinder()
                    }
                    .accessibilityLabel("Reveal in Finder")
                }

                if transfer.canCancel {
                    IconButton(icon: "xmark") {
                        onCancel()
                    }
                    .accessibilityLabel("Cancel transfer")
                }
                if transfer.canRetry {
                    IconButton(icon: "arrow.clockwise") {
                        onRetry()
                    }
                    .accessibilityLabel("Retry transfer")
                }
                if !transfer.isActive {
                    IconButton(icon: "trash") {
                        onRemove()
                    }
                    .accessibilityLabel("Remove transfer")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transferAccessibilityLabel)
        .contextMenu {
            if let onMoveToTop, let onMoveToBottom,
               transfer.status == .queued || transfer.status == .waiting {
                Button {
                    onMoveToTop()
                } label: {
                    Label("Move to Top", systemImage: "arrow.up.to.line")
                }

                Button {
                    onMoveToBottom()
                } label: {
                    Label("Move to Bottom", systemImage: "arrow.down.to.line")
                }

                Divider()
            }

            UserContextMenuItems(username: transfer.username)
        }
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    private var transferAccessibilityLabel: String {
        var parts = [transfer.displayFilename, "from \(transfer.username)", transfer.status.displayText]
        if transfer.status == .transferring {
            parts.append("\(Int(transfer.progress * 100))%")
            parts.append(transfer.formattedSpeed)
        } else if let error = transfer.error {
            parts.append(error)
        } else if let queuePosition = transfer.queuePosition {
            parts.append("queue position \(queuePosition)")
        }
        return parts.joined(separator: ", ")
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
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .animation(.easeInOut(duration: SeeleSpacing.animationFast), value: transfer.status)
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
