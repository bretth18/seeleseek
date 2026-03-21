import AppIntents

struct SeeleSeekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetConnectionStatusIntent(),
            phrases: [
                "Get \(.applicationName) connection status",
                "Am I connected to \(.applicationName)?"
            ],
            shortTitle: "Connection Status",
            systemImageName: "network"
        )

        AppShortcut(
            intent: SearchFilesIntent(),
            phrases: [
                "Search for files on \(.applicationName)",
                "Find files on \(.applicationName)"
            ],
            shortTitle: "Search Files",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: CheckUserStatusIntent(),
            phrases: [
                "Check user status on \(.applicationName)",
                "Is a user online on \(.applicationName)?"
            ],
            shortTitle: "Check User Status",
            systemImageName: "person.crop.circle"
        )

        AppShortcut(
            intent: SendRoomMessageIntent(),
            phrases: [
                "Send a room message on \(.applicationName)"
            ],
            shortTitle: "Send Room Message",
            systemImageName: "bubble.left"
        )

        AppShortcut(
            intent: SendPrivateMessageIntent(),
            phrases: [
                "Send a private message on \(.applicationName)"
            ],
            shortTitle: "Send Private Message",
            systemImageName: "envelope"
        )
    }
}
