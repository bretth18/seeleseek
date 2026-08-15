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
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Existing main `WindowGroup` window, if any (not Settings / panels).
    static var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            guard window.styleMask.contains(.titled), window.canBecomeMain else { return false }
            return window.isVisible || window.isMiniaturized
        }
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
}
#endif
