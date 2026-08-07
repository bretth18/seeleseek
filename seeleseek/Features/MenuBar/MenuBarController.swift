import AppKit
import SeeleseekCore

/// Status-bar presence, built on AppKit rather than SwiftUI's `MenuBarExtra`.
///
/// A `MenuBarExtra` in `.window` style is not a menu — it is an ordinary panel
/// that the app has to decorate itself, which means re-implementing (and
/// inevitably mismatching) the system's corner radius, material, row metrics
/// and highlight. Two behaviors cannot be re-implemented at all: a panel does
/// not keep the menu bar revealed while it is open in full-screen mode, and it
/// does not follow menu-tracking rules when the active screen changes. A real
/// `NSMenu` gets all of that from the system for free.
///
/// The cost of a real menu is that AppKit dims disabled items, and the header
/// row is disabled because it is a label rather than a control. Dimming would
/// wash out the status color, so that row carries an `attributedTitle` with an
/// explicit foreground color — attributed titles survive the disabled
/// treatment. The transfer rows *are* actionable (each opens the section it
/// summarizes) and so are enabled; they keep their attributed titles for the
/// speed/count coloring.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private var statusItem: NSStatusItem?
    private weak var menu: NSMenu?

    /// Rows whose contents change while the menu is on screen. Held so a tick
    /// can retitle them in place instead of rebuilding the menu.
    private var headerItem: NSMenuItem?
    private var speedsItem: NSMenuItem?
    private var downloadItem: NSMenuItem?
    private var uploadItem: NSMenuItem?
    private var queuedItem: NSMenuItem?

    /// The row the cursor is on. AppKit inverts a plain `title` on highlight
    /// but leaves an `attributedTitle`'s explicit colors alone, so the colored
    /// rows would keep their dark ink on the accent fill (~1.7:1). Tracked so
    /// the highlight can be repainted and undone.
    private weak var highlightedItem: NSMenuItem?

    private var refreshTimer: Timer?
    private var lastModel: MenuBarModel?

    /// Identifies the current `withObservationTracking` chain. A registered
    /// observation cannot be cancelled, so an outgoing chain is retired by
    /// bumping this: its `onChange` sees a stale generation and returns
    /// without re-arming. A plain bool would let every chain from every past
    /// install re-arm itself, so toggling "Show in menu bar" N times would
    /// leave N chains all repainting the same button.
    private var observationGeneration = 0
    private var isObservingStatus = false

    /// Brings the app's main window back. Injected because a closed
    /// `WindowGroup` window no longer exists as an `NSWindow` — only SwiftUI
    /// can recreate it — and with the status item installed the app
    /// deliberately outlives its last window, so that is the normal state
    /// rather than an edge case.
    private let openMainWindow: () -> Void

    init(appState: AppState, openMainWindow: @escaping () -> Void) {
        self.appState = appState
        self.openMainWindow = openMainWindow
        super.init()
    }

    // MARK: - Lifecycle

    var isInstalled: Bool { statusItem != nil }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(resource: .gsgaag2Menubar2)
            image.isTemplate = true
            button.image = image
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu

        statusItem = item
        self.menu = menu

        // The icon has to answer "what is my connection state?" without the
        // user opening anything — that is the entire point of a status item.
        applyStatusToButton()
        startObservingStatus()
    }

    func uninstall() {
        guard let item = statusItem else { return }
        stopRefreshTimer()
        stopObservingStatus()
        item.menu?.delegate = nil
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        menu = nil
        clearItemReferences()
        lastModel = nil
    }

    /// Applies the "Show in menu bar" setting.
    func setVisible(_ visible: Bool) {
        visible ? install() : uninstall()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu, with: currentModel())
    }

    func menuWillOpen(_ menu: NSMenu) {
        startRefreshTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopRefreshTimer()
        highlightedItem = nil
    }

    /// Repaints the colored rows white while the cursor is on them, and
    /// restores their palette color on the way out. `item` is nil when the
    /// cursor leaves the menu entirely.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Tracked unconditionally: `tint` reads this on every configure, so
        // letting it fall out of sync when there is no model yet would leave
        // the next repaint painting for the wrong highlight state.
        let previous = highlightedItem
        highlightedItem = item

        guard let model = lastModel else { return }

        // Restore the outgoing row before painting the incoming one. The two
        // are never the same object (`previous !== item` guards it), so the
        // order is about reading cleanly rather than correctness.
        if let previous, previous !== item {
            reconfigure(previous, model: model)
        }
        if let item {
            reconfigure(item, model: model)
        }
    }

    /// Re-runs whichever configure function owns this row.
    private func reconfigure(_ item: NSMenuItem, model: MenuBarModel) {
        switch item {
        case speedsItem: configureSpeeds(item, model: model)
        case downloadItem: configureDownload(item, model: model)
        case uploadItem: configureUpload(item, model: model)
        case queuedItem: configureQueued(item, model: model)
        default: break  // header and the plain-title rows need no repaint
        }
    }

    /// The color a palette-tinted run should actually be drawn in, given
    /// whether its row is currently highlighted.
    private func tint(_ color: NSColor, for item: NSMenuItem) -> NSColor {
        item === highlightedItem ? .selectedMenuItemTextColor : color
    }

    // MARK: - Status item button

    /// Tints the template icon by connection state. `.connected` deliberately
    /// gets no tint: the normal, unremarkable state should look like every
    /// other menu-bar icon, and color should mean "something needs you".
    private func applyStatusToButton() {
        guard let button = statusItem?.button else { return }

        let status = appState.connection.connectionStatus
        button.contentTintColor = status == .connected ? nil : status.adaptiveNSColor
        button.toolTip = headerAccessibilityLabel(
            status: status,
            username: appState.connection.username
        )
        button.setAccessibilityLabel("SeeleSeek — \(status.label)")
    }

    /// `withObservationTracking` fires once per change, so it re-arms itself.
    /// This runs whether or not the menu is open — unlike the refresh timer,
    /// which exists only to animate an already-visible menu.
    private func startObservingStatus() {
        guard !isObservingStatus else { return }
        isObservingStatus = true
        armStatusObservation(generation: observationGeneration)
    }

    private func stopObservingStatus() {
        isObservingStatus = false
        // Retires the live chain: its onChange will see the bump and stop.
        observationGeneration &+= 1
    }

    private func armStatusObservation(generation: Int) {
        withObservationTracking {
            _ = appState.connection.connectionStatus
            _ = appState.connection.username
        } onChange: { [weak self] in
            // onChange fires *before* the value is written, so the read has to
            // happen on a later turn of the run loop.
            Task { @MainActor [weak self] in
                guard let self,
                      self.isObservingStatus,
                      generation == self.observationGeneration,
                      self.statusItem != nil
                else { return }
                self.applyStatusToButton()
                self.armStatusObservation(generation: generation)
            }
        }
    }

    // MARK: - Live refresh

    /// AppKit asks the delegate for contents exactly once, right before the
    /// menu appears, and never again while it is on screen — so speeds and
    /// transfer counts would freeze at their open-time values. This ticks the
    /// menu for as long as it is open, and only then.
    private func startRefreshTimer() {
        stopRefreshTimer()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timers fire on the run loop that owns them — the main one here.
            MainActor.assumeIsolated { self?.refresh() }
        }
        // While a menu tracks, the run loop is in .eventTracking; a timer
        // registered only in .default would not fire until the menu closed,
        // which is the whole problem being fixed. .common covers both.
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refresh() {
        guard let menu, menu.numberOfItems > 0 else { return }

        let model = currentModel()
        guard model != lastModel else { return }

        // Retitling in place keeps the open menu's highlight and geometry
        // steady. A full rebuild is only needed when a row appears or
        // disappears, which changes the item layout anyway.
        if model.shape == lastModel?.shape {
            applyInPlace(model)
            lastModel = model
        } else {
            rebuild(menu, with: model)
        }
    }

    private func applyInPlace(_ model: MenuBarModel) {
        if let headerItem { configureHeader(headerItem, model: model) }
        if let speedsItem { configureSpeeds(speedsItem, model: model) }
        if let downloadItem { configureDownload(downloadItem, model: model) }
        if let uploadItem { configureUpload(uploadItem, model: model) }
        if let queuedItem { configureQueued(queuedItem, model: model) }
    }

    // MARK: - Menu construction

    private func rebuild(_ menu: NSMenu, with model: MenuBarModel) {
        menu.removeAllItems()
        clearItemReferences()

        let header = NSMenuItem()
        // Stays disabled: an enabled item highlights under the cursor, and a
        // header that lights up like a control but does nothing is worse than
        // a dim one. The dimming is answered by the opaque color in
        // `headerTitle` instead — attributed titles keep their own foreground
        // through the disabled treatment.
        header.isEnabled = false
        configureHeader(header, model: model)
        menu.addItem(header)
        headerItem = header

        if model.showsSpeeds {
            let speeds = NSMenuItem()
            speeds.action = #selector(openNetworkMonitor)
            speeds.target = self
            configureSpeeds(speeds, model: model)
            menu.addItem(speeds)
            speedsItem = speeds
        }

        if model.showsDownloads || model.showsUploads || model.showsQueued {
            menu.addItem(.separator())
        }

        if model.showsDownloads {
            let item = NSMenuItem()
            item.action = #selector(openTransfers)
            item.target = self
            configureDownload(item, model: model)
            menu.addItem(item)
            downloadItem = item
        }

        if model.showsUploads {
            let item = NSMenuItem()
            item.action = #selector(openTransfers)
            item.target = self
            configureUpload(item, model: model)
            menu.addItem(item)
            uploadItem = item
        }

        if model.showsQueued {
            let item = NSMenuItem()
            item.action = #selector(openTransfers)
            item.target = self
            configureQueued(item, model: model)
            menu.addItem(item)
            queuedItem = item
        }

        menu.addItem(.separator())

        // No key equivalents on these. A status-item menu is not in the main
        // menu bar, but its shortcuts still go through the same command-key
        // dispatch: ⌘Q would shadow the app's own Quit and ⌘, would race the
        // Settings scene. Every command-key press also re-runs
        // menuNeedsUpdate, rebuilding this menu for a keystroke aimed
        // somewhere else. The equivalents live in the main menu instead.
        let open = NSMenuItem(
            title: "Open SeeleSeek",
            action: #selector(openApp),
            keyEquivalent: ""
        )
        open.target = self
        open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(open)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit SeeleSeek",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)

        lastModel = model
    }

    private func clearItemReferences() {
        headerItem = nil
        speedsItem = nil
        downloadItem = nil
        uploadItem = nil
        queuedItem = nil
    }

    // MARK: - Row configuration

    private func configureHeader(_ item: NSMenuItem, model: MenuBarModel) {
        let color = model.status.adaptiveNSColor
        let isNamed = model.status == .connected && model.username != nil

        item.image = symbol(model.status.icon, color: color)
        item.attributedTitle = headerTitle(
            primary: isNamed ? (model.username ?? model.status.label) : model.status.label,
            secondary: isNamed ? model.status.label : nil,
            secondaryColor: color
        )
        // VoiceOver skips disabled rows, so this label is not what announces
        // the connection state — the status-item button carries that (see
        // applyStatusToButton). Kept so the row reads sensibly if AppKit ever
        // does expose it.
        item.setAccessibilityLabel(
            headerAccessibilityLabel(status: model.status, username: model.username)
        )
    }

    private func configureSpeeds(_ item: NSMenuItem, model: MenuBarModel) {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .medium
        )

        let title = NSMutableAttributedString(
            string: "↓ \(model.downSpeed.formattedSpeed)",
            attributes: [
                .font: font,
                .foregroundColor: tint(SeeleColors.Adaptive.infoNS, for: item),
            ]
        )
        title.append(NSAttributedString(
            string: "    ↑ \(model.upSpeed.formattedSpeed)",
            attributes: [
                .font: font,
                .foregroundColor: tint(SeeleColors.Adaptive.successNS, for: item),
            ]
        ))

        item.attributedTitle = title
        item.setAccessibilityLabel(
            "Download speed: \(model.downSpeed.formattedSpeed). "
                + "Upload speed: \(model.upSpeed.formattedSpeed). Opens Activity."
        )
    }

    private func configureDownload(_ item: NSMenuItem, model: MenuBarModel) {
        configureInfo(
            item,
            text: "\(model.activeDown) download\(model.activeDown == 1 ? "" : "s")",
            detail: model.downSpeed > 0 ? model.downSpeed.formattedSpeed : nil,
            symbolName: "arrow.down.circle.fill",
            color: SeeleColors.Adaptive.infoNS
        )
    }

    private func configureUpload(_ item: NSMenuItem, model: MenuBarModel) {
        configureInfo(
            item,
            text: "\(model.activeUp) upload\(model.activeUp == 1 ? "" : "s")",
            detail: model.upSpeed > 0 ? model.upSpeed.formattedSpeed : nil,
            symbolName: "arrow.up.circle.fill",
            color: SeeleColors.Adaptive.successNS
        )
    }

    private func configureQueued(_ item: NSMenuItem, model: MenuBarModel) {
        configureInfo(
            item,
            text: "\(model.queued) queued",
            detail: nil,
            symbolName: "clock.fill",
            color: SeeleColors.Adaptive.warningNS
        )
    }

    private func configureInfo(
        _ item: NSMenuItem,
        text: String,
        detail: String?,
        symbolName: String,
        color: NSColor
    ) {
        let isHighlighted = item === highlightedItem
        let inkColor = isHighlighted
            ? NSColor.selectedMenuItemTextColor
            : SeeleColors.Adaptive.labelPrimaryNS

        let title = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: inkColor,
            ]
        )
        if let detail {
            title.append(NSAttributedString(
                string: "  " + detail,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.smallSystemFontSize,
                        weight: .regular
                    ),
                    .foregroundColor: tint(color, for: item),
                ]
            ))
        }

        item.attributedTitle = title
        item.image = symbol(symbolName, color: tint(color, for: item))
        item.setAccessibilityLabel(
            (detail.map { "\(text), \($0)" } ?? text) + ". Opens Transfers."
        )
    }

    private func headerTitle(
        primary: String,
        secondary: String?,
        secondaryColor: NSColor
    ) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: primary,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0).bold,
                .foregroundColor: SeeleColors.Adaptive.labelPrimaryNS,
            ]
        )
        if let secondary {
            // Without an explicit paragraph style the two lines are spaced by
            // whatever the font's default leading happens to be, which drifts
            // with the system text size. Pinning it keeps the header the same
            // height relative to its rows at every size.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 1
            paragraph.paragraphSpacingBefore = 1

            title.append(NSAttributedString(
                string: "\n" + secondary,
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: paragraph,
                ]
            ))
        }
        return title
    }

    private func symbol(_ name: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        // A palette configuration tints the symbol without turning it into a
        // template, so the status color survives.
        return image.withSymbolConfiguration(.init(paletteColors: [color]))
    }

    // MARK: - Actions

    /// Raising an existing window is not enough. With the status item
    /// installed the app deliberately survives its last window closing, and a
    /// closed `WindowGroup` window is *destroyed*, not hidden — so on the
    /// common "closed to the menu bar" path there is nothing in
    /// `NSApp.windows` to raise. `openMainWindow` asks SwiftUI to bring the
    /// scene back; activation follows so the restored window comes forward.
    @objc private func openApp() {
        NSApplication.shared.activate()

        if let existing = NSApplication.shared.windows.first(where: {
            $0.canBecomeMain && $0.isVisible
        }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        openMainWindow()
    }

    /// Every row that summarizes a section deep-links into it, so the summary
    /// is a way in rather than a dead end.
    private func open(_ item: SidebarItem) {
        appState.sidebarSelection = item
        openApp()
    }

    @objc private func openTransfers() { open(.transfers) }

    @objc private func openNetworkMonitor() { open(.networkMonitor) }

    /// Opens the `Settings` *scene*, not the sidebar's settings page. The two
    /// coexist (⌘9 navigates the sidebar), but a row labelled "Settings…"
    /// with an ellipsis promises the standard settings window, and that is
    /// what the system Settings menu item opens too.
    @objc private func openSettings() {
        NSApplication.shared.activate()
        // The selector was renamed in Ventura; the old one is still what
        // pre-Ventura systems respond to, so try the current name first and
        // fall back rather than picking by OS version.
        let modern = Selector(("showSettingsWindow:"))
        let legacy = Selector(("showPreferencesWindow:"))
        if NSApplication.shared.responds(to: modern) {
            NSApplication.shared.sendAction(modern, to: nil, from: nil)
        } else {
            NSApplication.shared.sendAction(legacy, to: nil, from: nil)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - State snapshot

    private func currentModel() -> MenuBarModel {
        MenuBarModel(
            status: appState.connection.connectionStatus,
            username: appState.connection.username,
            downSpeed: appState.transferState.totalDownloadSpeed,
            upSpeed: appState.transferState.totalUploadSpeed,
            activeDown: appState.transferState.activeDownloads.count,
            activeUp: appState.uploadManager.activeUploadCount,
            queued: appState.transferState.queuedDownloads.count
        )
    }

    private func headerAccessibilityLabel(
        status: ConnectionStatus,
        username: String?
    ) -> String {
        var label = "Connection status: \(status.label)"
        if status == .connected, let username {
            label += " as \(username)"
        }
        return label
    }
}

/// Everything the menu displays, snapshotted so a refresh tick can tell what
/// actually changed — nothing (skip), values only (retitle in place), or which
/// rows exist (rebuild).
///
/// Internal rather than private so the rebuild-vs-retitle decision — the one
/// piece of real logic here that does not need a live status bar — is
/// reachable from tests.
struct MenuBarModel: Equatable {
    var status: ConnectionStatus
    var username: String?
    var downSpeed: Int64
    var upSpeed: Int64
    var activeDown: Int
    var activeUp: Int
    var queued: Int

    var showsSpeeds: Bool { status == .connected }
    var showsDownloads: Bool { activeDown > 0 }
    var showsUploads: Bool { activeUp > 0 }
    var showsQueued: Bool { queued > 0 }

    /// Which rows are present. The header's second line counts too: it appears
    /// only when connected with a username, and adds a line to that row.
    var shape: Shape {
        Shape(
            speeds: showsSpeeds,
            downloads: showsDownloads,
            uploads: showsUploads,
            queued: showsQueued,
            namedHeader: status == .connected && username != nil
        )
    }

    struct Shape: Equatable {
        var speeds: Bool
        var downloads: Bool
        var uploads: Bool
        var queued: Bool
        var namedHeader: Bool
    }
}

private extension NSFont {
    var bold: NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
