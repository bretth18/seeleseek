import SwiftUI
import SeeleseekCore

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
                statItem(icon: "externaldrive.fill", value: shareManager.totalSize.formattedBytes, label: "Size", color: SeeleColors.info)
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
                    SharedFolderRow(
                        folder: folder,
                        onRemove: { shareManager.removeFolder(folder) },
                        onVisibilityChange: { shareManager.setVisibility($0, forFolderWithID: folder.id) }
                    )
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
    let onVisibilityChange: (ShareManager.Visibility) -> Void

    // Fixed-width anchors so the three right-side columns (visibility,
    // file count, size) line up row-to-row regardless of which option
    // is selected or how many digits a value has. Without these the
    // native Picker's intrinsic width varies with selected label, and
    // variable-digit numbers shift the column's left edge per row.
    private static let visibilityColumnWidth: CGFloat = 130
    private static let fileCountColumnWidth: CGFloat = 64
    private static let sizeColumnWidth: CGFloat = 72

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

            visibilityPicker
                .frame(width: Self.visibilityColumnWidth, alignment: .trailing)

            Text("\(folder.fileCount) files")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
                .monospacedDigit()
                .frame(width: Self.fileCountColumnWidth, alignment: .trailing)

            Text(folder.totalSize.formattedBytes)
                .font(SeeleTypography.mono)
                .foregroundStyle(SeeleColors.textTertiary)
                .monospacedDigit()
                .frame(width: Self.sizeColumnWidth, alignment: .trailing)

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

    /// Native pop-up button (Picker with `.menu` style) — matches the
    /// existing `settingsPicker` idiom in `SettingsComponents.swift` and
    /// is the macOS-native control for "pick one of N" inline per HIG.
    /// Labels carry SF Symbols so the dropdown is skimmable; the row's
    /// closed state shows the current label + chevron from AppKit.
    private var visibilityPicker: some View {
        Picker(
            "Visibility",
            selection: Binding(
                get: { folder.visibility },
                set: onVisibilityChange
            )
        ) {
            Label("Public", systemImage: "globe")
                .tag(ShareManager.Visibility.public)
            Label("Buddies only", systemImage: "lock.fill")
                .tag(ShareManager.Visibility.buddies)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .help("Buddies-only folders are sent in the Soulseek protocol's private section, only to peers on your buddy list. Honor-system — not cryptographically enforced.")
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
