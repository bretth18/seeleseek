import Foundation
import SeeleseekCore

/// Configuration for leech detection and response
struct LeechSettings: Codable, Sendable, Equatable {
    var enabled: Bool = false

    var minSharedFiles: UInt32 = 10
    var minSharedFolders: UInt32 = 1

    var denyDownloads: Bool = false
    var sendMessage: Bool = false
    var blockUser: Bool = false

    /// `%files%` / `%folders%` expand to the thresholds.
    var customMessage: String = "Please share some files to use this network. Sharing is caring!"

    static let defaultMessages: [String] = [
        "Please share some files to use this network. Sharing is caring!",
        "Please consider sharing more files if you would like to download from me again. Thanks :)",
        "Hey! To download from me, please share at least %files% files in %folders% folders. Thank you!",
        "No shares detected. Please configure your shared folders to participate in the network."
    ]

    var deniesTransfers: Bool { denyDownloads || blockUser }

    var renderedMessage: String {
        customMessage
            .replacingOccurrences(of: "%files%", with: String(minSharedFiles))
            .replacingOccurrences(of: "%folders%", with: String(minSharedFolders))
    }
}

extension LeechSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled, minSharedFiles, minSharedFolders, denyDownloads, sendMessage, blockUser, customMessage
    }

    /// Settings saved before responses could be combined held a single
    /// `action`: ignore / warn / message / deny / block.
    private enum LegacyCodingKeys: String, CodingKey {
        case action
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyAction = try decoder.container(keyedBy: LegacyCodingKeys.self)
            .decodeIfPresent(String.self, forKey: .action)
        let defaults = LeechSettings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        minSharedFiles = try container.decodeIfPresent(UInt32.self, forKey: .minSharedFiles) ?? defaults.minSharedFiles
        minSharedFolders = try container.decodeIfPresent(UInt32.self, forKey: .minSharedFolders) ?? defaults.minSharedFolders
        denyDownloads = try container.decodeIfPresent(Bool.self, forKey: .denyDownloads) ?? (legacyAction == "deny")
        sendMessage = try container.decodeIfPresent(Bool.self, forKey: .sendMessage) ?? (legacyAction == "message")
        blockUser = try container.decodeIfPresent(Bool.self, forKey: .blockUser) ?? (legacyAction == "block")
        customMessage = try container.decodeIfPresent(String.self, forKey: .customMessage) ?? defaults.customMessage
    }
}
