import SwiftUI

struct GeneralSettingsSection: View {
    @Bindable var settings: SettingsState

    private var folderStructurePreview: String {
        let template = settings.activeDownloadTemplate
        var result = template
            .replacingOccurrences(of: "{username}", with: "user123")
            .replacingOccurrences(of: "{folders}", with: "Daft Punk/Discovery")
            .replacingOccurrences(of: "{artist}", with: "Daft Punk")
            .replacingOccurrences(of: "{album}", with: "Discovery")
            .replacingOccurrences(of: "{filename}", with: "01 Track.mp3")
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return result.isEmpty ? "01 Track.mp3" : result
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

                        Spacer()

                        Picker("", selection: $settings.downloadFolderFormat) {
                            ForEach(DownloadFolderFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }

                if settings.downloadFolderFormat == .custom {
                    settingsRow {
                        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                            Text("Template")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)

                            TextField("{username}/{folders}/{filename}", text: $settings.downloadFolderTemplate)
                                .textFieldStyle(SeeleTextFieldStyle())

                            Text("Tokens: {username}, {folders}, {artist}, {album}, {filename}")
                                .font(SeeleTypography.caption2)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                }

                settingsRow {
                    HStack(spacing: SeeleSpacing.xs) {
                        Image(systemName: "eye")
                            .font(.system(size: SeeleSpacing.iconSizeXS))
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text("Preview: ")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(folderStructurePreview)
                            .font(SeeleTypography.mono)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            settingsGroup("Search") {
                settingsNumberField("Max Results", value: $settings.maxSearchResults, range: 0...10000, placeholder: "0 = Unlimited")
                settingsRow {
                    Text("Stop collecting results after this limit. 0 = unlimited.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            settingsGroup("Startup") {
                settingsToggle("Launch at login", isOn: $settings.launchAtLogin)
                settingsToggle("Show in menu bar", isOn: $settings.showInMenuBar)
            }
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
