import SwiftUI

@main
struct SeeleSeekApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.appState, appState)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
        }
        #endif

        #if os(macOS)
        Settings {
            Text("Settings")
                .frame(width: 400, height: 300)
        }
        #endif
    }
}
