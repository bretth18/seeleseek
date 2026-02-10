import SwiftUI

struct ChatSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
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

#Preview {
    ScrollView {
        ChatSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 300)
    .background(SeeleColors.background)
}
