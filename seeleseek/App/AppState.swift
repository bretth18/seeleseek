import SwiftUI
import os
import SeeleseekCore

@Observable
@MainActor
final class AppState {
    // MARK: - Feature States
    var connection = ConnectionState()
    var searchState = SearchState()
    var chatState = ChatState()
    var settings = SettingsState()
    var transferState = TransferState()
    var statisticsState = StatisticsState()
    var browseState = BrowseState()
    var metadataState = MetadataState()
    var socialState = SocialState()
    var wishlistState = WishlistState()
    var updateState = UpdateState()

    // MARK: - Admin Messages
    var adminMessages: [AdminMessage] = []
    var showAdminMessageAlert = false
    var latestAdminMessage: AdminMessage?

    // MARK: - Navigation
    var selectedTab: NavigationTab = .search
    var sidebarSelection: SidebarItem? = .search
    /// Set by ⌘F; SearchView consumes it once the field is on screen.
    var searchFieldFocusPending = false

    func requestSearchFieldFocus() {
        sidebarSelection = .search
        searchFieldFocusPending = true
    }

    // MARK: - Availability

    /// Advertise availability to the server. `.offline` is not offered — the
    /// protocol reserves it for actually leaving, which is what disconnect
    /// does.
    func setOnlineStatus(_ status: UserStatus) {
        guard status != connection.onlineStatus else { return }
        connection.onlineStatus = status
        Task { [weak self] in
            guard let self else { return }
            try? await self.networkClient.setStatus(status)
        }
    }

