import SwiftUI
import SeeleseekCore

struct ChatSettingsSection: View {
    @Bindable var settings: SettingsState
    @State private var newRoom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Chat")

            settingsGroup("Messages") {
                settingsToggle("Show join/leave activity pane", isOn: $settings.showJoinLeaveMessages)
            }

            settingsGroup("Notifications") {
                settingsToggle("Enable notifications", isOn: $settings.enableNotifications)
                settingsToggle("Play notification sound", isOn: $settings.notificationSound)
                    .disabled(!settings.enableNotifications)
            }

            settingsGroup("Auto-join Rooms") {
                ForEach(settings.autoJoinRooms, id: \.self) { room in
                    settingsRow {
                        HStack(spacing: SeeleSpacing.md) {
                            Image(systemName: "number")
                                .font(.system(size: SeeleSpacing.iconSizeSmall))
                                .foregroundStyle(SeeleColors.textTertiary)
                                .accessibilityHidden(true)

                            Text(room)
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)

                            Spacer()

                            Button("Remove", role: .destructive) {
                                settings.autoJoinRooms.removeAll { $0 == room }
                            }
                            .buttonStyle(.seeleSecondary(.small))
                            .accessibilityLabel("Remove room \(room)")
                        }
                    }
                    Divider()
                }

                settingsRow {
                    HStack(spacing: SeeleSpacing.sm) {
                        TextField("Room name", text: $newRoom)
                            .textFieldStyle(SeeleTextFieldStyle())
                            .frame(maxWidth: 260)
                            .onSubmit(addRoom)

                        Button("Add", action: addRoom)
                            .buttonStyle(.seelePrimary(.small))
                            .disabled(trimmedNewRoom.isEmpty)

                        Spacer()
                    }
                }
                settingsCaption("Joined each time you connect. Rooms that don't exist yet are created.")
            }
        }
    }

    private var trimmedNewRoom: String {
        newRoom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addRoom() {
        let room = trimmedNewRoom
        guard !room.isEmpty else { return }
        if !settings.autoJoinRooms.contains(room) {
            settings.autoJoinRooms.append(room)
        }
        newRoom = ""
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ChatSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
#endif
