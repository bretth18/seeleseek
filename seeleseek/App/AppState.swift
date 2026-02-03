import SwiftUI

@Observable
@MainActor
final class AppState {
    // MARK: - Feature States
    var connection = ConnectionState()

    // MARK: - Navigation
    var selectedTab: NavigationTab = .search
    var sidebarSelection: SidebarItem? = .search

    // MARK: - Network Client
    let networkClient = NetworkClient()

    // MARK: - Initialization
    init() {}
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
    case settings

    var id: String {
        switch self {
        case .search: "search"
        case .transfers: "transfers"
        case .chat: "chat"
        case .browse: "browse"
        case .user(let name): "user-\(name)"
        case .room(let name): "room-\(name)"
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
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .transfers: "arrow.down.arrow.up"
        case .chat: "bubble.left.and.bubble.right"
        case .browse: "folder"
        case .user: "person"
        case .room: "person.3"
        case .settings: "gear"
        }
    }
}

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var appState = AppState()
}
