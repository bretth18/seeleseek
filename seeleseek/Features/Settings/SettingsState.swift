import SwiftUI
import os

@Observable
@MainActor
final class SettingsState {
    // MARK: - Keys (for UserDefaults fallback)
    private let listenPortKey = "settings.listenPort"
    private let enableUPnPKey = "settings.enableUPnP"
    private let maxDownloadSlotsKey = "settings.maxDownloadSlots"
    private let maxUploadSlotsKey = "settings.maxUploadSlots"
    private let uploadSpeedLimitKey = "settings.uploadSpeedLimit"
    private let downloadSpeedLimitKey = "settings.downloadSpeedLimit"

    private let logger = Logger(subsystem: "com.seeleseek", category: "Settings")

    // Flag to prevent save during load
    private var isLoading = false

    // MARK: - General Settings
    var downloadLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    var incompleteLocation: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Incomplete")
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true

    // MARK: - Network Settings
    var listenPort: Int = 2234 {
        didSet {
            guard !isLoading else { return }
            logger.info("listenPort changed from \(oldValue) to \(self.listenPort)")
            save()
        }
    }
    var enableUPnP: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var maxDownloadSlots: Int = 5 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var maxUploadSlots: Int = 5 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var uploadSpeedLimit: Int = 0 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var downloadSpeedLimit: Int = 0 {
        didSet {
            guard !isLoading else { return }
            save()
        }
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

    /// Save settings to both database and UserDefaults (for backwards compatibility)
    func save() {
        // Save to UserDefaults (legacy support)
        UserDefaults.standard.set(listenPort, forKey: listenPortKey)
        UserDefaults.standard.set(enableUPnP, forKey: enableUPnPKey)
        UserDefaults.standard.set(maxDownloadSlots, forKey: maxDownloadSlotsKey)
        UserDefaults.standard.set(maxUploadSlots, forKey: maxUploadSlotsKey)
        UserDefaults.standard.set(uploadSpeedLimit, forKey: uploadSpeedLimitKey)
        UserDefaults.standard.set(downloadSpeedLimit, forKey: downloadSpeedLimitKey)

        // Save to database asynchronously
        Task {
            await saveToDatabase()
        }
    }

    /// Save settings to database
    private func saveToDatabase() async {
        do {
            try await SettingsRepository.set("listenPort", value: listenPort)
            try await SettingsRepository.set("enableUPnP", value: enableUPnP)
            try await SettingsRepository.set("maxDownloadSlots", value: maxDownloadSlots)
            try await SettingsRepository.set("maxUploadSlots", value: maxUploadSlots)
            try await SettingsRepository.set("uploadSpeedLimit", value: uploadSpeedLimit)
            try await SettingsRepository.set("downloadSpeedLimit", value: downloadSpeedLimit)
            logger.debug("Settings saved to database")
        } catch {
            logger.error("Failed to save settings to database: \(error.localizedDescription)")
        }
    }

    /// Load settings from UserDefaults (used during initial startup before DB is ready)
    func load() {
        isLoading = true
        defer { isLoading = false }

        logger.info("Loading settings from UserDefaults...")
        if UserDefaults.standard.object(forKey: listenPortKey) != nil {
            let savedPort = UserDefaults.standard.integer(forKey: listenPortKey)
            logger.info("Found saved listenPort: \(savedPort)")
            listenPort = savedPort
        } else {
            logger.info("No saved listenPort, using default: \(self.listenPort)")
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

    /// Load settings from database (called after DB initialization)
    func loadFromDatabase() async {
        isLoading = true
        defer { isLoading = false }

        do {
            logger.info("Loading settings from database...")

            listenPort = try await SettingsRepository.get("listenPort", default: listenPort)
            enableUPnP = try await SettingsRepository.get("enableUPnP", default: enableUPnP)
            maxDownloadSlots = try await SettingsRepository.get("maxDownloadSlots", default: maxDownloadSlots)
            maxUploadSlots = try await SettingsRepository.get("maxUploadSlots", default: maxUploadSlots)
            uploadSpeedLimit = try await SettingsRepository.get("uploadSpeedLimit", default: uploadSpeedLimit)
            downloadSpeedLimit = try await SettingsRepository.get("downloadSpeedLimit", default: downloadSpeedLimit)

            logger.info("Settings loaded from database")
        } catch {
            logger.error("Failed to load settings from database: \(error.localizedDescription)")
            // Keep using values loaded from UserDefaults
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
