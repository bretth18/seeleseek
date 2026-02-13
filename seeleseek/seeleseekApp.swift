import SwiftUI

@main
struct SeeleSeekApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.appState, appState)
                .tint(SeeleColors.accent)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task { await appState.updateState.checkForUpdate() }
                }
            }
            CommandMenu("Connection") {
                Button("Connect...") {
                    // Show login if disconnected
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Disconnect") {
                    appState.networkClient.disconnect()
                    appState.connection.setDisconnected()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(appState.connection.connectionStatus != .connected)
            }
            CommandMenu("Navigate") {
                Button("Search") {
                    appState.sidebarSelection = .search
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Wishlists") {
                    appState.sidebarSelection = .wishlists
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Transfers") {
                    appState.sidebarSelection = .transfers
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Browse") {
                    appState.sidebarSelection = .browse
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Social") {
                    appState.sidebarSelection = .social
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Chat") {
                    appState.sidebarSelection = .chat
                }
                .keyboardShortcut("6", modifiers: .command)

                Divider()

                Button("Statistics") {
                    appState.sidebarSelection = .statistics
                }
                .keyboardShortcut("7", modifiers: .command)

                Button("Network Monitor") {
                    appState.sidebarSelection = .networkMonitor
                }
                .keyboardShortcut("8", modifiers: .command)

                Divider()

                Button("Settings") {
                    appState.sidebarSelection = .settings
                }
                .keyboardShortcut("9", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.appState, appState)
                .frame(minWidth: 700, minHeight: 500)
        }

        MenuBarExtra("SeeleSeek", systemImage: "music.note", isInserted: $appState.settings.showInMenuBar) {
            MenuBarView()
                .environment(\.appState, appState)
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}
