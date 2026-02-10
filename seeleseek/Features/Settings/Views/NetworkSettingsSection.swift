import SwiftUI

struct NetworkSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
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

#Preview {
    ScrollView {
        NetworkSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
