#if os(macOS)
import AppKit

/// Keeps `NSApp` activation policy in sync with **Minimize to menu bar**.
///
/// When that setting is on (and the menu bar extra is present), closing the
/// last titled window switches to `.accessory` so the Dock icon disappears.
/// Any titled window (main, Settings, update prompt) — including a
/// miniaturized one — restores `.regular`.
@MainActor
enum DockIconPolicy {
    private static var isObserving = false
    private static weak var settings: SettingsState?
    /// `activate()` / accessory→regular can ask SwiftUI to reopen a window.
    /// Menu-bar Open/Settings already create the window they want; a second
    /// one from reopen is the duplicate-instance bug.
    private static var suppressAutomaticReopen = false

    static func start(settings: SettingsState) {
        self.settings = settings
        settings.onDockPolicyRelevantChange = {
            refresh()
        }
        startObservingWindowsIfNeeded()
        refresh()
    }

    static func refresh() {
        guard !SeeleSeekApp.isRunningTests else { return }
        guard let settings else { return }

        let hideDock = settings.minimizeToMenuBar
            && settings.showInMenuBar
            && !hasPresentableWindows

        let policy: NSApplication.ActivationPolicy = hideDock ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Switch to a normal Docked app and activate so a window can come forward.
    static func prepareToPresentWindow() {
        suppressAutomaticReopen = true
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            suppressAutomaticReopen = false
            discardExtraMainWindows()
        }
    }

    /// Existing main scene window, if any (not Settings / panels).
    /// Includes a not-yet-visible window so Open does not spawn a second one.
    static var mainWindow: NSWindow? {
        let windows = NSApp.windows
        if let named = windows.first(where: { $0.identifier?.rawValue == "main" }) {
            return named
        }
        return windows.first(where: isLikelyMainWindow)
    }

    /// Dock click / Cmd-Tab reopen. Return `true` only when SwiftUI should
    /// create the main window; `false` when we already showed one (or the
    /// menu-bar path is about to).
    static func handleReopen(hasVisibleWindows: Bool) -> Bool {
        if suppressAutomaticReopen { return false }
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return !hasVisibleWindows
    }

    // MARK: - Private

    private static func startObservingWindowsIfNeeded() {
        guard !isObserving else { return }
        isObserving = true

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // willClose still reports the window as visible; defer so the
                // window list matches post-close reality.
                Task { @MainActor in
                    refresh()
                }
            }
        }
    }

    /// Titled app windows only — menu-bar extras and status items are excluded
    /// so opening the menu while Dock-hidden does not flash a Dock icon.
    private static var hasPresentableWindows: Bool {
        NSApp.windows.contains { window in
            guard window.styleMask.contains(.titled) else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    private static func isLikelyMainWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), window.canBecomeMain else { return false }
        let id = window.identifier?.rawValue ?? ""
        if id == "update-prompt" { return false }
        if id.localizedCaseInsensitiveContains("settings") { return false }
        let title = window.title
        if title == "Update Available" || title == "Settings" { return false }
        return window.isVisible || window.isMiniaturized
    }

    private static func isMainSceneWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == "main" { return true }
        return isLikelyMainWindow(window)
    }

    /// Accessory→regular plus `openWindow` can both materialize a main window.
    /// Keep the frontmost one.
    private static func discardExtraMainWindows() {
        let mains = NSApp.windows.filter(isMainSceneWindow)
        guard mains.count > 1 else { return }
        let keeper = mains.first(where: \.isKeyWindow)
            ?? mains.first(where: \.isMainWindow)
            ?? mains.first(where: \.isVisible)
            ?? mains[0]
        for window in mains where window !== keeper {
            window.close()
        }
    }
}
#endif
