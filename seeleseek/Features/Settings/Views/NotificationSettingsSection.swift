import SwiftUI

struct NotificationSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Notifications")

            settingsGroup("General") {
                settingsToggle("Enable notifications", isOn: $settings.enableNotifications)
                settingsToggle("Play notification sound", isOn: $settings.notificationSound)
                    .disabled(!settings.enableNotifications)
                settingsToggle("Only when app is in background", isOn: $settings.notifyOnlyInBackground)
                    .disabled(!settings.enableNotifications)
            }

            settingsGroup("Notify me about") {
                settingsToggle("Download completed", isOn: $settings.notifyDownloads)
                    .disabled(!settings.enableNotifications)
                settingsToggle("Upload completed", isOn: $settings.notifyUploads)
                    .disabled(!settings.enableNotifications)
                settingsToggle("Private messages", isOn: $settings.notifyPrivateMessages)
                    .disabled(!settings.enableNotifications)
            }
        }
    }
}

#Preview {
    ScrollView {
        NotificationSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
