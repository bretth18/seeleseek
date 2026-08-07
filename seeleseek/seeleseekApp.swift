import SwiftUI
import AppIntents
import SeeleseekCore

@main
struct SeeleSeekApp: App {
    @State private var appState: AppState

    /// Identifies the main scene so the status-bar menu can ask for it back
    /// after its window was closed.
    static let mainWindowID = "main"

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        if !Self.isRunningInPreview {
            AppDependencyManager.shared.add(dependency: state)
        }
    }

    fileprivate static var isRunningInPreview: Bool {
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
        WindowGroup(id: Self.mainWindowID) {
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
                    #if os(macOS)
                    .modifier(MenuBarInstaller(appState: appState, delegate: appDelegate))
                    #endif
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            TabNavigationCommands()
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    appState.requestSearchFieldFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task { await appState.updateState.checkForUpdate() }
                }
            }
            CommandMenu("Connection") {
                Toggle("Away", isOn: Binding(
                    get: { appState.connection.onlineStatus == .away },
                    set: { appState.setOnlineStatus($0 ? .away : .online) }
                ))
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(appState.connection.connectionStatus != .connected)

                Divider()

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
        #endif
    }
}

#if os(macOS)
/// Installs the status item once the scene exists.
///
/// This is a modifier rather than a bare `.task` because the controller needs
/// `openWindow`, and `OpenWindowAction` only resolves from a view's
/// environment — not from `App`. Reading it here also means the action stays
/// valid after the window it was read from is gone, which is exactly the case
/// the menu has to handle.
private struct MenuBarInstaller: ViewModifier {
    let appState: AppState
    let delegate: TestHostSafeAppDelegate

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            if SeeleSeekApp.isRunningInPreview { return }
            delegate.configureMenuBar(appState: appState) {
                openWindow(id: SeeleSeekApp.mainWindowID)
            }
        }
    }
}

/// Closing the last window normally quits a SwiftUI macOS app. When the
/// process is hosting unit tests, the window is a decoy — quitting on
/// close killed the test host mid-run and failed whichever test was
/// executing ("test runner exited with code 0").
///
/// The delegate also owns the status-bar item. That used to be a SwiftUI
/// `MenuBarExtra`, which kept the app alive on its own once the last window
/// closed; an AppKit `NSStatusItem` does not, so the last-window behavior is
/// answered here whenever the menu bar is showing.
final class TestHostSafeAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private var menuBarController: MenuBarController?

    /// Called once the app state exists. Installs the status item and keeps it
    /// in sync with the "Show in menu bar" setting. `openMainWindow` comes
    /// from the scene's environment — the controller cannot reach it itself.
    @MainActor
    func configureMenuBar(appState: AppState, openMainWindow: @escaping () -> Void) {
        guard !SeeleSeekApp.isRunningTests, menuBarController == nil else { return }

        let controller = MenuBarController(appState: appState, openMainWindow: openMainWindow)
        menuBarController = controller
        controller.setVisible(appState.settings.showInMenuBar)
        appState.settings.onShowInMenuBarChange = { [weak controller] visible in
            controller?.setVisible(visible)
        }
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Under tests the window is a decoy and must never take the host down.
        if SeeleSeekApp.isRunningTests { return false }
        // Otherwise the app lives in the menu bar when one is showing, and
        // quits with its last window when it isn't.
        return !(menuBarController?.isInstalled ?? false)
    }
}
#endif
