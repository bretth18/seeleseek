//
//  Destination.swift
//  seeleseek
//
//  Created by Brett Henderson on 9/3/26.
//

import Foundation

// MARK: - Transfer Tab

enum TransferTab: String, CaseIterable {
    case downloads = "Downloads"
    case uploads = "Uploads"
    case history = "History"

    var icon: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .uploads: "arrow.up.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

// MARK: - Social Tab

enum SocialTab: String, CaseIterable {
    case buddies = "Buddies"
    case ignored = "Ignored"
    case interests = "Interests"
    case discover = "Discover"

    var icon: String {
        switch self {
        case .buddies: "person.2"
        case .ignored: "eye.slash"
        case .interests: "heart"
        case .discover: "sparkles"
        }
    }
}

// MARK: - Monitor Tab

enum MonitorTab: String, CaseIterable {
    case overview = "Overview"
    case peers = "Peers"
    case search = "Search"
    case history = "History"

    var icon: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .peers: "person.line.dotted.person"
        case .search: "magnifyingglass"
        case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case profile = "Profile"
    case general = "General"
    case network = "Network"
    case shares = "Shares"
    case metadata = "Metadata"
    case chat = "Chat"
    case notifications = "Notifications"
    case privacy = "Privacy"
    case diagnostics = "Diagnostics"
    case update = "Update"
    case about = "About"

    var icon: String {
        switch self {
        case .profile: "person.crop.circle"
        case .general: "gear"
        case .network: "network"
        case .shares: "folder"
        case .metadata: "music.note"
        case .chat: "bubble.left"
        case .notifications: "bell"
        case .privacy: "lock.shield"
        case .diagnostics: "ant"
        case .update: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }
}

// MARK: - Destination

/// A place the app can navigate to. Surfaces with a fixed tab strip take an
/// optional tab; `nil` keeps whichever tab was last showing.
enum Destination {
    case search
    case wishlists
    case browse
    case chat
    case transfers(TransferTab? = nil)
    case social(SocialTab? = nil)
    case networkMonitor(MonitorTab? = nil)
    case settings(SettingsTab? = nil)

    var sidebarItem: SidebarItem {
        switch self {
        case .search: .search
        case .wishlists: .wishlists
        case .browse: .browse
        case .chat: .chat
        case .transfers: .transfers
        case .social: .social
        case .networkMonitor: .networkMonitor
        case .settings: .settings
        }
    }
}
