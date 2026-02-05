import SwiftUI
import AVFoundation

struct TransfersView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: TransferTab = .downloads

    private var transferState: TransferState { appState.transferState }

    enum TransferTab: String, CaseIterable {
        case downloads = "Downloads"
        case uploads = "Uploads"
        case history = "History"

        var icon: String {
            switch self {
            case .downloads: "arrow.down.circle"
            case .uploads: "arrow.up.circle"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs and stats
            header

            Divider().background(SeeleColors.surfaceSecondary)

            // Tab content
            switch selectedTab {
            case .downloads:
                downloadsView
            case .uploads:
                uploadsView
            case .history:
                historyView
            }
        }
        .background(SeeleColors.background)
        .sheet(isPresented: Binding(
            get: { appState.metadataState.isEditorPresented },
            set: { appState.metadataState.isEditorPresented = $0 }
        )) {
            MetadataEditorSheet(state: appState.metadataState)
        }
    }

    private var header: some View {
        VStack(spacing: SeeleSpacing.md) {
            // Speed stats
            HStack(spacing: SeeleSpacing.xl) {
                speedStat(
                    icon: "arrow.down",
                    label: "Download",
                    speed: transferState.totalDownloadSpeed,
                    color: SeeleColors.info
                )

                speedStat(
                    icon: "arrow.up",
                    label: "Upload",
                    speed: transferState.totalUploadSpeed,
                    color: SeeleColors.success
                )

                Spacer()

                // Clear buttons
                if !transferState.completedDownloads.isEmpty || !transferState.failedDownloads.isEmpty {
                    Menu {
                        Button("Clear Completed") {
                            transferState.clearCompleted()
                        }
                        Button("Clear Failed") {
                            transferState.clearFailed()
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.top, SeeleSpacing.md)

            // Tab picker
            HStack(spacing: SeeleSpacing.sm) {
                ForEach(TransferTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.md)
        }
        .padding(.bottom, SeeleSpacing.sm)
        .background(SeeleColors.surface.opacity(0.5))
    }

    private func speedStat(icon: String, label: String, speed: Int64, color: Color) -> some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Text(ByteFormatter.formatSpeed(speed))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
    }

    private func tabButton(_ tab: TransferTab) -> some View {
        let isSelected = selectedTab == tab
        let count: Int
        switch tab {
        case .downloads: count = transferState.downloads.count
        case .uploads: count = transferState.uploads.count
        case .history: count = transferState.history.count
        }

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 1, weight: isSelected ? .semibold : .regular))

                Text(tab.rawValue)
                    .font(SeeleTypography.body)
                    .fontWeight(isSelected ? .medium : .regular)

                if count > 0 {
                    Text("\(count)")
                        .font(SeeleTypography.badgeText)
                        .foregroundStyle(isSelected ? SeeleColors.textOnAccent : SeeleColors.textSecondary)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(isSelected ? SeeleColors.accent : SeeleColors.surfaceElevated, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var downloadsView: some View {
        if transferState.downloads.isEmpty {
            emptyState(
                icon: "arrow.down.circle",
                title: "No Downloads",
                subtitle: "Search for files and download them here"
            )
        } else {
            transferList(transfers: transferState.downloads)
        }
    }

    @ViewBuilder
    private var uploadsView: some View {
        if transferState.uploads.isEmpty {
            emptyState(
                icon: "arrow.up.circle",
                title: "No Uploads",
                subtitle: "Share files to allow others to download from you"
            )
        } else {
            transferList(transfers: transferState.uploads)
        }
    }

    @ViewBuilder
    private var historyView: some View {
        if transferState.history.isEmpty {
            emptyState(
                icon: "clock.arrow.circlepath",
                title: "No History",
                subtitle: "Completed transfers will appear here"
            )
        } else {
            VStack(spacing: 0) {
                // Stats bar
                HStack(spacing: SeeleSpacing.xl) {
                    statItem(
                        icon: "arrow.down",
                        label: "Downloaded",
                        value: ByteFormatter.format(transferState.totalDownloaded),
                        color: SeeleColors.info
                    )
                    statItem(
                        icon: "arrow.up",
                        label: "Uploaded",
                        value: ByteFormatter.format(transferState.totalUploaded),
                        color: SeeleColors.success
                    )
                    Spacer()
                    Button {
                        transferState.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SeeleSpacing.lg)
                .padding(.vertical, SeeleSpacing.sm)
                .background(SeeleColors.surface.opacity(0.5))

                Divider().background(SeeleColors.surfaceSecondary)

                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(transferState.history) { item in
                            HistoryRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Text(value)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        StandardEmptyState(icon: icon, title: title, subtitle: subtitle)
    }

    private func transferList(transfers: [Transfer]) -> some View {
        ScrollView {
            LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                ForEach(transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        onCancel: { transferState.cancelTransfer(id: transfer.id) },
                        onRetry: {
                            // Reset transfer state and trigger actual retry via DownloadManager
                            transferState.retryTransfer(id: transfer.id)
                            if transfer.direction == .download {
                                appState.downloadManager.retryFailedDownload(transferId: transfer.id)
                            }
                        },
                        onRemove: { transferState.removeTransfer(id: transfer.id) }
                    )
                }
            }
        }
    }
}

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

struct HistoryRow: View {
    let item: TransferHistoryItem
    @State private var isHovered = false

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
}

#Preview {
    TransfersView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
