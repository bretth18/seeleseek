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

    private func wireNetworkClient(_ client: NetworkClient) {
        searchState.settings = settings
        searchState.setupCallbacks(client: client)
        chatState.setupCallbacks(client: client)
        browseState.configure(networkClient: client)
        socialState.setupCallbacks(client: client)
        wishlistState.setupCallbacks(client: client)

        // Route wishlist tokens before falling through to regular search results.
        let originalSearchCallback = client.onSearchResults
        client.onSearchResults = { [weak self] token, results in
            guard let self else { return }
            let isWishlist = self.wishlistState.isWishlistToken(token)
            self.logger.info("Search results routing: token=\(String(format: "0x%08X", token)) results=\(results.count) isWishlist=\(isWishlist)")
            if isWishlist {
                self.wishlistState.handleSearchResults(token: token, results: results)
            } else {
                originalSearchCallback?(token, results)
            }
        }

        let metadataReader = MetadataReader()
        client.metadataReader = metadataReader
        downloadManager.configure(networkClient: client, transferState: transferState, statisticsState: statisticsState, uploadManager: uploadManager, settings: settings, metadataReader: metadataReader)
        uploadManager.configure(networkClient: client, transferState: transferState, shareManager: client.shareManager, statisticsState: statisticsState)

        // Peer-status watcher — SocialState tracks live online/away/offline
        // state for any peer currently in the transfer list (not just
        // buddies), so rows can surface offline state even for strangers.
        transferState.peerWatcher = socialState

        // Cancel any pending retry Task when the user takes a transfer out
        // of a retriable state (cancel, remove, manual retry, clear failed).
        // Without this the retry Task sleeps up to 30 min before self-skipping
        // via its status guard.
        transferState.onDownloadTerminated = { [weak self] transferId in
            self?.downloadManager.cancelRetry(transferId: transferId)
        }

        uploadManager.uploadPermissionChecker = { [weak self] username in
            guard let self else { return true }
            let patterns = self.settings.activeBlockedPatterns
            if !patterns.isEmpty,
               UsernamePatternMatcher.matches(username, anyOfCompiled: patterns) {
                return false
            }
            Task { try? await self.networkClient.getUserStats(username) }
            return self.socialState.shouldAllowUpload(to: username)
        }

        client.peerConnectionPool.peerPermissionChecker = { [weak self] username in
            guard let self else { return true }
            let patterns = self.settings.activeBlockedPatterns
            guard !patterns.isEmpty else { return true }
            return !UsernamePatternMatcher.matches(username, anyOfCompiled: patterns)
        }

        // Core asks "is this requester a buddy?" when responding to
        // shares / distributed search so it can gate buddy-only folders.
        // Case-insensitive match mirrors `SocialState.isIgnored`.
        client.isBuddyChecker = { [weak self] username in
            guard let self else { return false }
            let lower = username.lowercased()
            return self.socialState.buddies.contains { $0.username.lowercased() == lower }
        }

        client.addUserStatsHandler { [weak self] username, _, _, files, dirs in
            guard let self else { return }
            let hasQueuedUpload = self.uploadManager.queuedUploads.contains { $0.username == username }
                || self.uploadManager.activeUploadCount > 0
            if hasQueuedUpload {
                self.socialState.checkForLeech(username: username, files: files, folders: dirs)
            }
        }

        client.onAdminMessage = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                let adminMessage = AdminMessage(message: message)
                self.adminMessages.append(adminMessage)
                self.latestAdminMessage = adminMessage
                self.showAdminMessageAlert = true
                self.logger.info("Received admin message: \(message)")
            }
        }

        // Folder-download response handler: a search-row right-click → "Download
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
        client.onFolderContentsResponse = { [weak self] token, folder, files in
            guard let self,
                  let username = self.pendingFolderDownloads.removeValue(forKey: token) else {
                return
            }
            let queued = self.queueFolderDownload(files: files, from: username, folder: folder)
            self.logger.info("Folder download from \(username) in '\(folder)': queued \(queued)/\(files.count) files")
        }

        client.searchResponseFilter = { [weak self] in
            guard let settings = self?.settings else {
                return (enabled: true, minQueryLength: 3, maxResults: 50)
            }
            return (
                enabled: settings.respondToSearches,
                minQueryLength: settings.minSearchQueryLength,
                maxResults: settings.maxSearchResponseResults
            )
        }
    }

    // MARK: - Folder Download Coordinator
    // Maps the token returned by `requestFolderContents` to the username we
    // asked — response events only carry `(token, folder, files)`, so we
    // need this side-table to know where to queue the downloads.
    private var pendingFolderDownloads: [UInt32: String] = [:]

    /// Right-click "Download entire folder" entrypoint for a search result.
    /// Derives the containing folder from the Soulseek path (backslash-
    /// separated), asks the peer for its contents, and queues every returned
    /// file once the response arrives. Pending tokens are auto-cleaned after
    /// 60 s if the peer never responds, so `pendingFolderDownloads` can't grow
    /// unbounded. No ActivityLog entries — folder downloads surface through
    /// the same Transfers-tab path as single-file downloads, matching the
    /// app's "log on completion, not on intent" convention.
    func downloadContainingFolder(of result: SearchResult) async {
        let folder = Self.containingSoulseekFolder(of: result.filename)
        guard !folder.isEmpty else {
            logger.warning("Could not derive containing folder from filename: \(result.filename)")
            return
        }
        do {
            let token = try await networkClient.requestFolderContents(
                from: result.username,
                folder: folder
            )
            pendingFolderDownloads[token] = result.username
            logger.info("Requested folder contents '\(folder)' from \(result.username) (token=\(token))")
            scheduleFolderDownloadTimeout(token: token, username: result.username, folder: folder)
        } catch {
            logger.error("Failed to request folder contents: \(error.localizedDescription)")
        }
    }

    /// Drop the pending entry after 60 s if the peer never replied. No-op
    /// if the response already arrived and removed it.
    private func scheduleFolderDownloadTimeout(token: UInt32, username: String, folder: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self,
                  self.pendingFolderDownloads.removeValue(forKey: token) != nil else {
                return
            }
            self.logger.info("Folder contents request timed out: \(username) '\(folder)' (token=\(token))")
        }
    }

    /// Queue every file from a folder-contents response, skipping files
    /// already queued for this user. Returns the number actually queued.
    ///
    /// `folder` is the full Soulseek folder path the peer listed (as it
    /// appeared in `FolderContentsReply`). Some peers embed the full path
    /// in each file's `filename`; others send only basenames. If we just
    /// forward the basename, the peer's subsequent QueueUpload lookup fails
    /// with `File not shared` (they key their share index by full path).
    /// We detect the basename-only case and prepend `folder` so the queued
    /// SearchResult carries the path the peer expects.
    private func queueFolderDownload(files: [SharedFile], from username: String, folder: String) -> Int {
        var queued = 0
        for file in files {
            let fullPath = Self.fullSoulseekPath(folder: folder, filename: file.filename)
            if transferState.isFileQueued(filename: fullPath, username: username) { continue }
            let result = SearchResult(
                username: username,
                filename: fullPath,
                size: file.size,
                bitrate: file.bitrate,
                duration: file.duration,
                isVBR: false,
                freeSlots: true,
                uploadSpeed: 0,
                queueLength: 0
            )
            downloadManager.queueDownload(from: result)
            queued += 1
        }
        return queued
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

        // Sync launch-at-login state from system (user may toggle in System Settings)
        settings.syncLaunchAtLoginState()

        // Register activity logger with the package
        ActivityLogger.shared = ActivityLog.shared

        // Configure notifications
        NotificationService.shared.settings = settings
        NotificationService.shared.requestAuthorization()

        // Initialize database asynchronously
        Task {
            await initializeDatabase()
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

        // Load resumable transfers
        await transferState.loadPersisted()

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
