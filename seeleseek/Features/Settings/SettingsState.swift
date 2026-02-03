import SwiftUI

@Observable
@MainActor
final class SettingsState {
    // MARK: - General Settings
    var downloadLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    var incompleteLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Incomplete")
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true

    // MARK: - Network Settings
    var listenPort: Int = 2234
    var enableUPnP: Bool = true
    var maxDownloadSlots: Int = 5
    var maxUploadSlots: Int = 5
    var uploadSpeedLimit: Int = 0 // 0 = unlimited
    var downloadSpeedLimit: Int = 0

    // MARK: - Shares Settings
    var sharedFolders: [URL] = []
    var rescanOnStartup: Bool = true
    var shareHiddenFiles: Bool = false

    // MARK: - Metadata Settings
    var autoFetchMetadata: Bool = true
    var autoFetchAlbumArt: Bool = true
    var embedAlbumArt: Bool = true
    var organizeDownloads: Bool = false
    var organizationPattern: String = "{artist}/{album}/{track} - {title}"

    // MARK: - Chat Settings
    var showJoinLeaveMessages: Bool = true
    var enableNotifications: Bool = true
    var notificationSound: Bool = true

    // MARK: - Privacy Settings
    var showOnlineStatus: Bool = true
    var allowBrowsing: Bool = true

    // MARK: - Actions
    func addSharedFolder(_ url: URL) {
        if !sharedFolders.contains(url) {
            sharedFolders.append(url)
        }
    }

    func removeSharedFolder(_ url: URL) {
        sharedFolders.removeAll { $0 == url }
    }

    func resetToDefaults() {
        downloadLocation = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        incompleteLocation = downloadLocation.appendingPathComponent("Incomplete")
        launchAtLogin = false
        showInMenuBar = true
        listenPort = 2234
        enableUPnP = true
        maxDownloadSlots = 5
        maxUploadSlots = 5
        uploadSpeedLimit = 0
        downloadSpeedLimit = 0
        rescanOnStartup = true
        shareHiddenFiles = false
        autoFetchMetadata = true
        autoFetchAlbumArt = true
        embedAlbumArt = true
        organizeDownloads = false
        organizationPattern = "{artist}/{album}/{track} - {title}"
        showJoinLeaveMessages = true
        enableNotifications = true
        notificationSound = true
        showOnlineStatus = true
        allowBrowsing = true
    }

    // MARK: - Persistence
    func save() {
        // In real app, save to UserDefaults or a settings file
    }

    func load() {
        // In real app, load from UserDefaults or a settings file
    }
}

// MARK: - Speed Formatting
extension SettingsState {
    var formattedUploadLimit: String {
        if uploadSpeedLimit == 0 {
            return "Unlimited"
        }
        return ByteFormatter.formatSpeed(Int64(uploadSpeedLimit * 1024))
    }

    var formattedDownloadLimit: String {
        if downloadSpeedLimit == 0 {
            return "Unlimited"
        }
        return ByteFormatter.formatSpeed(Int64(downloadSpeedLimit * 1024))
    }
}
