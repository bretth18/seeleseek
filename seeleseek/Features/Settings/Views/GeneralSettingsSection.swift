import SwiftUI
import SeeleseekCore

struct GeneralSettingsSection: View {
    @Environment(\.appState) private var appState
    @Bindable var settings: SettingsState
    @State private var showNicotineImport = false

    /// Uses the manager's own resolver so the preview can't drift.
    private var folderStructurePreview: String {
        DownloadManager.resolveDownloadPath(
            soulseekPath: #"@@music\Daft Punk\Discovery\01 Track.mp3"#,
            username: "user123",
            template: settings.activeDownloadTemplate,
            metadata: AudioFileMetadata(artist: "Daft Punk", album: "Discovery")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("General")

            settingsGroup("Downloads") {
                folderPicker("Download Location", url: $settings.downloadLocation)
                folderPicker("Incomplete Files", url: $settings.incompleteLocation)

                settingsRow {
                    HStack {
                        Text("Folder Structure")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)
                            .accessibilityHidden(true)

                        Spacer()

                        Picker("", selection: $settings.downloadFolderFormat) {
                            ForEach(DownloadFolderFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityLabel("Folder Structure")
                    }
                }

                if settings.downloadFolderFormat == .custom {
                    settingsRow {
                        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                            Text("Template")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)
                                .accessibilityHidden(true)

                            TextField("{username}/{full-path}/{filename}", text: $settings.downloadFolderTemplate)
                                .textFieldStyle(SeeleTextFieldStyle())
                                .accessibilityLabel("Download folder template")

                            Text("Tokens: {username}, {folder}, {full-path}, {artist}, {album}, {filename}")
                                .font(SeeleTypography.caption2)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                }

                settingsCaption {
                    HStack(spacing: SeeleSpacing.xs) {
                        Image(systemName: "eye")
                            .font(.system(size: SeeleSpacing.iconSizeXS))
                            .foregroundStyle(SeeleColors.textTertiary)
                            .accessibilityHidden(true)
                        Text("Preview: ")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(folderStructurePreview)
                            .font(SeeleTypography.mono)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
                }
            }

            settingsGroup("Search") {
                settingsNumberField("Max Results", value: $settings.maxSearchResults, range: 0...10000, placeholder: "0 = Unlimited")
                settingsCaption("Stop collecting results after this limit. 0 = unlimited.")
                // Set via searchState so the live view recomputes; it
                // writes the setting back.
                settingsToggle("Group results by folder", isOn: Binding(
                    get: { settings.groupSearchResults },
                    set: { appState.searchState.isGrouped = $0 }
                ))
            }

            settingsGroup("Startup") {
                settingsToggle("Launch at login", isOn: $settings.launchAtLogin)
                settingsToggle("Show in menu bar", isOn: $settings.showInMenuBar)
                settingsToggle("Minimize to menu bar", isOn: $settings.minimizeToMenuBar)
                    .disabled(!settings.showInMenuBar)
            }

            settingsGroup("Import") {
                settingsRow {
                    HStack {
                        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                            Text("Migrate from Nicotine+")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)
                            Text("Login, ports, folders, shares, and ignore list")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }

                        Spacer()

                        Button("Import from Nicotine+…") {
                            showNicotineImport = true
                        }
                        .buttonStyle(.seeleSecondary(.small))
                    }
                }
            }
        }
        .sheet(isPresented: $showNicotineImport) {
            NicotineImportSheet(isPresented: $showNicotineImport)
        }
    }
}

#Preview {
    ScrollView {
        GeneralSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
