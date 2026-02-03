import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @State private var settingsState = SettingsState()
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case network = "Network"
        case shares = "Shares"
        case metadata = "Metadata"
        case chat = "Chat"
        case privacy = "Privacy"

        var icon: String {
            switch self {
            case .general: "gear"
            case .network: "network"
            case .shares: "folder"
            case .metadata: "music.note"
            case .chat: "bubble.left"
            case .privacy: "lock.shield"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Tab sidebar
            VStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    settingsTabButton(tab)
                }
                Spacer()
            }
            .frame(width: 180)
            .background(SeeleColors.surface)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsSection(settings: settingsState)
                    case .network:
                        NetworkSettingsSection(settings: settingsState)
                    case .shares:
                        SharesSettingsSection(settings: settingsState)
                    case .metadata:
                        MetadataSettingsSection(settings: settingsState)
                    case .chat:
                        ChatSettingsSection(settings: settingsState)
                    case .privacy:
                        PrivacySettingsSection(settings: settingsState)
                    }
                }
                .padding(SeeleSpacing.xl)
            }
            .background(SeeleColors.background)
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(SeeleTypography.subheadline)

                Spacer()
            }
            .foregroundStyle(selectedTab == tab ? SeeleColors.accent : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(selectedTab == tab ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Sections

struct GeneralSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("General")

            settingsGroup("Downloads") {
                folderPicker("Download Location", url: $settings.downloadLocation)
                folderPicker("Incomplete Files", url: $settings.incompleteLocation)
            }

            settingsGroup("Startup") {
                settingsToggle("Launch at login", isOn: $settings.launchAtLogin)
                settingsToggle("Show in menu bar", isOn: $settings.showInMenuBar)
            }
        }
    }
}

struct NetworkSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Network")

            settingsGroup("Connection") {
                settingsNumberField("Listen Port", value: $settings.listenPort, range: 1024...65535)
                settingsToggle("Enable UPnP", isOn: $settings.enableUPnP)
            }

            settingsGroup("Transfer Slots") {
                settingsStepper("Max Download Slots", value: $settings.maxDownloadSlots, range: 1...20)
                settingsStepper("Max Upload Slots", value: $settings.maxUploadSlots, range: 1...20)
            }

            settingsGroup("Speed Limits") {
                settingsNumberField("Upload Limit (KB/s)", value: $settings.uploadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
                settingsNumberField("Download Limit (KB/s)", value: $settings.downloadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
            }
        }
    }
}

struct SharesSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Shares")

            settingsGroup("Shared Folders") {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    ForEach(settings.sharedFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(SeeleColors.warning)

                            Text(folder.path)
                                .font(SeeleTypography.mono)
                                .foregroundStyle(SeeleColors.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                settings.removeSharedFolder(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(SeeleColors.error)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(SeeleSpacing.sm)
                        .background(SeeleColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
                    }

                    Button {
                        // Show folder picker
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Folder")
                        }
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, SeeleSpacing.sm)
                }
            }

            settingsGroup("Options") {
                settingsToggle("Rescan on startup", isOn: $settings.rescanOnStartup)
                settingsToggle("Share hidden files", isOn: $settings.shareHiddenFiles)
            }
        }
    }
}

struct MetadataSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Metadata")

            settingsGroup("Auto-fetch") {
                settingsToggle("Fetch metadata automatically", isOn: $settings.autoFetchMetadata)
                settingsToggle("Fetch album art", isOn: $settings.autoFetchAlbumArt)
                    .disabled(!settings.autoFetchMetadata)
                settingsToggle("Embed album art in files", isOn: $settings.embedAlbumArt)
                    .disabled(!settings.autoFetchAlbumArt)
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

struct ChatSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Chat")

            settingsGroup("Messages") {
                settingsToggle("Show join/leave messages", isOn: $settings.showJoinLeaveMessages)
            }

            settingsGroup("Notifications") {
                settingsToggle("Enable notifications", isOn: $settings.enableNotifications)
                settingsToggle("Play notification sound", isOn: $settings.notificationSound)
                    .disabled(!settings.enableNotifications)
            }
        }
    }
}

struct PrivacySettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Privacy")

            settingsGroup("Visibility") {
                settingsToggle("Show online status", isOn: $settings.showOnlineStatus)
                settingsToggle("Allow users to browse my files", isOn: $settings.allowBrowsing)
            }
        }
    }
}

// MARK: - Settings Components

private func settingsHeader(_ title: String) -> some View {
    Text(title)
        .font(SeeleTypography.title2)
        .foregroundStyle(SeeleColors.textPrimary)
}

private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: SeeleSpacing.md) {
        Text(title)
            .font(SeeleTypography.headline)
            .foregroundStyle(SeeleColors.textSecondary)

        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            content()
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
        .toggleStyle(SeeleToggleStyle())
        .font(SeeleTypography.body)
        .foregroundStyle(SeeleColors.textPrimary)
}

private func settingsNumberField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, placeholder: String = "") -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(SeeleTextFieldStyle())
            .frame(width: 100)
            .multilineTextAlignment(.trailing)
    }
}

private func settingsStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        Stepper("\(value.wrappedValue)", value: value, in: range)
            .labelsHidden()

        Text("\(value.wrappedValue)")
            .font(SeeleTypography.mono)
            .foregroundStyle(SeeleColors.textPrimary)
            .frame(width: 30)
    }
}

private func folderPicker(_ title: String, url: Binding<URL>) -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        Text(url.wrappedValue.lastPathComponent)
            .font(SeeleTypography.mono)
            .foregroundStyle(SeeleColors.textSecondary)
            .lineLimit(1)

        Button("Choose...") {
            // Show folder picker
        }
        .font(SeeleTypography.caption)
        .foregroundStyle(SeeleColors.accent)
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
