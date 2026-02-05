import Foundation

/// Configuration for leech detection and response
struct LeechSettings: Codable, Sendable {
    /// Whether leech detection is enabled
    var enabled: Bool = false

    /// Minimum number of shared files a user must have
    var minSharedFiles: UInt32 = 10

    /// Minimum number of shared folders a user must have
    var minSharedFolders: UInt32 = 1

    /// Action to take when a leech is detected
    var action: LeechAction = .warn

    /// Custom message to send (if action is .message or .warn)
    var customMessage: String = "Please share some files to use this network. Sharing is caring!"

    /// Whether to auto-block after warning
    var blockAfterWarning: Bool = false

    /// Default message templates
    static let defaultMessages: [String] = [
        "Please share some files to use this network. Sharing is caring!",
        "I noticed you have no shared files. The Soulseek network works best when everyone contributes.",
        "Hey! To download from me, please share some files first. Thank you!",
        "No shares detected. Please configure your shared folders to participate in the network."
    ]
}

enum LeechAction: String, Codable, CaseIterable, Sendable {
    case ignore = "ignore"      // Do nothing, just track
    case warn = "warn"          // Show warning in UI
    case message = "message"    // Send private message
    case deny = "deny"          // Deny file requests
    case block = "block"        // Block the user

    var displayName: String {
        switch self {
        case .ignore: "Ignore (track only)"
        case .warn: "Warn (show in UI)"
        case .message: "Send message"
        case .deny: "Deny downloads"
        case .block: "Block user"
        }
    }

    var description: String {
        switch self {
        case .ignore: "Track leeches but take no action"
        case .warn: "Show a warning indicator in the UI"
        case .message: "Automatically send a polite message asking them to share"
        case .deny: "Refuse file transfer requests from leeches"
        case .block: "Automatically block users with no shares"
        }
    }
}
