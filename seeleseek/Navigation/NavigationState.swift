import SwiftUI

/// Sidebar selection plus the tab strips that sit under it. Held outside
/// the views so `navigate(to:)` can deep link and the selection survives
/// the detail pane being rebuilt when the sidebar changes.
@Observable
final class NavigationState {
    var sidebarSelection: SidebarItem? = .search

    var transfersTab: TransferTab = .downloads
    var socialTab: SocialTab = .buddies
    var monitorTab: MonitorTab = .overview
    var settingsTab: SettingsTab = .general

    /// Set by ⌘F; SearchView consumes it once the field is on screen.
    var searchFieldFocusPending = false

    func navigate(to destination: Destination) {
        switch destination {
        case .transfers(let tab?): transfersTab = tab
        case .social(let tab?): socialTab = tab
        case .networkMonitor(let tab?): monitorTab = tab
        case .settings(let tab?): settingsTab = tab
        default: break
        }
        sidebarSelection = destination.sidebarItem
    }

    func requestSearchFieldFocus() {
        sidebarSelection = .search
        searchFieldFocusPending = true
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
