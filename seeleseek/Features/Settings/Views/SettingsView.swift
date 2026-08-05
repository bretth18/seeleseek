import SwiftUI
import SeeleseekCore

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case profile = "Profile"
        case general = "General"
        case network = "Network"
        case shares = "Shares"
        case metadata = "Metadata"
        case chat = "Chat"
        case notifications = "Notifications"
        case privacy = "Privacy"
        case diagnostics = "Diagnostics"
        case update = "Update"
        case about = "About"

        var icon: String {
            switch self {
            case .profile: "person.crop.circle"
            case .general: "gear"
            case .network: "network"
            case .shares: "folder"
            case .metadata: "music.note"
            case .chat: "bubble.left"
            case .notifications: "bell"
            case .privacy: "lock.shield"
            case .diagnostics: "ant"
            case .update: "arrow.triangle.2.circlepath"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HSplitView {
            StandardTabBar(
                selection: $selectedTab,
                axis: .vertical,
                showsBackground: false,
                icon: { $0.icon }
            )
            .frame(width: 180)
            .background(SeeleColors.surface)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                    switch selectedTab {
                    case .profile:
                        MyProfileView()
                    case .general:
                        GeneralSettingsSection(settings: appState.settings)
                    case .network:
                        NetworkSettingsSection(settings: appState.settings)
                    case .shares:
                        SharesSettingsSection(settings: appState.settings)
                    case .metadata:
                        MetadataSettingsSection(settings: appState.settings)
                    case .chat:
                        ChatSettingsSection(settings: appState.settings)
                    case .notifications:
                        NotificationSettingsSection(settings: appState.settings)
                    case .privacy:
                        PrivacySettingsSection(settings: appState.settings)
                    case .diagnostics:
                        DiagnosticsSection()
                    case .update:
                        UpdateSettingsSection(updateState: appState.updateState)
                    case .about:
                        AboutSettingsSection()
                    }

                }
                .padding(SeeleSpacing.lg)
            }
            .background(SeeleColors.background)
        }
        .focusedSceneValue(\.tabCommands, .cycling($selectedTab))
    }


}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
