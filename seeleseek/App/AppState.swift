import SwiftUI

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
        // Load persisted settings
        settings.load()
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
