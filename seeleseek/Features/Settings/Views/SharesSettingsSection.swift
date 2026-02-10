import SwiftUI

struct SharesSettingsSection: View {
    @Bindable var settings: SettingsState
    @Environment(\.appState) private var appState

    private var shareManager: ShareManager {
        appState.networkClient.shareManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sectionSpacing) {
            settingsHeader("Shares")

            // Summary stats
            HStack(spacing: SeeleSpacing.md) {
                statItem(icon: "folder.fill", value: "\(shareManager.totalFolders)", label: "Folders", color: SeeleColors.warning)
                statItem(icon: "doc.fill", value: "\(shareManager.totalFiles)", label: "Files", color: SeeleColors.accent)
                statItem(icon: "externaldrive.fill", value: ByteFormatter.format(Int64(shareManager.totalSize)), label: "Size", color: SeeleColors.info)
                Spacer()
            }

            settingsGroup("Shared Folders") {
                if shareManager.sharedFolders.isEmpty {
                    settingsRow {
                        Text("No folders shared")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ForEach(shareManager.sharedFolders) { folder in
                    SharedFolderRow(folder: folder) {
                        shareManager.removeFolder(folder)
                    }
                }

                // Actions row
                settingsRow {
                    HStack {
                        Button {
                            showFolderPicker()
                        } label: {
                            HStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                                Text("Add Folder")
                            }
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if shareManager.isScanning {
                            HStack(spacing: SeeleSpacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Scanning \(Int(shareManager.scanProgress * 100))%")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        } else {
                            Button {
                                Task { await shareManager.rescanAll() }
                            } label: {
                                HStack(spacing: SeeleSpacing.xs) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: SeeleSpacing.iconSizeXS))
                                    Text("Rescan")
                                }
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            settingsGroup("Options") {
                settingsToggle("Rescan on startup", isOn: $settings.rescanOnStartup)
                settingsToggle("Share hidden files", isOn: $settings.shareHiddenFiles)
            }
        }
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(color)
            Text(value)
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
    }

    private func showFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to share"
        panel.prompt = "Share"

        if panel.runModal() == .OK {
            for url in panel.urls {
                shareManager.addFolder(url)
            }
        }
        #endif
    }
}

struct SharedFolderRow: View {
    let folder: ShareManager.SharedFolder
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(SeeleColors.warning)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(folder.displayName)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                Text(folder.path)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(folder.fileCount) files")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)

            Text(ByteFormatter.format(Int64(folder.totalSize)))
                .font(SeeleTypography.mono)
                .foregroundStyle(SeeleColors.textTertiary)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.error.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SeeleSpacing.rowHorizontal)
        .padding(.vertical, SeeleSpacing.rowVertical)
        .background(SeeleColors.surface)
    }
}

#Preview {
    ScrollView {
        SharesSettingsSection(settings: SettingsState())
            .padding()
    }
    .environment(\.appState, AppState())
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
