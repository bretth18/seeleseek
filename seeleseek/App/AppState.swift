import SwiftUI
import os

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

    // MARK: - Network Client (lazy to avoid creation in previews/default env)
    private var _networkClient: NetworkClient?
    var networkClient: NetworkClient {
        if _networkClient == nil {
            _networkClient = NetworkClient()
            // Set up callbacks when client is first accessed
            searchState.settings = settings
            searchState.setupCallbacks(client: _networkClient!)
            chatState.setupCallbacks(client: _networkClient!)
            browseState.configure(networkClient: _networkClient!)
            socialState.setupCallbacks(client: _networkClient!)
            wishlistState.setupCallbacks(client: _networkClient!)

            // Override search results callback to route wishlist tokens
            let originalSearchCallback = _networkClient!.onSearchResults
            _networkClient!.onSearchResults = { [weak self] token, results in
                guard let self else { return }
                if self.wishlistState.isWishlistToken(token) {
                    self.wishlistState.handleSearchResults(token: token, results: results)
                } else {
                    originalSearchCallback?(token, results)
                }
            }

            downloadManager.configure(networkClient: _networkClient!, transferState: transferState, statisticsState: statisticsState, uploadManager: uploadManager, settings: settings)
            uploadManager.configure(networkClient: _networkClient!, transferState: transferState, shareManager: _networkClient!.shareManager, statisticsState: statisticsState)

            // Wire upload permission checker to SocialState (blocklist + leech detection)
            uploadManager.uploadPermissionChecker = { [weak self] username in
                guard let self else { return true }
                // Request stats so leech detection runs on next QueueUpload
                Task { try? await self.networkClient.getUserStats(username) }
                return self.socialState.shouldAllowUpload(to: username)
            }

            // Leech detection: only check users who are trying to download from us
            _networkClient!.addUserStatsHandler { [weak self] username, _, _, files, dirs in
                guard let self else { return }
                // Only check if this user has queued or active uploads
                let hasQueuedUpload = self.uploadManager.queuedUploads.contains { $0.username == username }
                    || self.uploadManager.activeUploadCount > 0
                if hasQueuedUpload {
                    self.socialState.checkForLeech(username: username, files: files, folders: dirs)
                }
            }

            // Set up admin message callback
            _networkClient!.onAdminMessage = { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    let adminMessage = AdminMessage(message: message)
                    self.adminMessages.append(adminMessage)
                    self.latestAdminMessage = adminMessage
                    self.showAdminMessageAlert = true
                    self.logger.info("Received admin message: \(message)")
                }
            }

            // Wire search response filter from settings
            _networkClient!.searchResponseFilter = { [weak self] in
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
        return _networkClient!
    }

    // MARK: - Download Manager
    let downloadManager = DownloadManager()

    // MARK: - Upload Manager
    let uploadManager = UploadManager()

    // MARK: - Initialization
    init() {
        // Load persisted settings from UserDefaults initially (will migrate to DB)
        settings.load()

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
