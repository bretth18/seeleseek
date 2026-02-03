import SwiftUI

struct TransfersView: View {
    @Environment(\.appState) private var appState
    @State private var transferState = TransferState()
    @State private var selectedTab: TransferTab = .downloads

    enum TransferTab: String, CaseIterable {
        case downloads = "Downloads"
        case uploads = "Uploads"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs and stats
            header

            Divider().background(SeeleColors.surfaceSecondary)

            // Tab content
            if selectedTab == .downloads {
                downloadsView
            } else {
                uploadsView
            }
        }
        .background(SeeleColors.background)
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
            HStack(spacing: 0) {
                ForEach(TransferTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, SeeleSpacing.lg)
        }
        .padding(.bottom, SeeleSpacing.sm)
        .background(SeeleColors.surface.opacity(0.5))
    }

    private func speedStat(icon: String, label: String, speed: Int64, color: Color) -> some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
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
        let count = tab == .downloads ? transferState.downloads.count : transferState.uploads.count

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Text(tab.rawValue)
                    .font(SeeleTypography.headline)

                if count > 0 {
                    Text("\(count)")
                        .font(SeeleTypography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? SeeleColors.accent : SeeleColors.textTertiary.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.sm)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(SeeleColors.accent)
                    .frame(height: 2)
            }
        }
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

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text(title)
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text(subtitle)
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transferList(transfers: [Transfer]) -> some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        onCancel: { transferState.cancelTransfer(id: transfer.id) },
                        onRetry: { transferState.retryTransfer(id: transfer.id) },
                        onRemove: { transferState.removeTransfer(id: transfer.id) }
                    )
                }
            }
        }
    }
}

struct TransferRow: View {
    let transfer: Transfer
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

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
                    Label(transfer.username, systemImage: "person")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)

                    if transfer.status == .transferring {
                        Text(transfer.formattedSpeed)
                            .font(SeeleTypography.monoSmall)
                            .foregroundStyle(SeeleColors.accent)
                    } else if let queuePosition = transfer.queuePosition {
                        Text("Queue: \(queuePosition)")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.warning)
                    } else if let error = transfer.error {
                        Text(error)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.error)
                            .lineLimit(1)
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
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(transfer.statusColor.opacity(0.15))
                .frame(width: 32, height: 32)

            if transfer.status == .transferring {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .tint(transfer.statusColor)
            } else {
                Image(systemName: transfer.status.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(transfer.statusColor)
            }
        }
    }
}

#Preview {
    TransfersView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
