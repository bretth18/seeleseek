import SwiftUI
import ServiceManagement
import os
import SeeleseekCore

enum NotificationSound: String, CaseIterable {
    case `default` = "default"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var displayName: String {
        switch self {
        case .default: "Default"
        case .basso: "Basso"
        case .blow: "Blow"
        case .bottle: "Bottle"
        case .frog: "Frog"
        case .funk: "Funk"
        case .glass: "Glass"
        case .hero: "Hero"
        case .morse: "Morse"
        case .ping: "Ping"
        case .pop: "Pop"
        case .purr: "Purr"
        case .sosumi: "Sosumi"
        case .submarine: "Submarine"
        case .tink: "Tink"
        }
    }
}

enum DownloadFolderFormat: String, CaseIterable {
    case folderOnly = "folderOnly"
    case usernameAndPath = "usernameAndPath"
    case pathOnly = "pathOnly"
    case artistAlbum = "artistAlbum"
    case flat = "flat"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .folderOnly: "Folder"
        case .usernameAndPath: "Username / Full Path"
        case .pathOnly: "Full Path"
        case .artistAlbum: "Artist - Album"
        case .flat: "Filename Only"
        case .custom: "Custom"
        }
    }

    var template: String {
        switch self {
        case .folderOnly: "{folder}/{filename}"
        case .usernameAndPath: "{username}/{full-path}/{filename}"
        case .pathOnly: "{full-path}/{filename}"
        case .artistAlbum: "{artist} - {album}/{filename}"
        case .flat: "{filename}"
        case .custom: ""
        }
    }

}

/// Search-result filter prefs that survive relaunch. Kept separate from
/// `SearchState` so Settings can load them before the search tab wires up.
/// New fields must be optional: synthesized Codable ignores the defaults
/// below, so blobs from older builds would fail to decode and reset to .empty.
struct PersistedSearchFilters: Equatable, Codable, Sendable {
    var minBitrate: Int? = nil
    var minSampleRate: Int? = nil
    var minBitDepth: Int? = nil
    var minSize: Int64? = nil
    var maxSize: Int64? = nil
    var extensions: Set<String> = []
    var freeSlotOnly: Bool = false

    static let empty = PersistedSearchFilters()
}

@Observable
@MainActor
final class SettingsState: DownloadSettingsProviding {
    // MARK: - Keys (for UserDefaults fallback)
    private let listenPortKey = "settingsListenPort"
    private let enableUPnPKey = "settingsEnableUPnP"
    private let maxDownloadSlotsKey = "settingsMaxDownloadSlots"
    private let maxUploadSlotsKey = "settingsMaxUploadSlots"
    private let uploadSpeedLimitKey = "settingsUploadSpeedLimit"
    private let downloadSpeedLimitKey = "settingsDownloadSpeedLimit"
    private let maxSearchResultsKey = "settingsMaxSearchResults"
    private let groupSearchResultsKey = "settingsGroupSearchResults"
    private let searchFiltersKey = "settingsSearchFilters"
    private let downloadLocationKey = "settingsDownloadLocation"
    private let incompleteLocationKey = "settingsIncompleteLocation"
    private let downloadFolderFormatKey = "settingsDownloadFolderFormat"
    private let downloadFolderTemplateKey = "settingsDownloadFolderTemplate"
    private let downloadDefaultsMigratedKey = "settingsDownloadDefaultsMigratedV2"
    private let launchAtLoginKey = "settingsLaunchAtLogin"
    private let showInMenuBarKey = "settingsShowInMenuBar"
    private let notifyDownloadsKey = "settingsNotifyDownloads"
    private let notifyUploadsKey = "settingsNotifyUploads"
    private let notifyPrivateMessagesKey = "settingsNotifyPrivateMessages"
    private let notifyOnlyInBackgroundKey = "settingsNotifyOnlyInBackground"
    private let notificationSoundNameKey = "settingsNotificationSoundName"
    private let blockLeechPatternsEnabledKey = "settingsBlockLeechPatternsEnabled"
    private let blockedUsernamePatternsKey = "settingsBlockedUsernamePatterns"
    private let showJoinLeaveMessagesKey = "settingsShowJoinLeaveMessages"

    /// Default patterns shipped on first launch. Prefix `slsk_` catches bot accounts
    /// created by "streaming-service" apps that queue uploads en masse without sharing.
    static let defaultBlockedUsernamePatterns: [String] = ["slsk_*"]

