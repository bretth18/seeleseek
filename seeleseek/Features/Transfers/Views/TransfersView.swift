import SwiftUI

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
            header

            Divider().background(SeeleColors.surfaceSecondary)

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

                if selectedTab == .uploads || appState.uploadManager.activeUploadCount > 0 || appState.uploadManager.queueDepth > 0 {
                    uploadQueueStat
                }

                Spacer()

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

    private var uploadQueueStat: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: "person.2.fill")
                .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .bold))
                .foregroundStyle(SeeleColors.success)

            VStack(alignment: .leading, spacing: 0) {
                Text("Slots")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Text("\(appState.uploadManager.slotsSummary) · Queue: \(appState.uploadManager.queueDepth)")
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
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
            StandardEmptyState(
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
            StandardEmptyState(
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
            StandardEmptyState(
                icon: "clock.arrow.circlepath",
                title: "No History",
                subtitle: "Completed transfers will appear here"
            )
        } else {
            VStack(spacing: 0) {
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

    private func transferList(transfers: [Transfer]) -> some View {
        ScrollView {
            LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                ForEach(transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        onCancel: { transferState.cancelTransfer(id: transfer.id) },
                        onRetry: {
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

#Preview {
    TransfersView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
