import SwiftUI

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
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? SeeleColors.accent : SeeleColors.textTertiary)
                    .frame(width: SeeleSpacing.iconSizeMedium)

                Text(tab.rawValue)
                    .font(SeeleTypography.body)
                    .foregroundStyle(selectedTab == tab ? SeeleColors.textPrimary : SeeleColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                selectedTab == tab
                    ? SeeleColors.selectionBackground
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(selectedTab == tab ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SeeleSpacing.xs)
    }
}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
