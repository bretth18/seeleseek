import SwiftUI
import AppIntents
import SeeleseekCore

@main
struct SeeleSeekApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        if !Self.isRunningInPreview {
            AppDependencyManager.shared.add(dependency: state)
        }
    }

    private static var isRunningInPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }

    /// True when this process hosts the unit-test bundle. The app must stay
    /// inert then — no database load, no update check, and no login UI that
    /// a stray click could connect to the real server with saved
    /// credentials. Tests construct their own instances. UI tests are
    /// unaffected: they launch the app as a separate process without XCTest
    /// injected.
    nonisolated static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(TestHostSafeAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                Text("seeleseek test host — closing this window is fine")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(width: 360, height: 120)
            } else {
                MainView()
                    .environment(\.appState, appState)
                    .tint(SeeleColors.accent)
                    .task {
                        if Self.isRunningInPreview { return }
                        #if DEBUG
                        if DemoDataSeeder.isEnabled {
                            DemoDataSeeder.seed(into: appState)
                            return
                        }
                        #endif
                        appState.configure()
                        SeeleSeekShortcuts.updateAppShortcutParameters()
                    }
            }
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

                Button("Activity") {
                    appState.sidebarSelection = .networkMonitor
                }
                .keyboardShortcut("7", modifiers: .command)

                Divider()

                Button("Settings") {
                    appState.sidebarSelection = .settings
                }
                .keyboardShortcut("9", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Window("Update Available", id: "update-prompt") {
            UpdatePromptSheet(updateState: appState.updateState)
                .environment(\.appState, appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(\.appState, appState)
                .frame(minWidth: 700, minHeight: 500)
        }

        MenuBarExtra("SeeleSeek", image: .gsgaag2Menubar2, isInserted: $appState.settings.showInMenuBar) {
            MenuBarView()
                .environment(\.appState, appState)
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}

#if os(macOS)
/// Closing the last window normally quits a SwiftUI macOS app. When the
/// process is hosting unit tests, the window is a decoy — quitting on
/// close killed the test host mid-run and failed whichever test was
/// executing ("test runner exited with code 0").
///
/// Outside tests the delegate pretends not to implement the method at all
/// (via `responds(to:)`), so SwiftUI's own last-window-closed behavior —
/// including staying alive while the menu-bar extra is active — is
/// untouched.
final class TestHostSafeAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)) {
            return SeeleSeekApp.isRunningTests
        }
        return super.responds(to: aSelector)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // Only consulted under tests — see responds(to:).
    }
}
#endif
