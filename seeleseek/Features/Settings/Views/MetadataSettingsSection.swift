import SwiftUI

struct MetadataSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Metadata")

            settingsGroup("Auto-fetch") {
                settingsToggle("Fetch metadata automatically", isOn: $settings.autoFetchMetadata)
                settingsToggle("Fetch album art", isOn: $settings.autoFetchAlbumArt)
                    .disabled(!settings.autoFetchMetadata)
                settingsToggle("Embed album art in files", isOn: $settings.embedAlbumArt)
                    .disabled(!settings.autoFetchAlbumArt)
                settingsToggle("Set album art as folder icon", isOn: $settings.setFolderIcons)
            }

            settingsGroup("Organization") {
                settingsToggle("Organize downloads automatically", isOn: $settings.organizeDownloads)

                if settings.organizeDownloads {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                        Text("Pattern")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        TextField("", text: $settings.organizationPattern)
                            .textFieldStyle(SeeleTextFieldStyle())

                        Text("Available: {artist}, {album}, {track}, {title}, {year}")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        MetadataSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 300)
    .background(SeeleColors.background)
}
