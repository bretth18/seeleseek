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
            searchState.setupCallbacks(client: _networkClient!)
            chatState.setupCallbacks(client: _networkClient!)
            browseState.configure(networkClient: _networkClient!)
            downloadManager.configure(networkClient: _networkClient!, transferState: transferState, statisticsState: statisticsState)
            uploadManager.configure(networkClient: _networkClient!, transferState: transferState, shareManager: _networkClient!.shareManager, statisticsState: statisticsState)
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
    case transfers
    case chat
    case browse
    case user(String)
    case room(String)
    case statistics
    case networkMonitor
    case settings

    var id: String {
        switch self {
        case .search: "search"
        case .transfers: "transfers"
        case .chat: "chat"
        case .browse: "browse"
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
        case .transfers: "Transfers"
        case .chat: "Chat"
        case .browse: "Browse"
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
        case .transfers: "arrow.up.arrow.down"
        case .chat: "bubble.left.and.bubble.right"
        case .browse: "folder"
        case .user: "person"
        case .room: "person.3"
        case .statistics: "chart.bar"
        case .networkMonitor: "network"
        case .settings: "gear"
        }
    }
}

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var appState = AppState()
}
