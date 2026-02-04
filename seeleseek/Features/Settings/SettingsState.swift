import SwiftUI

@Observable
@MainActor
final class SettingsState {
    // MARK: - Keys
    private let listenPortKey = "settings.listenPort"
    private let enableUPnPKey = "settings.enableUPnP"
    private let maxDownloadSlotsKey = "settings.maxDownloadSlots"
    private let maxUploadSlotsKey = "settings.maxUploadSlots"
    private let uploadSpeedLimitKey = "settings.uploadSpeedLimit"
    private let downloadSpeedLimitKey = "settings.downloadSpeedLimit"

    // MARK: - General Settings
    var downloadLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    var incompleteLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Incomplete")
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true

    // MARK: - Network Settings
    var listenPort: Int = 2234 {
        didSet {
            print("🔧 Settings: listenPort changed from \(oldValue) to \(listenPort)")
            save()
        }
    }
    var enableUPnP: Bool = true {
        didSet { save() }
    }
    var maxDownloadSlots: Int = 5 {
        didSet { save() }
    }
    var maxUploadSlots: Int = 5 {
        didSet { save() }
    }
    var uploadSpeedLimit: Int = 0 {
        didSet { save() }
    }
    var downloadSpeedLimit: Int = 0 {
        didSet { save() }
    }

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
        save()
    }

    // MARK: - Persistence
    func save() {
        UserDefaults.standard.set(listenPort, forKey: listenPortKey)
        UserDefaults.standard.set(enableUPnP, forKey: enableUPnPKey)
        UserDefaults.standard.set(maxDownloadSlots, forKey: maxDownloadSlotsKey)
        UserDefaults.standard.set(maxUploadSlots, forKey: maxUploadSlotsKey)
        UserDefaults.standard.set(uploadSpeedLimit, forKey: uploadSpeedLimitKey)
        UserDefaults.standard.set(downloadSpeedLimit, forKey: downloadSpeedLimitKey)
    }

    func load() {
        print("🔧 Settings: Loading from UserDefaults...")
        if UserDefaults.standard.object(forKey: listenPortKey) != nil {
            let savedPort = UserDefaults.standard.integer(forKey: listenPortKey)
            print("🔧 Settings: Found saved listenPort: \(savedPort)")
            listenPort = savedPort
        } else {
            print("🔧 Settings: No saved listenPort, using default: \(listenPort)")
        }
        if UserDefaults.standard.object(forKey: enableUPnPKey) != nil {
            enableUPnP = UserDefaults.standard.bool(forKey: enableUPnPKey)
        }
        if UserDefaults.standard.object(forKey: maxDownloadSlotsKey) != nil {
            maxDownloadSlots = UserDefaults.standard.integer(forKey: maxDownloadSlotsKey)
        }
        if UserDefaults.standard.object(forKey: maxUploadSlotsKey) != nil {
            maxUploadSlots = UserDefaults.standard.integer(forKey: maxUploadSlotsKey)
        }
        if UserDefaults.standard.object(forKey: uploadSpeedLimitKey) != nil {
            uploadSpeedLimit = UserDefaults.standard.integer(forKey: uploadSpeedLimitKey)
        }
        if UserDefaults.standard.object(forKey: downloadSpeedLimitKey) != nil {
            downloadSpeedLimit = UserDefaults.standard.integer(forKey: downloadSpeedLimitKey)
        }
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
