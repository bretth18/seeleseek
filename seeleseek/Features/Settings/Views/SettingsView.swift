import SwiftUI
import SeeleseekCore

struct SettingsView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        @Bindable var navigation = appState.navigation

        HSplitView {
            StandardTabBar(
                selection: $navigation.settingsTab,
                axis: .vertical,
                showsBackground: false,
                icon: { $0.icon }
            )
            .frame(width: 180)
            .background(SeeleColors.surface)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                    switch navigation.settingsTab {
                    case .profile:
                        UserProfileSettingsSection()
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
        .focusedSceneValue(\.tabCommands, .cycling($navigation.settingsTab))
    }

}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
