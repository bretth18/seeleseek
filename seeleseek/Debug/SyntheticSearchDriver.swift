#if DEBUG
import Foundation
import SeeleseekCore
import AppKit

/// Deterministic reproduction of "scroll the results list while a search
/// streams in" — the scenario behind the search scroll-hitching reports —
/// without needing a server login or live peers.
///
/// Launch with `--synth-search` (optionally `--synth-scroll`):
///   - streams ~500 synthetic results in peer-sized batches over ~30s
///   - `--synth-scroll` sweeps the results scroll view up and down
///   - a main-actor pacer logs `PACE` lines (dropped-frame buckets per 5s)
///     so variants can be compared by numbers instead of eyeballing
/// Profile with `sample <pid>` while it runs.
/// `SEELE_LOG_CHANGES=1` turns on per-view invalidation logging (see the
/// `Self._printChanges()` probes in the search view cascade): each body
/// re-evaluation prints which dependency changed, so observable-churn
/// storms can be attributed to their source instead of guessed at.
enum SynthDiag {
    nonisolated static let logChanges =
        ProcessInfo.processInfo.environment["SEELE_LOG_CHANGES"] != nil
}

@MainActor
enum SyntheticSearchDriver {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--synth-search")
    }

    /// LIVE mode: the app logs in and searches the real SoulSeek network
    /// (normal `configure()` path), while the driver supplies the same
    /// measurement rig — pacer, auto-scroll, cursor parking. This is the
    /// only mode that exercises the real control plane: server messages,
    /// peer-connection churn, pool bookkeeping, GeoIP — the load the
    /// in-process synthetic stream bypasses entirely.
    static var isLiveEnabled: Bool {
        CommandLine.arguments.contains("--synth-live")
    }

    private static var autoScroll: Bool {
        CommandLine.arguments.contains("--synth-scroll")
    }

    /// PROBE mode: instead of load generation, verify the search-row
    /// action cluster end to end — warp the real cursor over each button
    /// (so tracking areas engage hover), synthesize a click through the
    /// window's event pipeline, and log which app action actually fired.
    private static var probe: Bool {
        CommandLine.arguments.contains("--synth-probe")
    }

    /// `_printChanges` goes through `print` → stdout, which is block-
    /// buffered when redirected to a file; a killed process drops the
    /// unflushed tail. Line-buffer it so change logs survive.
    private static func lineBufferStdout() {
        setvbuf(stdout, nil, _IOLBF, 0)
    }

    static func start(appState: AppState) {
        lineBufferStdout()
        appState.connection.setConnected(
            username: "demo_user",
            ip: "192.0.2.42",
            greeting: ""
        )
        appState.sidebarSelection = .search

        // Launched from a terminal the app starts in the background, where
        // the window is occluded and nothing renders — the repro needs
        // live drawing.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        moveWindowToFastestScreenAfterRestore()

        startHangMonitor()
        Task { await streamForever(appState: appState) }
        if autoScroll {
            Task { await runAutoScroll() }
        }
        startCursorParkingIfRequested()
        if probe {
            Task { await runClusterProbe(appState: appState) }
        }
    }

    // MARK: - Cluster probe

    /// Hover + click each button of a search row's trailing cluster and
    /// log the app state that changes, so click-target accuracy can be
    /// verified from the log alone. Run with SEELE_LOG_CHANGES=1 to also
    /// see hover engagement (the cluster re-prints on the env flip).
    private static func runClusterProbe(appState: AppState) async {
        try? await Task.sleep(for: .seconds(8))
        guard let scrollView = resultsScrollView(),
              scrollView.documentView != nil,
              scrollView.window != nil else {
            synthLog("PROBE: results scroll view not found")
            return
        }

        // Document coords are authoritative: converting from the document
        // view sidesteps content insets, scroll offset, and flippedness.
        // Row pitch = rowHeight 58 + divider 1; probe row 3's center.
        let rowCenterDocY = 3 * 59.0 + 29.0
        // From the row's trailing edge (doc right): padding 16, download
        // 32 wide, gap 2, person 28, gap 2, folder 28.
        let targets: [(name: String, xFromRight: CGFloat)] = [
            ("person(view-profile)", 64),   // 16 + 32 + 2 + 14
            ("folder(browse-folder)", 94), // 16 + 32 + 2 + 28 + 2 + 14
        ]

        for target in targets {
            appState.socialState.showProfileSheet = false
            appState.sidebarSelection = .search
            try? await Task.sleep(for: .seconds(1))
            guard let sv = resultsScrollView(), let d = sv.documentView,
                  let win = sv.window else { break }
            let docPoint = NSPoint(x: d.bounds.maxX - target.xFromRight, y: rowCenterDocY)
            let winPoint = d.convert(docPoint, to: nil)

            // Real-cursor warp so tracking areas fire mouseEntered, plus
            // a synthesized move so SwiftUI sees the position.
            let screenPoint = win.convertPoint(toScreen: winPoint)
            if let screenHeight = NSScreen.screens.first?.frame.height {
                CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y))
            }
            sendMouse(.mouseMoved, at: winPoint, in: win)
            try? await Task.sleep(for: .milliseconds(700))

            let before = probeStateSnapshot(appState)
            sendMouse(.leftMouseDown, at: winPoint, in: win, clickCount: 1)
            try? await Task.sleep(for: .milliseconds(80))
            sendMouse(.leftMouseUp, at: winPoint, in: win, clickCount: 1)
            try? await Task.sleep(for: .milliseconds(1200))
            let after = probeStateSnapshot(appState)
            synthLog("PROBE: \(target.name) @doc(\(Int(docPoint.x)),\(Int(docPoint.y)))")
            synthLog("PROBE:   before \(before)")
            synthLog("PROBE:   after  \(after)")
        }
        synthLog("PROBE: done")
    }

    private static func probeStateSnapshot(_ appState: AppState) -> String {
        let sidebar = String(describing: appState.sidebarSelection)
        let folder = appState.browseState.currentFolderPath ?? "nil"
        let profile = appState.socialState.viewingProfile?.username ?? "nil"
        return "sidebar=\(sidebar) browseUser='\(appState.browseState.currentUser)' folder='\(folder)' profileSheet=\(appState.socialState.showProfileSheet):\(profile)"
    }

    private static var probeEventNumber = 1000
    private static func sendMouse(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        in window: NSWindow,
        clickCount: Int = 0
    ) {
        probeEventNumber += 1
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: probeEventNumber,
            clickCount: clickCount,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else { return }
        window.sendEvent(event)
    }