    /// Re-send `.away` after a reconnect; the login sequence hardcodes
    /// `.online`, so without this the flag is quietly lost.
    private func reapplyOnlineStatusIfAway() {
        guard connection.onlineStatus == .away else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await self.networkClient.setStatus(.away)
        }
    }

    // MARK: - Database State
    var isDatabaseReady = false
    private let logger = Logger(subsystem: "com.seeleseek", category: "AppState")

    // MARK: - Network Client
    // Lazy to avoid creation in previews / default environment values, but the
    // wiring itself lives in wireNetworkClient() so it isn't buried inside the
    // accessor and can't be partially executed under early concurrent access.
    private var _networkClient: NetworkClient?
    var networkClient: NetworkClient {
        if let client = _networkClient { return client }
        let client = NetworkClient()
        _networkClient = client
        wireNetworkClient(client)
        return client
    }

    @ObservationIgnored private var connectionEventsTask: Task<Void, Never>?
    @ObservationIgnored private var searchEventsTask: Task<Void, Never>?
    @ObservationIgnored private var socialEventsTask: Task<Void, Never>?

    private func wireNetworkClient(_ client: NetworkClient) {
        // App-wide connection lifecycle handling, subscribed exactly once
        // (not per Connect tap). One serial consumer per domain — status
        // transitions must never reorder.
        connectionEventsTask?.cancel()
        let connectionEvents = client.events.connection.subscribe()
        connectionEventsTask = Task { [weak self] in
            for await event in connectionEvents {
                guard let self else { return }
                self.handle(event)
            }
        }

        searchState.wireNetworkEvents(client: client)
        chatState.wireNetworkEvents(client: client)
        browseState.configure(networkClient: client)
        socialState.wireNetworkEvents(client: client)
        wishlistState.wireNetworkEvents(client: client)

        // Single search-domain consumer: routes wishlist tokens to
        // WishlistState, everything else into SearchState's coalescing
        // buffer. Bounded: live searches can deliver hundreds of result batches/sec
        // across peers; if the main actor stalls, overflow past 1024 queued
        // batches is tail-dropped rather than growing without limit.
        searchEventsTask?.cancel()
        let searchEvents = client.events.search.subscribe(bufferingPolicy: .bufferingOldest(1024))
        searchEventsTask = Task { [weak self] in
            for await event in searchEvents {
                guard let self else { return }
                self.handle(event)
            }
        }

        // Bounded: status/stats storms from large buddy lists are the hot
        // case; tail-drop past 1024 queued events instead of growing.
        socialEventsTask?.cancel()
        let socialEvents = client.events.social.subscribe(bufferingPolicy: .bufferingOldest(1024))
        socialEventsTask = Task { [weak self] in
            for await event in socialEvents {
                guard let self else { return }
                self.handle(event)
            }
        }

        let metadataReader = MetadataReader()
        Task { await client.setMetadataReader(metadataReader) }
        let downloadManager = downloadManager
        let downloadSettings = DownloadSettingsSnapshot(from: settings)
        Task {
            await downloadManager.configure(networkClient: client, transferState: self.transferState, statisticsState: self.statisticsState, uploadManager: self.uploadManager, settings: downloadSettings, metadataReader: metadataReader)
        }
        // Keep the manager's settings snapshot current — the actor reads
        // pushed values instead of pulling from SettingsState per path
        // computation.
        settings.onDownloadSettingsChange = { [weak self, weak downloadManager] in
            guard let self, let downloadManager else { return }
            let snapshot = DownloadSettingsSnapshot(from: self.settings)
            Task { await downloadManager.updateSettings(snapshot) }
        }
        let uploadManager = uploadManager
        Task {
            await uploadManager.configure(networkClient: client, transferState: transferState, shareManager: client.shareManager, statisticsState: statisticsState)
            // Push the settings stepper's value into UploadManager and keep
            // them in sync as the user changes it.
            await uploadManager.setMaxConcurrentUploads(self.settings.maxUploadSlots)
            // Same wiring for the upload speed limit (KB/s, 0 = unlimited).
            await uploadManager.setUploadSpeedLimit(kbPerSecond: self.settings.uploadSpeedLimit)
        }
        settings.onMaxUploadSlotsChange = { [weak uploadManager] newValue in
            Task { await uploadManager?.setMaxConcurrentUploads(newValue) }
        }
        settings.onUploadSpeedLimitChange = { [weak uploadManager] newValue in
            Task { await uploadManager?.setUploadSpeedLimit(kbPerSecond: newValue) }
        }

        // Peer-status watcher — SocialState tracks live online/away/offline
        // state for any peer currently in the transfer list (not just
        // buddies), so rows can surface offline state even for strangers.
        transferState.peerWatcher = socialState

        // Cancel any pending retry Task when the user takes a transfer out
        // of a retriable state (cancel, remove, manual retry, clear failed).
        // Without this the retry Task sleeps up to 30 min before self-skipping
        // via its status guard. Both managers maintain their own retry table
        // — same callback fans out to both since `transferId` is unique
        // across directions and the lookup is a no-op when there's no
        // pending entry.
        transferState.onDownloadTerminated = { [weak self] transferId in
            Task { [weak self] in
                await self?.downloadManager.cancelRetry(transferId: transferId)
                await self?.uploadManager.cancelRetry(transferId: transferId)
            }
        }

        // Cancel/remove must stop the actual network work, not just flip the
        // row status — without this a "cancelled" transfer keeps streaming
        // and the completion path flips it back to .completed.
        transferState.onCancelRequested = { [weak self] transferId, isDownload in
            guard let self else { return }
            // Route by direction: cancelDownload on an upload id would stamp
            // the row .cancelled in the wrong manager's bookkeeping.
            if isDownload {
                Task { await self.downloadManager.cancelDownload(transferId: transferId) }
            } else {
                Task { await self.uploadManager.cancelUpload(transferId: transferId) }
            }
        }

        Task { [uploadManager] in
            await uploadManager.setUploadPermissionChecker { [weak self] username in
                guard let self else { return true }
                let patterns = self.settings.activeBlockedPatterns
                if !patterns.isEmpty,
                   UsernamePatternMatcher.matches(username, anyOfCompiled: patterns) {
                    return false
                }
                Task { try? await self.networkClient.getUserStats(username) }
                return self.socialState.shouldAllowUpload(to: username)
            }
        }

        // Push the compiled username block patterns into the pool and keep
        // them in sync; the pool evaluates them on its per-connection hot
        // path.
        let initialPatterns = settings.activeBlockedPatterns
        Task { await client.peerConnectionPool.updateBlockedUsernamePatterns(initialPatterns) }
        settings.onActiveBlockedPatternsChange = { [weak client] patterns in
            Task { await client?.peerConnectionPool.updateBlockedUsernamePatterns(patterns) }
        }

        // Push the search-response policy and keep it in sync — the
        // distributed-search handler reads it at relay rates.
        let initialPolicy = settings.searchResponsePolicy
        Task { await client.updateSearchResponsePolicy(initialPolicy) }
        settings.onSearchResponsePolicyChange = { [weak client] policy in
            Task { await client?.updateSearchResponsePolicy(policy) }
        }
    }

    // MARK: - Network Event Handling

    private func handle(_ event: ConnectionEvent) {
        switch event {
        case .statusChanged(let status):
            switch status {
            case .connected:
                if connection.rememberCredentials {
                    CredentialStorage.save(
                        username: connection.loginUsername,
                        password: connection.loginPassword
                    )
                }
                connection.setConnected(
                    username: connection.loginUsername,
                    ip: "",
                    greeting: nil
                )
                // Resume all retriable downloads from previous session
                Task { await self.downloadManager.resumeDownloadsOnConnect() }
                // Same on the upload side: persisted `.failed` rows
                // whose error is retriable get a fresh 4-attempt budget.
                Task { await self.uploadManager.resumeUploadsOnConnect() }
                // Re-send peer-status watches (earlier attempts made
                // during the connecting phase may have been dropped).
                socialState.resubscribeWatchedPeers()
                // The server wipes buddy watches and interests on every
                // disconnect. Restore them on each connect
                socialState.resubscribeOnConnect()
                reapplyOnlineStatusIfAway()
            case .disconnected:
                connection.setDisconnected()
            case .connecting:
                connection.setConnecting()
            case .reconnecting:
                connection.setReconnecting(reason: networkClient.status.connectionError)
            case .error:
                connection.setError(networkClient.status.connectionError ?? "Unknown error")
            }
        case .protocolNotice:
            break
        }
    }

    private func handle(_ event: SearchEvent) {
        switch event {
        case .results(let token, let results):
            // Route wishlist tokens before falling through to regular
            // search results.
            let isWishlist = wishlistState.isWishlistToken(token)
            logger.info("Search results routing: token=\(String(format: "0x%08X", token)) results=\(results.count) isWishlist=\(isWishlist)")
            if isWishlist {
                wishlistState.handleSearchResults(token: token, results: results)
            } else {
                searchState.addResults(results, forToken: token)
            }
        case .wishlistInterval(let seconds):
            wishlistState.handleWishlistInterval(seconds)
        case .folderContentsResponse(let token, let folder, let files):
            handleFolderContentsResponse(token: token, folder: folder, files: files)
        case .excludedPhrases:
            break
        }
    }

    private func handle(_ event: SocialEvent) {
        switch event {
        case .userStats(let username, _, _, let files, let dirs):
            let hasQueuedUpload = uploadManager.state.queuedUploads.contains { $0.username == username }
                || uploadManager.state.activeUploadCount > 0
            if hasQueuedUpload {
                socialState.checkForLeech(username: username, files: files, folders: dirs)
            }
        case .adminMessage(let message):
            let adminMessage = AdminMessage(message: message)
            adminMessages.append(adminMessage)
            latestAdminMessage = adminMessage
            showAdminMessageAlert = true
            logger.info("Received admin message: \(message)")
        default:
            break
        }
    }

    // Folder-download response: a search-row right-click → "Download
    // entire folder" triggers `requestFolderContents`, which eventually
    // lands here with the file list. Match by token to the username that
    // initiated the request and queue every file. No ActivityLog entry —
    // individual downloads surface in the Transfers tab and will emit
    // their own logDownloadCompleted when they finish, matching the
    // single-file download path.
    //
    // The `folder` argument is passed into `queueFolderDownload` because
    // some peers (e.g. vanilla Nicotine+) send full paths as each file's
    // `filename`, while others (seen in the wild) send only basenames.
    // The queue path uses `folder` to reconstruct the full Soulseek path
    // when the peer sent a basename — otherwise the QueueUpload request
    // we later send to them comes back `File not shared`.
    private func handleFolderContentsResponse(token: UInt32, folder: String, files: [SharedFile]) {
        guard let pending = pendingFolderDownloads.removeValue(forKey: token) else {
            return
        }
        let username = pending.username
        if files.isEmpty {
            markFolderRequestFailed(pending, reason: "\(username) shared no files in this folder")
            ActivityLog.shared.logFolderRequestFailed(
                username: username, folder: folder,
                reason: "\(username) shared no files in this folder"
            )
            return
        }
        clearFolderRequestState(pending)
        let queued = self.queueFolderDownload(files: files, from: username, folder: folder)
        logger.info("Folder download from \(username) in '\(folder)': queued \(queued)/\(files.count) files")
        ActivityLog.shared.logFolderQueued(count: queued, username: username, folder: folder)
    }

    // MARK: - Folder Download Coordinator
    struct FolderRequest: Hashable {
        let username: String
        let folder: String
    }
    private var pendingFolderDownloads: [UInt32: FolderRequest] = [:]

    enum FolderRequestState: Equatable {
        case fetching
        case failed(String)
    }

    private(set) var folderRequestStates: [FolderRequest: FolderRequestState] = [:]
    private var folderFailureClearTasks: [FolderRequest: Task<Void, Never>] = [:]

    func folderRequestState(for result: SearchResult) -> FolderRequestState? {
        // Every visible row calls this on every render — skip the path parse.
        guard !folderRequestStates.isEmpty else { return nil }
        let folder = Self.containingSoulseekFolder(of: result.filename)
        guard !folder.isEmpty else { return nil }
        return folderRequestStates[FolderRequest(username: result.username, folder: folder)]
    }

    #if DEBUG
    func previewSeedFolderRequest(_ state: FolderRequestState, for result: SearchResult) {
        let folder = Self.containingSoulseekFolder(of: result.filename)
        folderRequestStates[FolderRequest(username: result.username, folder: folder)] = state
    }
    #endif

    private func clearFolderRequestState(_ request: FolderRequest) {
        folderFailureClearTasks.removeValue(forKey: request)?.cancel()
        folderRequestStates.removeValue(forKey: request)
    }

    /// Cancel-and-replace: without it, an older failure's 30 s timer can
    /// clear a newer failure for the same folder early.
    private func markFolderRequestFailed(_ request: FolderRequest, reason: String) {
        folderRequestStates[request] = .failed(reason)
        folderFailureClearTasks[request]?.cancel()
        folderFailureClearTasks[request] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.folderFailureClearTasks.removeValue(forKey: request)
            if case .failed = self.folderRequestStates[request] {
                self.folderRequestStates.removeValue(forKey: request)
            }
        }
    }

    /// Right-click "Download entire folder" entrypoint for a search result.
    /// Derives the containing folder from the Soulseek path (backslash-
    /// separated), asks the peer for its contents, and queues every returned
    /// file once the response arrives.
    func downloadContainingFolder(of result: SearchResult) async {
        let folder = Self.containingSoulseekFolder(of: result.filename)
        guard !folder.isEmpty else {
            logger.warning("Could not derive containing folder from filename: \(result.filename)")
            return
        }
        let request = FolderRequest(username: result.username, folder: folder)
        guard folderRequestStates[request] != .fetching else { return }
        folderRequestStates[request] = .fetching
        let started = Date()
        logger.info("Folder download clicked: \(result.username) '\(folder)'")
        ActivityLog.shared.logFolderRequestStarted(username: result.username, folder: folder)
        do {
            let token = try await networkClient.requestFolderContents(
                from: result.username,
                folder: folder
            )
            pendingFolderDownloads[token] = request
            logger.info("Requested folder contents '\(folder)' from \(result.username) (token=\(token)) after \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            scheduleFolderDownloadTimeout(token: token, request: request)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started))
            let reason = networkClient.status.isConnected
                ? "Could not reach \(result.username) after \(elapsed) seconds"
                : "Not connected to the Soulseek server"
            markFolderRequestFailed(request, reason: reason)
            logger.error("Failed to request folder contents after \(elapsed) s: \(error.localizedDescription)")
            ActivityLog.shared.logFolderRequestFailed(
                username: result.username, folder: folder, reason: reason
            )
        }
    }

    /// Warn at 60 s but keep the entry for 5 more minutes: firewalled
    /// peers can need 45 s before the request is even sent, and those
    /// late replies must still queue.
    private func scheduleFolderDownloadTimeout(token: UInt32, request: FolderRequest) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, self.pendingFolderDownloads[token] != nil else { return }
            let (username, folder) = (request.username, request.folder)
            let reason = "\(username) did not answer within 60 seconds"
            self.markFolderRequestFailed(request, reason: reason)
            self.logger.info("Folder contents request slow: \(username) '\(folder)' (token=\(token))")
            ActivityLog.shared.logFolderRequestFailed(
                username: username, folder: folder, reason: reason
            )

            try? await Task.sleep(for: .seconds(300))
            if self.pendingFolderDownloads.removeValue(forKey: token) != nil {
                self.logger.info("Folder contents request expired: \(username) '\(folder)' (token=\(token))")
            }
        }
    }

    /// Queue every file from a folder-contents response. Returns the number
    /// handed to the download manager. Do not pre-filter queued files here:
    /// `queueDownload` skips active duplicates and re-drives failed rows.
    ///
    /// `folder` is the full Soulseek folder path the peer listed (as it
    /// appeared in `FolderContentsReply`). Some peers embed the full path
    /// in each file's `filename`; others send only basenames. If we just
    /// forward the basename, the peer's subsequent QueueUpload lookup fails
    /// with `File not shared` (they key their share index by full path).
    /// We detect the basename-only case and prepend `folder` so the queued
    /// SearchResult carries the path the peer expects.
    private func queueFolderDownload(files: [SharedFile], from username: String, folder: String) -> Int {
        let results = files.map { file in
            SearchResult(
                username: username,
                filename: Self.fullSoulseekPath(folder: folder, filename: file.filename),
                size: file.size,
                bitrate: file.bitrate,
                duration: file.duration,
                isVBR: false,
                freeSlots: true,
                uploadSpeed: 0,
                queueLength: 0
            )
        }
        // One Task for the whole batch so files queue in folder order —
        // a Task per file would race and scramble queue positions.
        let downloadManager = downloadManager
        Task {
            for result in results {
                await downloadManager.queueDownload(from: result)
            }
        }
        return results.count
    }

    /// Combine `folder` and `filename` into a full Soulseek path, detecting
    /// whether the peer already embedded the full path in `filename`. Heuristic:
    /// if `filename` contains a backslash, trust it verbatim (either a full
    /// path or a nested sub-path both of which the peer indexes directly);
    /// otherwise prepend `folder` and the backslash separator. Empty `folder`
    /// falls through to the bare filename — defensive; the caller already
    /// guards against the empty-folder case upstream.
    private static func fullSoulseekPath(folder: String, filename: String) -> String {
        if filename.contains("\\") || folder.isEmpty {
            return filename
        }
        let separator = folder.hasSuffix("\\") ? "" : "\\"
        return "\(folder)\(separator)\(filename)"
    }

    /// Soulseek paths use backslash separators — e.g.
    /// `@@hddmusic\Music\Artist\Album\01 - Track.flac`. Returns the path
    /// with the trailing component dropped, or empty if there isn't one.
    private static func containingSoulseekFolder(of filename: String) -> String {
        let components = filename.components(separatedBy: "\\")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "\\")
    }

    // MARK: - Download Manager
    let downloadManager = DownloadManager()

    // MARK: - Upload Manager
    let uploadManager = UploadManager()

    // MARK: - Audio Preview
    // App-wide so starting playback in one row stops the previous row's
    // preview automatically (no overlapping audio across the list).
    let audioPreview = RowAudioPreview()

    // MARK: - Initialization

    // init() is intentionally lightweight — @Entry and SwiftUI may construct
    // multiple AppState instances.  Heavy side-effects live in configure().
    private var isConfigured = false

    /// One-time setup: load settings, request notifications, init database.
    /// Call exactly once from the App struct's .task modifier.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        // Migrate UserDefaults from sandboxed container if needed (v1.0.5 → v1.0.6)
        migrateUserDefaultsFromContainer()

        // Migrate dotted UserDefaults keys to camelCase (v1.0.11 → v1.0.12).
        // Copies old → new (does not delete) so the legacy DB migration below
        // can still find the old keys for users who never opened pre-DB builds.
        Self.migrateLegacyDottedDefaults()

        // Load persisted settings from UserDefaults initially (will migrate to DB)
        settings.load()
        // Sole wiring point; must follow settings.load() or the search tab
        // starts with empty grouping + filters.
        searchState.settings = settings

        // Sync launch-at-login state from system (user may toggle in System Settings)
        settings.syncLaunchAtLoginState()

        // Register activity logger with the package
        ActivityLogger.shared = ActivityLog.shared

        // Configure notifications
        NotificationService.shared.settings = settings
        NotificationService.shared.requestAuthorization()

        Task {
            await initializeDatabase()
            // Wiring is not inert: wireNetworkEvents loads each feature
            // state's persisted data, so the database must be ready first.
            // Previews and the test host skip configure(), so neither
            // scans the filesystem.
            let client = networkClient
            await client.shareManager.loadPersistedFolders()
            await client.shareManager.rescanAll()
        }
    }

    // MARK: - Database Initialization

    private func initializeDatabase() async {
        do {
            logger.info("Initializing database...")
            try await DatabaseManager.shared.initialize()

            // Migrate from UserDefaults if needed
            await migrateFromUserDefaults()

            // Load persisted state from database
            await loadPersistedState()

            // Clean up expired cache
            try? await DatabaseManager.shared.cleanupExpiredCache()

            isDatabaseReady = true
            logger.info("Database initialization complete")
        } catch {
            logger.error("Database initialization failed: \(error.localizedDescription)")
            // App continues to work with in-memory state
        }
    }

    private func migrateFromUserDefaults() async {
        do {
            guard try await !SettingsRepository.isMigrated() else {
                logger.info("Database already migrated from UserDefaults")
                return
            }

            logger.info("Migrating settings from UserDefaults to database...")

            // Migrate network settings
            let defaults = UserDefaults.standard

            if let port = defaults.object(forKey: "settings.listenPort") as? Int {
                try await SettingsRepository.set("listenPort", value: port)
            }
            if defaults.object(forKey: "settings.enableUPnP") != nil {
                try await SettingsRepository.set("enableUPnP", value: defaults.bool(forKey: "settings.enableUPnP"))
            }
            if let slots = defaults.object(forKey: "settings.maxDownloadSlots") as? Int {
                try await SettingsRepository.set("maxDownloadSlots", value: slots)
            }
            if let slots = defaults.object(forKey: "settings.maxUploadSlots") as? Int {
                try await SettingsRepository.set("maxUploadSlots", value: slots)
            }
            if let limit = defaults.object(forKey: "settings.uploadSpeedLimit") as? Int {
                try await SettingsRepository.set("uploadSpeedLimit", value: limit)
            }
            if let limit = defaults.object(forKey: "settings.downloadSpeedLimit") as? Int {
                try await SettingsRepository.set("downloadSpeedLimit", value: limit)
            }

            try await SettingsRepository.markMigrated()
            logger.info("UserDefaults migration complete")
        } catch {
            logger.error("UserDefaults migration failed: \(error.localizedDescription)")
        }
    }

    /// One-shot rename of legacy dotted UserDefaults keys to camelCase. Copies
    /// values forward; old keys are not deleted so the DB seeder above still
    /// finds them on first launch after the v1.0.5 → v1.0.6 unsandboxing.
    static func migrateLegacyDottedDefaults() {
        let migrationDoneKey = "didMigrateDottedDefaults"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationDoneKey) else { return }

        let pairs: [(old: String, new: String)] = [
            ("settings.listenPort",            "settingsListenPort"),
            ("settings.enableUPnP",            "settingsEnableUPnP"),
            ("settings.maxDownloadSlots",      "settingsMaxDownloadSlots"),
            ("settings.maxUploadSlots",        "settingsMaxUploadSlots"),
            ("settings.uploadSpeedLimit",      "settingsUploadSpeedLimit"),
            ("settings.downloadSpeedLimit",    "settingsDownloadSpeedLimit"),
            ("settings.maxSearchResults",      "settingsMaxSearchResults"),
            ("settings.downloadLocation",      "settingsDownloadLocation"),
            ("settings.incompleteLocation",    "settingsIncompleteLocation"),
            ("settings.downloadFolderFormat",  "settingsDownloadFolderFormat"),
            ("settings.downloadFolderTemplate","settingsDownloadFolderTemplate"),
            ("settings.launchAtLogin",         "settingsLaunchAtLogin"),
            ("settings.showInMenuBar",         "settingsShowInMenuBar"),
            ("settings.notifyDownloads",       "settingsNotifyDownloads"),
            ("settings.notifyUploads",         "settingsNotifyUploads"),
            ("settings.notifyPrivateMessages", "settingsNotifyPrivateMessages"),
            ("settings.notifyWishlist",        "settingsNotifyWishlist"),
            ("settings.notifyOnlyInBackground","settingsNotifyOnlyInBackground"),
            ("settings.notificationSoundName", "settingsNotificationSoundName"),
            ("update.lastCheckDate",           "updateLastCheckDate"),
            ("update.autoCheckEnabled",        "updateAutoCheckEnabled"),
            ("update.skippedVersion",          "updateSkippedVersion")
        ]
        for (old, new) in pairs where defaults.object(forKey: new) == nil {
            if let value = defaults.object(forKey: old) {
                defaults.set(value, forKey: new)
            }
        }
        defaults.set(true, forKey: migrationDoneKey)
    }

    /// Migrate UserDefaults from the sandboxed container plist to the standard location.
    /// When moving from sandboxed (v1.0.5) to unsandboxed (v1.0.6), UserDefaults reads
    /// from a different plist file. This copies essential keys if they're missing.
    private func migrateUserDefaultsFromContainer() {
        let defaults = UserDefaults.standard
        let migrationKey = "containerPlistMigrated"

        guard !defaults.bool(forKey: migrationKey) else { return }

        let containerPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/computerdata.seeleseek/Data/Library/Preferences/computerdata.seeleseek.plist")

        guard let containerDefaults = NSDictionary(contentsOf: containerPlist) as? [String: Any] else {
            // No container plist found — either fresh install or already unsandboxed
            defaults.set(true, forKey: migrationKey)
            return
        }

        logger.info("Migrating UserDefaults from sandboxed container...")

        // Copy keys that aren't already set in the current defaults
        let keysToMigrate = containerDefaults.keys.filter { key in
            // Skip Apple/system keys and window frame data
            !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple")
        }

        var migratedCount = 0
        for key in keysToMigrate {
            if defaults.object(forKey: key) == nil, let value = containerDefaults[key] {
                defaults.set(value, forKey: key)
                migratedCount += 1
            }
        }

        defaults.set(true, forKey: migrationKey)
        logger.info("Migrated \(migratedCount) UserDefaults keys from sandboxed container")
    }

    private func loadPersistedState() async {
        // Load settings from database
        await settings.loadFromDatabase()

        // `loadFromDatabase` sets `isLoading = true`, so the `didSet` hooks
        // that normally push maxUploadSlots / uploadSpeedLimit to
        // UploadManager are suppressed. Re-apply after the load completes.
        await uploadManager.setMaxConcurrentUploads(settings.maxUploadSlots)
        await uploadManager.setUploadSpeedLimit(kbPerSecond: settings.uploadSpeedLimit)

        // Load resumable transfers
        await transferState.loadPersisted()

        // Rearm any retry timers that were mid-backoff when the app last
        // quit. Without this, a row scheduled to retry in 28 minutes but
        // interrupted by a quit just sits at `.failed` forever — the
        // in-memory `Task` died with the process. Past-due rows fire
        // immediately with a small stagger; future rows reschedule with
        // the remaining delay. Must run after `loadPersisted` so the
        // managers can read `transferState.downloads`/`.uploads`.
        await downloadManager.rearmPersistedRetries()
        await uploadManager.rearmPersistedRetries()

        // Load wishlist items
        await wishlistState.loadFromDatabase()

        // Check for updates on launch
        updateState.checkOnLaunch()

        logger.info("Persisted state loaded")
    }
}