    static let defaultDownloadLocation = DownloadManager.defaultDownloadDirectory
    static let defaultIncompleteLocation = defaultDownloadLocation.appendingPathComponent("Incomplete")
    static let defaultDownloadFolderFormat = DownloadFolderFormat.folderOnly
    /// Starting point for a custom template, not the shipped default layout.
    static let defaultDownloadFolderTemplate = DownloadFolderFormat.usernameAndPath.template

    private let logger = Logger(subsystem: "com.seeleseek", category: "Settings")

    // Flag to prevent save during load
    private var isLoading = false

    // MARK: - General Settings
    var downloadLocation: URL = SettingsState.defaultDownloadLocation {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var incompleteLocation: URL = SettingsState.defaultIncompleteLocation {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var downloadFolderFormat: DownloadFolderFormat = SettingsState.defaultDownloadFolderFormat {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var downloadFolderTemplate: String = SettingsState.defaultDownloadFolderTemplate {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var launchAtLogin: Bool = false {
        didSet {
            guard !isLoading else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Failed to \(self.launchAtLogin ? "register" : "unregister") launch at login: \(error.localizedDescription)")
            }
            save()
        }
    }
    var showInMenuBar: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

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
            onMaxUploadSlotsChange?(maxUploadSlots)
        }
    }

    /// Live push from the settings UI to UploadManager. Wired by AppState
    /// at startup — without this, the stepper would only affect a fresh
    /// launch (and historically didn't affect anything at all: the cap
    /// was hardcoded to 3).
    var onMaxUploadSlotsChange: ((Int) -> Void)?
    var uploadSpeedLimit: Int = 0 {
        didSet {
            guard !isLoading else { return }
            save()
            onUploadSpeedLimitChange?(uploadSpeedLimit)
        }
    }
    /// Live push (KB/s, 0 = unlimited) to UploadManager. Wired by AppState —
    /// the setting was previously cosmetic: persisted and displayed, but
    /// never assigned to the manager's limiter.
    var onUploadSpeedLimitChange: ((Int) -> Void)?
    var downloadSpeedLimit: Int = 0 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    // MARK: - Search Settings
    /// Maximum number of search results to collect (0 = unlimited)
    var maxSearchResults: Int = 500 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    /// Mirrors `SearchState.isGrouped`, which writes back here on every
    /// change so the filter-bar toggle persists too. The oldValue guard
    /// stops that write-back loop from re-saving.
    var groupSearchResults: Bool = false {
        didSet {
            guard !isLoading, groupSearchResults != oldValue else { return }
            save()
        }
    }
    /// Mirrors `SearchState` quality/format filters. Sort order and panel
    /// open state stay session-only. Written back on every filter edit
    /// (including Clear → empty).
    var searchFilters: PersistedSearchFilters = .empty {
        didSet {
            guard !isLoading, searchFilters != oldValue else { return }
            save()
        }
    }

    // MARK: - Search Response Settings (how we respond to other users' searches)
    /// Whether to respond to distributed search requests from other users
    var respondToSearches: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    /// Minimum search query length to respond to (filters out short/broad queries)
    var minSearchQueryLength: Int = 3 {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    /// Maximum number of results to send per search response (0 = unlimited)
    var maxSearchResponseResults: Int = 50 {
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
    var setFolderIcons: Bool = true
    var organizeDownloads: Bool = false
    var organizationPattern: String = "{artist}/{album}/{track} - {title}"

    // MARK: - Chat Settings
    var showJoinLeaveMessages: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var enableNotifications: Bool = true
    var notificationSound: Bool = true
    var selectedNotificationSound: NotificationSound = .default {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    var availableNotificationSounds: [NotificationSound] {
        NotificationSound.allCases
    }

    // MARK: - Notification Settings (granular)
    var notifyDownloads: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var notifyUploads: Bool = false {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var notifyPrivateMessages: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }
    var notifyOnlyInBackground: Bool = false {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    // MARK: - Privacy Settings
    var showOnlineStatus: Bool = true
    var allowBrowsing: Bool = true

    /// When true, peers whose usernames match any pattern in `blockedUsernamePatterns`
    /// have their upload requests silently rejected.
    var blockLeechPatternsEnabled: Bool = true {
        didSet {
            recomputeActiveBlockedPatterns()
            guard !isLoading else { return }
            save()
        }
    }

    /// Glob-style patterns (`*` wildcard) matched case-insensitively against incoming
    /// upload-request usernames. Example: `slsk_*` blocks any user whose name starts
    /// with `slsk_`.
    var blockedUsernamePatterns: [String] = SettingsState.defaultBlockedUsernamePatterns {
        didSet {
            recomputeActiveBlockedPatterns()
            guard !isLoading else { return }
            save()
        }
    }

    /// Precompiled, filter-ready pattern set consumed by the peer/upload checkers.
    /// Empty when blocking is disabled OR the user's list contains only blank entries.
    /// Readers short-circuit on `.isEmpty` — no closure or string work on the hot path.
    private(set) var activeBlockedPatterns: [UsernamePatternMatcher.Compiled] =
        UsernamePatternMatcher.compile(SettingsState.defaultBlockedUsernamePatterns)

    private func recomputeActiveBlockedPatterns() {
        activeBlockedPatterns = blockLeechPatternsEnabled
            ? UsernamePatternMatcher.compile(blockedUsernamePatterns)
            : []
    }

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
        downloadLocation = SettingsState.defaultDownloadLocation
        incompleteLocation = SettingsState.defaultIncompleteLocation
        downloadFolderFormat = SettingsState.defaultDownloadFolderFormat
        downloadFolderTemplate = SettingsState.defaultDownloadFolderTemplate
        launchAtLogin = false
        showInMenuBar = true
        listenPort = 2234
        enableUPnP = true
        maxDownloadSlots = 5
        maxUploadSlots = 5
        uploadSpeedLimit = 0
        downloadSpeedLimit = 0
        maxSearchResults = 500
        groupSearchResults = false
        searchFilters = .empty
        respondToSearches = true
        minSearchQueryLength = 3
        maxSearchResponseResults = 50
        rescanOnStartup = true
        shareHiddenFiles = false
        autoFetchMetadata = true
        autoFetchAlbumArt = true
        embedAlbumArt = true
        setFolderIcons = true
        organizeDownloads = false
        organizationPattern = "{artist}/{album}/{track} - {title}"
        showJoinLeaveMessages = true
        enableNotifications = true
        notificationSound = true
        selectedNotificationSound = .default
        notifyDownloads = true
        notifyUploads = false
        notifyPrivateMessages = true
        notifyOnlyInBackground = false
        showOnlineStatus = true
        allowBrowsing = true
        blockLeechPatternsEnabled = true
        blockedUsernamePatterns = SettingsState.defaultBlockedUsernamePatterns
        save()
    }

    // MARK: - Launch at Login Sync

    /// Sync launchAtLogin state from the system (user may toggle it in System Settings)
    func syncLaunchAtLoginState() {
        isLoading = true
        defer { isLoading = false }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Persistence

    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?

    /// Debounced save. Every settings property calls this from its
    /// `didSet`, and `resetToDefaults()` fires it ~30×; each call used to
    /// rewrite all ~20 UserDefaults keys and schedule a full DB save.
    /// Coalesce bursts into a single write half a second after the last
    /// change.
    func save() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.pendingSaveTask = nil
            self.saveNow()
        }
    }

    /// Save settings to both database and UserDefaults (for backwards compatibility)
    private func saveNow() {
        // Save to UserDefaults (legacy support)
        UserDefaults.standard.set(listenPort, forKey: listenPortKey)
        UserDefaults.standard.set(enableUPnP, forKey: enableUPnPKey)
        UserDefaults.standard.set(maxDownloadSlots, forKey: maxDownloadSlotsKey)
        UserDefaults.standard.set(maxUploadSlots, forKey: maxUploadSlotsKey)
        UserDefaults.standard.set(uploadSpeedLimit, forKey: uploadSpeedLimitKey)
        UserDefaults.standard.set(downloadSpeedLimit, forKey: downloadSpeedLimitKey)
        UserDefaults.standard.set(maxSearchResults, forKey: maxSearchResultsKey)
        UserDefaults.standard.set(groupSearchResults, forKey: groupSearchResultsKey)
        if let data = try? JSONEncoder().encode(searchFilters) {
            UserDefaults.standard.set(data, forKey: searchFiltersKey)
        }
        UserDefaults.standard.set(downloadLocation.path, forKey: downloadLocationKey)
        UserDefaults.standard.set(incompleteLocation.path, forKey: incompleteLocationKey)
        UserDefaults.standard.set(downloadFolderFormat.rawValue, forKey: downloadFolderFormatKey)
        UserDefaults.standard.set(downloadFolderTemplate, forKey: downloadFolderTemplateKey)
        UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
        UserDefaults.standard.set(showInMenuBar, forKey: showInMenuBarKey)
        UserDefaults.standard.set(notifyDownloads, forKey: notifyDownloadsKey)
        UserDefaults.standard.set(notifyUploads, forKey: notifyUploadsKey)
        UserDefaults.standard.set(notifyPrivateMessages, forKey: notifyPrivateMessagesKey)
        UserDefaults.standard.set(notifyOnlyInBackground, forKey: notifyOnlyInBackgroundKey)
        UserDefaults.standard.set(selectedNotificationSound.rawValue, forKey: notificationSoundNameKey)
        UserDefaults.standard.set(blockLeechPatternsEnabled, forKey: blockLeechPatternsEnabledKey)
        UserDefaults.standard.set(blockedUsernamePatterns, forKey: blockedUsernamePatternsKey)
        UserDefaults.standard.set(showJoinLeaveMessages, forKey: showJoinLeaveMessagesKey)

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
            try await SettingsRepository.set("maxSearchResults", value: maxSearchResults)
            try await SettingsRepository.set("respondToSearches", value: respondToSearches)
            try await SettingsRepository.set("minSearchQueryLength", value: minSearchQueryLength)
            try await SettingsRepository.set("maxSearchResponseResults", value: maxSearchResponseResults)
            try await SettingsRepository.set("downloadFolderFormat", value: downloadFolderFormat.rawValue)
            try await SettingsRepository.set("downloadFolderTemplate", value: downloadFolderTemplate)
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
        if UserDefaults.standard.object(forKey: maxSearchResultsKey) != nil {
            maxSearchResults = UserDefaults.standard.integer(forKey: maxSearchResultsKey)
        }
        if UserDefaults.standard.object(forKey: groupSearchResultsKey) != nil {
            groupSearchResults = UserDefaults.standard.bool(forKey: groupSearchResultsKey)
        }
        if let data = UserDefaults.standard.data(forKey: searchFiltersKey),
           let filters = try? JSONDecoder().decode(PersistedSearchFilters.self, from: data) {
            searchFilters = filters
        }
        if let downloadPath = UserDefaults.standard.string(forKey: downloadLocationKey) {
            downloadLocation = URL(fileURLWithPath: downloadPath)
        }
        if let incompletePath = UserDefaults.standard.string(forKey: incompleteLocationKey) {
            incompleteLocation = URL(fileURLWithPath: incompletePath)
        }
        if let formatRaw = UserDefaults.standard.string(forKey: downloadFolderFormatKey),
           let format = DownloadFolderFormat(rawValue: formatRaw) {
            downloadFolderFormat = format
        }
        if let template = UserDefaults.standard.string(forKey: downloadFolderTemplateKey) {
            downloadFolderTemplate = template
        }
        migrateDownloadDefaultsIfNeeded()
        if UserDefaults.standard.object(forKey: showInMenuBarKey) != nil {
            showInMenuBar = UserDefaults.standard.bool(forKey: showInMenuBarKey)
        }
        if UserDefaults.standard.object(forKey: notifyDownloadsKey) != nil {
            notifyDownloads = UserDefaults.standard.bool(forKey: notifyDownloadsKey)
        }
        if UserDefaults.standard.object(forKey: notifyUploadsKey) != nil {
            notifyUploads = UserDefaults.standard.bool(forKey: notifyUploadsKey)
        }
        if UserDefaults.standard.object(forKey: notifyPrivateMessagesKey) != nil {
            notifyPrivateMessages = UserDefaults.standard.bool(forKey: notifyPrivateMessagesKey)
        }
        if UserDefaults.standard.object(forKey: notifyOnlyInBackgroundKey) != nil {
            notifyOnlyInBackground = UserDefaults.standard.bool(forKey: notifyOnlyInBackgroundKey)
        }
        if let soundRaw = UserDefaults.standard.string(forKey: notificationSoundNameKey),
           let sound = NotificationSound(rawValue: soundRaw) {
            selectedNotificationSound = sound
        }
        if UserDefaults.standard.object(forKey: blockLeechPatternsEnabledKey) != nil {
            blockLeechPatternsEnabled = UserDefaults.standard.bool(forKey: blockLeechPatternsEnabledKey)
        }
        if let patterns = UserDefaults.standard.stringArray(forKey: blockedUsernamePatternsKey) {
            blockedUsernamePatterns = patterns
        }
        if UserDefaults.standard.object(forKey: showJoinLeaveMessagesKey) != nil {
            showJoinLeaveMessages = UserDefaults.standard.bool(forKey: showJoinLeaveMessagesKey)
        }
    }

    /// Both download defaults changed in this version, and each would
    /// re-lay-out an upgraded install: a stored `~/Downloads` (the old
    /// default, which was never actually used) would dump files loose into
    /// Downloads, and the new `.folderOnly` structure would apply to anyone
    /// who never opened Settings, since `save()` only runs from a `didSet`.
    /// Old versions created `~/Downloads/SeeleSeek` eagerly at launch, so its
    /// presence marks a pre-1.1.x install. Chosen values are left alone.
    private func migrateDownloadDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: downloadDefaultsMigratedKey) else { return }
        defaults.set(true, forKey: downloadDefaultsMigratedKey)

        let isUpgrade = FileManager.default.fileExists(atPath: SettingsState.defaultDownloadLocation.path)

        if isUpgrade, defaults.string(forKey: downloadFolderFormatKey) == nil {
            logger.info("Pinning pre-existing library to the previous folder structure default")
            downloadFolderFormat = .usernameAndPath
            // `isLoading` suppresses the `didSet` that would normally persist
            // this, and the one-shot flag is already burned.
            defaults.set(downloadFolderFormat.rawValue, forKey: downloadFolderFormatKey)
        }

        let legacyDefault = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

        // Same pin for the incomplete directory: partials from the old
        // default must stay findable or interrupted downloads restart at 0.
        let legacyIncomplete = legacyDefault.appendingPathComponent("Incomplete")
        if isUpgrade, defaults.string(forKey: incompleteLocationKey) == nil,
           FileManager.default.fileExists(atPath: legacyIncomplete.path) {
            logger.info("Pinning incomplete directory to previous default \(legacyIncomplete.path)")
            incompleteLocation = legacyIncomplete
            defaults.set(incompleteLocation.path, forKey: incompleteLocationKey)
        }

        guard downloadLocation.standardizedFileURL == legacyDefault.standardizedFileURL else { return }

        logger.info("Migrating download location from \(legacyDefault.path) to \(SettingsState.defaultDownloadLocation.path)")
        downloadLocation = SettingsState.defaultDownloadLocation
        defaults.set(downloadLocation.path, forKey: downloadLocationKey)
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
            maxSearchResults = try await SettingsRepository.get("maxSearchResults", default: maxSearchResults)
            respondToSearches = try await SettingsRepository.get("respondToSearches", default: respondToSearches)
            minSearchQueryLength = try await SettingsRepository.get("minSearchQueryLength", default: minSearchQueryLength)
            maxSearchResponseResults = try await SettingsRepository.get("maxSearchResponseResults", default: maxSearchResponseResults)

            let formatRaw: String = try await SettingsRepository.get("downloadFolderFormat", default: downloadFolderFormat.rawValue)
            if let format = DownloadFolderFormat(rawValue: formatRaw) {
                downloadFolderFormat = format
            }
            downloadFolderTemplate = try await SettingsRepository.get("downloadFolderTemplate", default: downloadFolderTemplate)

            logger.info("Settings loaded from database")
        } catch {
            logger.error("Failed to load settings from database: \(error.localizedDescription)")
            // Keep using values loaded from UserDefaults
        }
    }
}

// MARK: - Download Folder Template
extension SettingsState {
    var activeDownloadTemplate: String {
        let template = downloadFolderFormat == .custom ? downloadFolderTemplate : downloadFolderFormat.template
        return template.isEmpty ? DownloadManager.fallbackTemplate : template
    }

    var incompleteDownloadDirectory: URL {
        incompleteLocation
    }
}

// MARK: - Speed Formatting
extension SettingsState {
    var formattedUploadLimit: String {
        if uploadSpeedLimit == 0 {
            return "Unlimited"
        }
        return Int64(uploadSpeedLimit * 1024).formattedSpeed
    }

    var formattedDownloadLimit: String {
        if downloadSpeedLimit == 0 {
            return "Unlimited"
        }
        return Int64(downloadSpeedLimit * 1024).formattedSpeed
    }
}