#if false
    /// LIVE mode — see `isLiveEnabled`. The caller has already run the
    /// normal `appState.configure()`; this waits for the real login, then
    /// runs endless real search cycles with the same stream/hold phase
    /// cadence as the synthetic mode so PACE lines stay comparable.
    static func startLive(appState: AppState) {
        lineBufferStdout()
        appState.sidebarSelection = .search
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        moveWindowToFastestScreenAfterRestore()
        startHangMonitor()
        if autoScroll {
            Task { await runAutoScroll() }
        }
        startCursorParkingIfRequested()
        Task { await liveSearchForever(appState: appState) }
    }

#endif
#if false
    private static func liveSearchForever(appState: AppState) async {
        // There is no auto-connect in the app — LoginView's button does
        // this. Replicate its flow with the saved credentials.
        // NOTE: SoulSeek permits one session per account; this kicks any
        // other running client on the same account.
        try? await Task.sleep(for: .seconds(3))  // let configure()'s async setup land
        guard let credentials = CredentialStorage.load() else {
            synthLog("LIVE: no saved credentials in keychain — cannot log in")
            return
        }
        appState.connection.loginUsername = credentials.username
        appState.connection.loginPassword = credentials.password
        appState.connection.setConnecting()
        await appState.networkClient.setAcceptDistributedChildrenPreference(appState.settings.respondToSearches)
        await appState.networkClient.connect(
            server: ServerConnection.defaultHost,
            port: ServerConnection.defaultPort,
            username: credentials.username,
            password: credentials.password,
            preferredListenPort: UInt16(appState.settings.listenPort)
        )

        var waited = 0
        while appState.connection.connectionStatus != .connected {
            guard waited < 30 else {
                synthLog("LIVE: gave up waiting for login after \(waited)s (error: \(appState.networkClient.status.connectionError ?? "none"))")
                return
            }
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        synthLog("LIVE: connected after \(waited)s")
        try? await Task.sleep(for: .seconds(2))

        let queries = ["mozart flac", "aphex twin", "beatles", "ambient flac", "miles davis", "radiohead"]
        var cycle = 0
        while true {
            let query = queries[cycle % queries.count]
            cycle += 1
            appState.searchState.searchQuery = query
            let token = UInt32.random(in: 1..<0x8000_0000)
            appState.searchState.startSearch(token: token)
            phase = "stream"
            synthLog("LIVE: cycle \(cycle) query '\(query)'")
            do {
                try await appState.networkClient.search(query: query, token: token)
            } catch {
                synthLog("LIVE: search send failed: \(error)")
            }
            // Real searches stream on the server's schedule; give them the
            // same 25s stream + 10s hold cadence the synthetic mode uses.
            try? await Task.sleep(for: .seconds(25))
            phase = "hold"
            try? await Task.sleep(for: .seconds(10))
            if let index = appState.searchState.searches.firstIndex(where: { $0.token == token }) {
                appState.searchState.closeSearch(at: index)
            }
        }
    }

#endif
    private static func startCursorParkingIfRequested() {
        if CommandLine.arguments.contains("--synth-cursor") {
            // Park the real cursor over the results list. Cursor-in-window
            // is a distinct performance regime: AppKit/SwiftUI re-evaluate
            // hover targets against the moving rows every frame. Warped
            // periodically so a user nudge doesn't silently end the regime.
            Task {
                var lastWarp = ContinuousClock.now - .seconds(10)
                while true {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let scrollView = resultsScrollView(),
                          let window = scrollView.window else { continue }
                    let local = scrollView.convert(
                        NSPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY),
                        to: nil
                    )
                    if ContinuousClock.now - lastWarp > .seconds(2) {
                        lastWarp = .now
                        let screen = window.convertPoint(toScreen: local)
                        if let screenHeight = NSScreen.screens.first?.frame.height {
                            CGWarpMouseCursorPosition(CGPoint(x: screen.x, y: screenHeight - screen.y))
                        }
                    }
                    // Warping alone fires no events, so hover/tracking would
                    // stay dormant; a synthesized in-window mouseMoved at the
                    // parked position runs the real pipeline each tick.
                    if let move = NSEvent.mouseEvent(
                        with: .mouseMoved,
                        location: local,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 0,
                        pressure: 0
                    ) {
                        window.sendEvent(move)
                    }
                }
            }
        }
    }

    /// Which repro phase is running, for per-phase scroll stats:
    /// "stream" while results land, "hold" after the search completes.
    private static var phase = "stream"

    /// Endless repro cycles: stream a full search, hold 10s (the
    /// "completed search" scroll phase), close the tab, start over.
    private static func streamForever(appState: AppState) async {
        let state = appState.searchState
        var cycle: UInt32 = 0
        while true {
            cycle += 1
            state.searchQuery = "synthetic stress \(cycle)"
            let token = 0x5EED_0000 + cycle
            state.startSearch(token: token)
            phase = "stream"
            synthLog("SYNTH: cycle \(cycle) streaming")
            await stream(into: state, token: token, appState: appState)
            phase = "hold"
            try? await Task.sleep(for: .seconds(10))
            if let index = state.searches.firstIndex(where: { $0.token == token }) {
                state.closeSearch(at: index)
            }
        }
    }

    /// `print` to a redirected stdout is block-buffered; stderr is not.
    /// Lines are also mirrored to `SEELE_SYNTH_LOG`, or to
    /// `seele_synth.log` in the app's own temp directory if no override is
    /// provided. UI-test-launched instances often swallow stderr, so the
    /// file copy is the stable way to inspect pacing data after a run.
    private static let logFile: FileHandle? = {
        let requested = ProcessInfo.processInfo.environment["SEELE_SYNTH_LOG"]
        for path in [requested, NSTemporaryDirectory() + "seele_synth.log"].compactMap({ $0 }) {
            FileManager.default.createFile(atPath: path, contents: nil)
            if let handle = FileHandle(forWritingAtPath: path) { return handle }
        }
        return nil
    }()

    private static func synthLog(_ message: String) {
        let stamp = String(format: "%.1f", ProcessInfo.processInfo.systemUptime)
        let data = Data(("[\(stamp)] " + message + "\n").utf8)
        FileHandle.standardError.write(data)
        logFile?.write(data)
    }

    // MARK: - Result streaming

    /// Batches sized like real peer replies (a few files from one or two
    /// folders per peer), with jittered arrival, until ~500 results — the
    /// default `maxSearchResults`. Each peer also runs the country
    /// pipeline the way a real reply does: `registerIP` (async GeoIP task
    /// + `onCountryResolved` into SocialState) plus a seeded ISO code so
    /// every row deterministically renders its flag-emoji Text — real rows
    /// carry that color-emoji glyph and the first harness versions never
    /// created it at all.
    private static func stream(into state: SearchState, token: UInt32, appState: AppState) async {
        let cache = appState.networkClient.userInfoCache
        var total = 0
        var peer = 0
        while total < 500 {
            try? await Task.sleep(for: .milliseconds(UInt64.random(in: 30...140)))
            peer += 1
            let batch = peerBatch(peer: peer)
            if let username = batch.first?.username {
                cache.registerIP("81.2.\(peer % 250).\(peer % 200 + 1)", for: username)
                cache.seedCountry(Self.countryCodes[peer % Self.countryCodes.count], for: username)
            }
            state.addResults(batch, forToken: token)
            total += batch.count
        }
        synthLog("SYNTH: streaming done, \(total) results sent")
    }

    private static let countryCodes = [
        "US", "DE", "GB", "FR", "NL", "SE", "PL", "BR",
        "JP", "AU", "CA", "FI", "IT", "ES", "CZ", "NO",
    ]

    private static let artists = [
        "Radiohead", "Boards of Canada", "Aphex Twin", "Cindy Lee",
        "My Bloody Valentine", "Slowdive", "Fennesz", "Burial",
        "Björk", "Sigur Rós", "坂本龍一", "Broadcast",
    ]

    private static func peerBatch(peer: Int) -> [SearchResult] {
        // Realistic identities: SoulSeek paths routinely run 150–250
        // characters with unicode, and the row middle-truncates them —
        // which costs a full-string text measurement per row. Short toy
        // paths understate row cost.
        let username = "MusicArchivist_\(["lossless", "vinyl_rips", "shared_library", "collection"][peer % 4])_\(1980 + peer % 45)_\(peer)"
        let artist = artists[peer % artists.count]
        let lossless = peer % 3 != 0
        let ext = lossless ? "flac" : "mp3"
        let year = 1988 + peer % 38
        let edition = lossless
            ? "[FLAC] [\(peer % 2 == 0 ? "16bit-44.1kHz" : "24bit-96kHz")] {\(peer % 2 == 0 ? "Deluxe Remastered Edition" : "Original Press")}"
            : "[MP3 320 CBR] {Web Rip}"
        let folder = "@@shares\\Music Library (sorted by genre)\\Electronic & Experimental\\\(artist)\\\(artist) - Album Number \(peer) — The Extended Anniversary Collection (\(year)) \(edition)"
        let count = Int.random(in: 2...12)
        let free = peer % 5 != 0
        return (1...count).map { track in
            SearchResult(
                username: username,
                filename: "\(folder)\\\(String(format: "%02d", track)) - \(artist) - A Fairly Long Descriptive Track Title (Original Extended Mix) [Explicit] feat. Someone Else.\(ext)",
                size: UInt64.random(in: 3_000_000...60_000_000),
                bitrate: lossless ? UInt32.random(in: 700...1100) : 320,
                duration: UInt32.random(in: 90...600),
                sampleRate: lossless ? 44100 : nil,
                bitDepth: lossless ? 16 : nil,
                isVBR: !lossless && peer % 7 == 0,
                freeSlots: free,
                uploadSpeed: UInt32.random(in: 50_000...8_000_000),
                queueLength: free ? 0 : UInt32.random(in: 1...20),
                isPrivate: peer % 11 == 0
            )
        }
    }

    // MARK: - Auto scroll

    /// Sweeps the results list bottom-to-top-to-bottom continuously by
    /// injecting REAL pixel-unit `scrollWheel` events at ~125Hz into the
    /// scroll view — the genuine wheel-handling path (smooth scrolling,
    /// tracking invalidation), at hard-flick speed (~7500 pt/s), and
    /// visibly fast on screen. Driving the clip view directly or posting
    /// per-event XCUI scrolls both understate real scrolling.
    private static func runAutoScroll() async {
        try? await Task.sleep(for: .seconds(3))
        var goingDown = true
        // Wheel polarity differs across system scroll settings; if events
        // stop moving the list mid-range, flip the sign.
        var sign: CGFloat = 1
        var lastY: CGFloat = -1
        var stuckTicks = 0
        // Proof of motion: total distance traveled per report window. A
        // stationary list produces clean pacer numbers that mean nothing.
        var traveled: CGFloat = 0
        var lastTravelReport = ContinuousClock.now
        var lastTick = ContinuousClock.now
        while true {
            try? await Task.sleep(for: .milliseconds(8))
            if ContinuousClock.now - lastTravelReport > .seconds(5) {
                let windows = NSApp.windows.count
                let sv = resultsScrollView()
                let docH = Int(sv?.documentView?.frame.height ?? -1)
                let cap = ProcessInfo.processInfo.environment["SEELE_SCROLL_RANGE"] ?? "none"
                synthLog("TRAVEL: \(Int(traveled)) pt in 5s (y=\(Int(lastY)), windows=\(windows), scrollView=\(sv != nil), docH=\(docH), cap=\(cap))")
                traveled = 0
                lastTravelReport = .now
            }
            guard let scrollView = resultsScrollView(),
                  let doc = scrollView.documentView else { continue }
            let clip = scrollView.contentView
            // SEELE_SCROLL_RANGE caps how deep the sweep goes — for
            // measuring how cost scales with materialized-row count.
            let rangeCap = ProcessInfo.processInfo.environment["SEELE_SCROLL_RANGE"]
                .flatMap(Double.init).map { CGFloat($0) } ?? .infinity
            let maxY = min(rangeCap, max(0, doc.frame.height - clip.bounds.height))
            guard maxY > 0 else { continue }
            let y = clip.bounds.origin.y
            if goingDown && y >= maxY - 1 { goingDown = false }
            if !goingDown && y <= 1 { goingDown = true }
            if abs(y - lastY) < 0.5 { stuckTicks += 1 } else { stuckTicks = 0 }
            if lastY >= 0 { traveled += abs(y - lastY) }
            lastY = y
            if stuckTicks > 30, y > 1, y < maxY - 1 {
                sign = -sign
                stuckTicks = 0
                synthLog("SYNTH: wheel polarity flipped")
            }
            // Constant-VELOCITY scrolling: scale each event's delta by the
            // actual elapsed time, so a busy main thread gets fewer but
            // larger events and every run sweeps at the same pt/s. The
            // earlier fixed-delta-per-iteration form scrolled faster when
            // the main thread was freer, which made CPU comparisons
            // between builds meaningless (faster sweep = more work/s).
            let targetSpeed: CGFloat = 3000  // pt/s
            let now2 = ContinuousClock.now
            let dt = min(0.1, Double((now2 - lastTick).components.attoseconds) / 1e18
                + Double((now2 - lastTick).components.seconds))
            lastTick = now2
            let magnitude = min(300, targetSpeed * CGFloat(dt))
            let delta = Int32((sign * (goingDown ? -magnitude : magnitude)).rounded())
            guard let cg = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: delta,
                wheel2: 0,
                wheel3: 0
            ), let event = NSEvent(cgEvent: cg) else { continue }
            scrollView.scrollWheel(with: event)
        }
    }

    /// The scroll view with the tallest DOCUMENT across all windows —
    /// with 500 results the list document is tens of thousands of points,
    /// while every other scroll view (sidebar, tab strip) is a few
    /// hundred. Picking by scroll-view frame height instead selected one
    /// of those and silently scrolled nothing.
    private static func resultsScrollView() -> NSScrollView? {
        var found: [NSScrollView] = []
        for window in NSApp.windows {
            guard let root = window.contentView else { continue }
            var queue: [NSView] = [root]
            while let view = queue.popLast() {
                if let sv = view as? NSScrollView { found.append(sv) }
                queue.append(contentsOf: view.subviews)
            }
        }
        return found.max {
            ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
        }
    }

    // MARK: - Hang monitor

    /// Main-actor pacer: 8ms ticks, resume gaps bucketed in frames of the
    /// panel the app window is on (`maximumFramesPerSecond`: 120 on
    /// ProMotion). A fixed 33ms threshold hid every 120Hz drop — one frame
    /// there is 8.3ms. Buckets: >2 frames dropped, >4 frames visible jank,
    /// >150ms stall. At 60Hz these equal the old 33/66/150ms lines, so
    /// earlier logs stay comparable; `hz=` on each line says which.
    private static func startHangMonitor() {
        Task { @MainActor in
            var last = ContinuousClock.now
            var lastReport = last
            var ticks = 0, dropped = 0, jank = 0, stalls = 0
            var maxGap: Duration = .zero
            var statsPhase = phase
            var hz = displayHz()
            var frame = Duration.seconds(1) / hz
            while true {
                try? await Task.sleep(for: .milliseconds(8))
                let now = ContinuousClock.now
                let gap = now - last
                last = now
                ticks += 1
                if gap > frame * 2 { dropped += 1 }
                if gap > frame * 4 { jank += 1 }
                if gap > .milliseconds(150) { stalls += 1 }
                if gap > maxGap { maxGap = gap }
                if phase != statsPhase || now - lastReport > .seconds(5) {
                    synthLog("PACE[\(statsPhase)]: hz=\(hz) ticks=\(ticks) >2f=\(dropped) >4f=\(jank) >150ms=\(stalls) max=\(maxGap) active=\(NSApp.isActive)")
                    ticks = 0; dropped = 0; jank = 0; stalls = 0; maxGap = .zero
                    statsPhase = phase
                    lastReport = now
                    hz = displayHz()
                    frame = Duration.seconds(1) / hz
                }
            }
        }
    }

    /// A restored window frame can land on a slower external display;
    /// pacing must be measured on the fastest panel (ProMotion = 120Hz).
    /// Delayed: SwiftUI applies the restored frame after the first
    /// appearance, undoing a move made from `.task`.
    private static func moveWindowToFastestScreenAfterRestore() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            moveWindowToFastestScreen()
        }
    }

    private static func moveWindowToFastestScreen() {
        guard let window = NSApp.windows.first,
              let target = NSScreen.screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }),
              window.screen != target else { return }
        let size = window.frame.size
        let visible = target.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        window.setFrame(NSRect(origin: origin, size: size).intersection(visible), display: true)
    }

    private static func displayHz() -> Int {
        let screen = NSApp.keyWindow?.screen ?? NSApp.windows.first?.screen ?? NSScreen.main
        return max(screen?.maximumFramesPerSecond ?? 60, 1)
    }
}
#endif