// MARK: - Navigation Types

enum NavigationTab: String, CaseIterable, Identifiable {
    case search
    case transfers
    case chat
    case browse
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Search"
        case .transfers: "Transfers"
        case .chat: "Chat"
        case .browse: "Browse"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .transfers: "arrow.down.arrow.up"
        case .chat: "bubble.left.and.bubble.right"
        case .browse: "folder"
        case .settings: "gear"
        }
    }
}

enum SidebarItem: Hashable, Identifiable {
    case search
    case wishlists
    case transfers
    case chat
    case browse
    case social
    case user(String)
    case room(String)
    case networkMonitor
    case settings

    var id: String {
        switch self {
        case .search: "search"
        case .wishlists: "wishlists"
        case .transfers: "transfers"
        case .chat: "chat"
        case .browse: "browse"
        case .social: "social"
        case .user(let name): "user-\(name)"
        case .room(let name): "room-\(name)"
        case .networkMonitor: "networkMonitor"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .search: "Search"
        case .wishlists: "Wishlists"
        case .transfers: "Transfers"
        case .chat: "Chat"
        case .browse: "Browse"
        case .social: "Friends"
        case .user(let name): name
        case .room(let name): name
        case .networkMonitor: "Activity"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .wishlists: "star"
        case .transfers: "arrow.up.arrow.down"
        case .chat: "bubble.left.and.bubble.right"
        case .browse: "folder"
        case .social: "person.2"
        case .user: "person"
        case .room: "person.3"
        case .networkMonitor: "waveform.path.ecg"
        case .settings: "gear"
        }
    }
}

// MARK: - Admin Message

struct AdminMessage: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date

    init(message: String) {
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var appState = AppState()
}
