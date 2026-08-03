import SwiftUI
import SeeleseekCore

struct TransfersView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: TransferTab = .downloads
    @State private var isDashboardPresented = false
    @State private var isClearHistoryConfirmationPresented = false

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
            tabBar

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
        .focusedSceneValue(\.tabCommands, .cycling($selectedTab))
        .sheet(isPresented: Bindable(appState.metadataState).isEditorPresented) {
            MetadataEditorSheet(state: appState.metadataState)
        }
        .sheet(isPresented: $isDashboardPresented) {
            QueueDashboardSheet()
        }
        .confirmationDialog(
            "Clear all transfer history?",
            isPresented: $isClearHistoryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                transferState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all completed-transfer records and totals. This cannot be undone.")
        }
    }

    private var tabBar: some View {
        StandardTabBar(
            selection: $selectedTab,
            icon: { $0.icon },
            badge: { tab in
                switch tab {
                case .downloads: transferState.downloads.count
                case .uploads: transferState.uploads.count
                case .history: transferState.history.count
                }
            }
        ) {
            StandardStatCluster {
                // Gate on upload activity only — a selectedTab condition
                // here reflows the cluster on every tab switch.
                if appState.uploadManager.activeUploadCount > 0 || appState.uploadManager.queueDepth > 0 {
                    uploadQueueStat
                }

                StandardLiveStat(
                    icon: "arrow.down",
                    value: transferState.totalDownloadSpeed.formattedSpeed,
                    iconColor: SeeleColors.info,
                    accessibilityLabel: "Download speed \(transferState.totalDownloadSpeed.formattedSpeed)"
                )
                StandardLiveStat(
                    icon: "arrow.up",
                    value: transferState.totalUploadSpeed.formattedSpeed,
                    iconColor: SeeleColors.success,
                    accessibilityLabel: "Upload speed \(transferState.totalUploadSpeed.formattedSpeed)"
                )
            }

            IconButton(icon: "chart.bar.xaxis", label: "Open queue dashboard") {
                isDashboardPresented = true
            }

            clearMenu
        }
    }

    private var hasClearableTransfers: Bool {
        !transferState.completedDownloads.isEmpty || !transferState.failedDownloads.isEmpty
    }

    /// Always present so the trailing cluster never reflows; disabled
    /// (not hidden) when there is nothing to clear.
    private var clearMenu: some View {
        Menu {
            Button("Clear Completed") {
                transferState.clearCompleted()
            }
            Button("Clear Failed") {
                transferState.clearFailed()
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                .foregroundStyle(hasClearableTransfers ? SeeleColors.textSecondary : SeeleColors.textTertiary)
                .frame(
                    width: SeeleSpacing.iconSize + SeeleSpacing.lg,
                    height: SeeleSpacing.iconSize + SeeleSpacing.lg
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!hasClearableTransfers)
        .help("Clear finished transfers")
        .accessibilityLabel("Clear finished transfers")
    }

    private var uploadQueueStat: some View {
        StandardLiveStat(
            icon: "person.2.fill",
            value: "\(appState.uploadManager.slotsSummary) · \(appState.uploadManager.queueDepth) queued",
            accessibilityLabel: "Upload slots: \(appState.uploadManager.slotsSummary), queue: \(appState.uploadManager.queueDepth)"
        )
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
            transferList(
                transfers: transferState.downloads,
                onMoveToTop: { transferState.moveDownloadToTop(id: $0) },
                onMoveToBottom: { transferState.moveDownloadToBottom(id: $0) }
            )
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
                        value: transferState.totalDownloaded.formattedBytes,
                        iconColor: SeeleColors.info
                    )
                    statItem(
                        icon: "arrow.up",
                        label: "Uploaded",
                        value: transferState.totalUploaded.formattedBytes,
                        iconColor: SeeleColors.success
                    )
                    Spacer()
                    Button {
                        isClearHistoryConfirmationPresented = true
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

    private func statItem(icon: String, label: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Text(value)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityAddTraits(.isStaticText)
    }

    private func transferList(
        transfers: [Transfer],
        onMoveToTop: ((UUID) -> Void)? = nil,
        onMoveToBottom: ((UUID) -> Void)? = nil
    ) -> some View {
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
                            } else {
                                appState.uploadManager.retryFailedUpload(transferId: transfer.id)
                            }
                        },
                        onRemove: { transferState.removeTransfer(id: transfer.id) },
                        onMoveToTop: onMoveToTop.map { cb in { cb(transfer.id) } },
                        onMoveToBottom: onMoveToBottom.map { cb in { cb(transfer.id) } }
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
