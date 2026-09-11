import Foundation
import SeeleseekCore

/// Configuration for leech detection and response
struct LeechSettings: Codable, Sendable {
    var enabled: Bool = false

    /// Minimum number of shared files a user must have
    var minSharedFiles: UInt32 = 10

    /// Minimum number of shared folders a user must have
    var minSharedFolders: UInt32 = 1

    var action: LeechAction = .warn

    /// `%files%` / `%folders%` expand to the thresholds.
    var customMessage: String = "Please share some files to use this network. Sharing is caring!"

    static let defaultMessages: [String] = [
        "Please share some files to use this network. Sharing is caring!",
        "Please consider sharing more files if you would like to download from me again. Thanks :)",
        "Hey! To download from me, please share at least %files% files in %folders% folders. Thank you!",
        "No shares detected. Please configure your shared folders to participate in the network."
    ]

    var renderedMessage: String {
        customMessage
            .replacingOccurrences(of: "%files%", with: String(minSharedFiles))
            .replacingOccurrences(of: "%folders%", with: String(minSharedFolders))
    }
}

enum LeechAction: String, Codable, CaseIterable, Sendable {
    case ignore = "ignore"
    case warn = "warn"
    case message = "message"
    case deny = "deny"
    case block = "block"

    /// `.block` included so the triggering request is refused too.
    var deniesTransfers: Bool { self == .deny || self == .block }

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
        case .ignore: "Keep a list of leechers but take no action"
        case .warn: "Mark their uploads with a warning and log a detection event"
        case .message: "Send the custom message once, after the first upload to them completes"
        case .deny: "Refuse file requests from leechers"
        case .block: "Add leechers to the blocklist"
        }
    }
}
