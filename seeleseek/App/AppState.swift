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
    case statistics
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
        case .statistics: "statistics"
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
        case .statistics: "Statistics"
        case .networkMonitor: "Network Monitor"
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
        case .statistics: "chart.bar"
        case .networkMonitor: "network"
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
