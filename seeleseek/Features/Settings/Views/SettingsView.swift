import SwiftUI
import SeeleseekCore

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            StandardTabBar(
                selection: $selection,
                axis: .vertical,
                showsBackground: false,
                icon: { $0.icon }
            )
            .frame(width: 180)
            .background(SeeleColors.surface.ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(SeeleColors.border)
                    .frame(width: 1)
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                    switch selection {
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
                .transaction { $0.animation = nil }
            }
            .background(SeeleColors.background)
        }
        .focusedSceneValue(\.tabCommands, .cycling($selection))
    }

}

struct SettingsWindowView: View {
    @State private var selection = SettingsTab.general

    var body: some View {
        SettingsView(selection: $selection)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var selection = SettingsTab.general
    SettingsView(selection: $selection)
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
#endif
