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

            SharesSummaryStats()

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

                settingsRow {
                    SharesScanControl()
                }
            }

            settingsGroup("Options") {
                settingsToggle("Rescan on startup", isOn: $settings.rescanOnStartup)
                settingsToggle("Share hidden files", isOn: $settings.shareHiddenFiles)
            }
        }
    }
}

struct SharedFolderRow: View {
    let folder: ShareManager.SharedFolder
    let onRemove: () -> Void
    let onVisibilityChange: (ShareManager.Visibility) -> Void

    // Cap the Picker width so its closed-state size doesn't depend on
    // the selected label ("Public" is narrower than "Buddies only") —
    // without this, switching a folder's visibility would shift the
    // remove button on that row.
    private static let visibilityColumnWidth: CGFloat = 112

    var body: some View {
        // Single-row layout with metadata (file count, size) demoted
        // into the subline alongside the path, matching the macOS
        // Settings pattern used in System Settings > Sharing and in
        // Finder's Get Info accessory rows. This frees enough
        // horizontal space for the visibility picker + remove button
        // to stay on screen even on narrow Settings detail panes.
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(SeeleColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(folder.displayName)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: SeeleSpacing.xs) {
                    Text(folder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(0)

                    Text("·")
                    Text("\(folder.fileCount) files")
                        .monospacedDigit()
                        .layoutPriority(1)

                    Text("·")
                    Text(folder.totalSize.formattedBytes)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            }
            // Let the path/metadata subline collapse to zero width
            // before the trailing controls get clipped.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(folder.displayName), \(folder.fileCount) files, \(folder.totalSize.formattedBytes)")

            visibilityPicker
                .frame(width: Self.visibilityColumnWidth, alignment: .trailing)
                .layoutPriority(2)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.error.opacity(0.8))
            }
            .buttonStyle(.plain)
            .layoutPriority(2)
            .accessibilityLabel("Stop sharing \(folder.displayName)")
            .help("Stop sharing this folder")
        }
        .padding(.horizontal, SeeleSpacing.rowHorizontal)
        .padding(.vertical, SeeleSpacing.rowVertical)
        .background(SeeleColors.surface)
    }

    /// Native pop-up button (Picker with `.menu` style) — matches the
    /// existing `settingsPicker` idiom in `SettingsComponents.swift` and
    /// is the macOS-native control for "pick one of N" inline per HIG.
    /// The row's closed state shows the current label + chevron from AppKit.
    private var visibilityPicker: some View {
        Picker(
            "Visibility",
            selection: Binding(
                get: { folder.visibility },
                set: { onVisibilityChange($0) }
            )
        ) {
            Text("Public")
                .tag(ShareManager.Visibility.public)
            Text("Buddies only")
                .tag(ShareManager.Visibility.buddies)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel("Visibility for \(folder.displayName)")
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
