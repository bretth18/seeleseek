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

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
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
    private let searchFilterPresetsKey = "settingsSearchFilterPresets"
    private let downloadLocationKey = "settingsDownloadLocation"
    private let incompleteLocationKey = "settingsIncompleteLocation"
    private let downloadFolderFormatKey = "settingsDownloadFolderFormat"
    private let downloadFolderTemplateKey = "settingsDownloadFolderTemplate"
    private let downloadDefaultsMigratedKey = "settingsDownloadDefaultsMigratedV2"
    private let launchAtLoginKey = "settingsLaunchAtLogin"
    private let connectAtLaunchKey = "settingsConnectAtLaunch"
    private let showInMenuBarKey = "settingsShowInMenuBar"
    private let appearanceKey = "settingsAppearance"
    private let notifyDownloadsKey = "settingsNotifyDownloads"
    private let notifyUploadsKey = "settingsNotifyUploads"
    private let notifyPrivateMessagesKey = "settingsNotifyPrivateMessages"
    private let notifyWishlistKey = "settingsNotifyWishlist"
    private let notifyLeechersKey = "settingsNotifyLeechers"
    private let notifyOnlyInBackgroundKey = "settingsNotifyOnlyInBackground"
    private let notificationSoundNameKey = "settingsNotificationSoundName"
    private let blockLeechPatternsEnabledKey = "settingsBlockLeechPatternsEnabled"
    private let blockedUsernamePatternsKey = "settingsBlockedUsernamePatterns"
    private let showJoinLeaveMessagesKey = "settingsShowJoinLeaveMessages"
    private let autoJoinRoomsKey = "settingsAutoJoinRooms"
    private let enableNotificationsKey = "settingsEnableNotifications"
    private let notificationSoundEnabledKey = "settingsNotificationSoundEnabled"
    private let rescanOnStartupKey = "settingsRescanOnStartup"
    private let shareHiddenFilesKey = "settingsShareHiddenFiles"
    private let autoFetchMetadataKey = "settingsAutoFetchMetadata"
    private let autoFetchAlbumArtKey = "settingsAutoFetchAlbumArt"
    private let embedAlbumArtKey = "settingsEmbedAlbumArt"
    private let setFolderIconsKey = "settingsSetFolderIcons"
    private let organizeDownloadsKey = "settingsOrganizeDownloads"
    private let organizationPatternKey = "settingsOrganizationPattern"
    private let showOnlineStatusKey = "settingsShowOnlineStatus"
    private let allowBrowsingKey = "settingsAllowBrowsing"

    /// Default patterns shipped on first launch. Prefix `slsk_` catches bot accounts
    /// created by "streaming-service" apps that queue uploads en masse without sharing.
    static let defaultBlockedUsernamePatterns: [String] = ["slsk_*"]

    static let defaultDownloadLocation = DownloadManager.defaultDownloadDirectory
    static let defaultIncompleteLocation = defaultDownloadLocation.appendingPathComponent("Incomplete")
    static let defaultDownloadFolderFormat = DownloadFolderFormat.folderOnly
    /// Starting point for a custom template, not the shipped default layout.
    static let defaultDownloadFolderTemplate = DownloadFolderFormat.usernameAndPath.template

    private let logger = Logger(subsystem: "com.seeleseek", category: "Settings")

    /// Backing store for prefs. Injectable so tests can use an isolated suite
    /// instead of the live `UserDefaults.standard` (same trap as ShareManager).
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Flag to prevent save during load
    private var isLoading = false
    /// `save()` is a no-op until `load()` finishes. Stops first-frame
    /// bindings (MenuBarExtra `isInserted`, etc.) from writing factory
    /// defaults over real prefs before configure runs.
    private var hasLoaded = false

    // MARK: - General Settings
    var downloadLocation: URL = SettingsState.defaultDownloadLocation {
        didSet {
            guard !isLoading else { return }
            save()
            onDownloadSettingsChange?()
        }
    }
    var incompleteLocation: URL = SettingsState.defaultIncompleteLocation {
        didSet {
            guard !isLoading else { return }
            save()
            onDownloadSettingsChange?()
        }
    }
    var downloadFolderFormat: DownloadFolderFormat = SettingsState.defaultDownloadFolderFormat {
        didSet {
            guard !isLoading else { return }
            save()
            onDownloadSettingsChange?()
        }
    }
    var downloadFolderTemplate: String = SettingsState.defaultDownloadFolderTemplate {
        didSet {
            guard !isLoading else { return }
            save()
            onDownloadSettingsChange?()
        }
    }

    /// Live push to `DownloadManager`'s settings snapshot — wired by
    /// AppState. Fired whenever any download-relevant setting changes,
    /// and after `loadFromDatabase()` in case wiring happened before the
    /// load.
    @ObservationIgnored var onDownloadSettingsChange: (() -> Void)?
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
        didSet { save() }
    }
    /// Dark, not system: existing installs on light Macs must not re-theme on update.
    var appearance: AppAppearance = .dark {
        didSet { save() }
    }
    var connectAtLaunch: Bool = false {
        didSet { save() }
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
        didSet { save() }
    }
    var maxDownloadSlots: Int = 5 {
        didSet { save() }
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
        didSet { save() }
    }

    // MARK: - Search Settings
    /// Maximum number of search results to collect (0 = unlimited)
    var maxSearchResults: Int = 500 {
        didSet { save() }
    }
    /// Mirrors `SearchState.isGrouped`, which writes back here on every
    /// change so the filter-bar toggle persists too. The oldValue guard
    /// stops that write-back loop from re-saving.
    var groupSearchResults: Bool = false {
        didSet {
            guard groupSearchResults != oldValue else { return }
            save()
        }
    }
    /// Mirrors `SearchState` quality/format filters. Sort order and panel
    /// open state stay session-only. Written back on every filter edit
    /// (including Clear → empty).
    var searchFilters: PersistedSearchFilters = .empty {
        didSet {
            guard searchFilters != oldValue else { return }
            save()
        }
    }
    /// Quick-filter pills in the search bar, in display order.
    var searchFilterPresets: [SearchFilterPreset] = SearchFilterPreset.defaults {
        didSet {
            guard searchFilterPresets != oldValue else { return }
            save()
        }
    }

    // MARK: - Search Response Settings (how we respond to other users' searches)
    /// Whether to respond to distributed search requests from other users
    var respondToSearches: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
            onSearchResponsePolicyChange?(searchResponsePolicy)
        }
    }
    /// Minimum search query length to respond to (filters out short/broad queries)
    var minSearchQueryLength: Int = 3 {
        didSet {
            guard !isLoading else { return }
            save()
            onSearchResponsePolicyChange?(searchResponsePolicy)
        }
    }
    /// Maximum number of results to send per search response (0 = unlimited)
    var maxSearchResponseResults: Int = 50 {
        didSet {
            guard !isLoading else { return }
            save()
            onSearchResponsePolicyChange?(searchResponsePolicy)
        }
    }

    /// The three settings above as the core's pushed-down policy value.
    var searchResponsePolicy: SearchResponsePolicy {
        SearchResponsePolicy(
            enabled: respondToSearches,
            minQueryLength: minSearchQueryLength,
            maxResults: maxSearchResponseResults
        )
    }

    /// Live push to `NetworkClient` — wired by AppState. Also fired after
    /// `loadFromDatabase()` in case wiring happened before the load.
    var onSearchResponsePolicyChange: ((SearchResponsePolicy) -> Void)?

    // MARK: - Shares Settings
    var rescanOnStartup: Bool = true {
        didSet { save() }
    }
    var shareHiddenFiles: Bool = false {
        didSet { save() }
    }

    // MARK: - Metadata Settings
    var autoFetchMetadata: Bool = true {
        didSet { save() }
    }
    var autoFetchAlbumArt: Bool = true {
        didSet { save() }
    }
    var embedAlbumArt: Bool = true {
        didSet { save() }
    }
    var setFolderIcons: Bool = true {
        didSet {
            guard !isLoading else { return }
            save()
            onDownloadSettingsChange?()
        }
    }
    var organizeDownloads: Bool = false {
        didSet { save() }
    }
    var organizationPattern: String = "{artist}/{album}/{track} - {title}" {
        didSet { save() }
    }

    // MARK: - Chat Settings
    var showJoinLeaveMessages: Bool = true {
        didSet { save() }
    }
    /// Rooms joined on every connect (the server drops membership on
    /// disconnect). Seeded with the project room on a fresh install only;
    /// existing installs start empty so an update never drops anyone
    /// into a room unasked.
    static let defaultAutoJoinRooms = ["seeleseek"]
    var autoJoinRooms: [String] = [] {
        didSet {
            guard autoJoinRooms != oldValue else { return }
            save()
        }
    }
    var enableNotifications: Bool = true {
        didSet { save() }
    }
    var notificationSound: Bool = true {
        didSet { save() }
    }
    var selectedNotificationSound: NotificationSound = .default {
        didSet { save() }
    }

    var availableNotificationSounds: [NotificationSound] {
        NotificationSound.allCases
    }

    // MARK: - Notification Settings (granular)
    var notifyDownloads: Bool = true {
        didSet { save() }
    }
    var notifyUploads: Bool = false {
        didSet { save() }
    }
    var notifyPrivateMessages: Bool = true {
        didSet { save() }
    }
    var notifyWishlist: Bool = true {
        didSet { save() }
    }
    var notifyLeechers: Bool = true {
        didSet { save() }
    }
    var notifyOnlyInBackground: Bool = false {
        didSet { save() }
    }

    // MARK: - Privacy Settings
    var showOnlineStatus: Bool = true {
        didSet { save() }
    }
    var allowBrowsing: Bool = true {
        didSet { save() }
    }

    /// When true, peers whose usernames match any pattern in `blockedUsernamePatterns`
    /// have their upload requests silently rejected.
    var blockLeechPatternsEnabled: Bool = true {
        didSet {
            recomputeActiveBlockedPatterns()
            save()
        }
    }

    /// Glob-style patterns (`*` wildcard) matched case-insensitively against incoming
    /// upload-request usernames. Example: `slsk_*` blocks any user whose name starts
    /// with `slsk_`.
    var blockedUsernamePatterns: [String] = SettingsState.defaultBlockedUsernamePatterns {
        didSet {
            recomputeActiveBlockedPatterns()
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
        onActiveBlockedPatternsChange?(activeBlockedPatterns)
    }

    /// Live push to `PeerConnectionPool` — wired by AppState.
    var onActiveBlockedPatternsChange: (([UsernamePatternMatcher.Compiled]) -> Void)?

    // MARK: - Launch at Login Sync

    /// Sync launchAtLogin state from the system (user may toggle it in System Settings)
    func syncLaunchAtLoginState() {
        isLoading = true
        defer { isLoading = false }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Persistence

    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?

    /// Persist UserDefaults immediately; debounce only the DB write.
    /// Xcode Stop / rebuild often kills the process before a 500ms Task
    /// runs, which used to drop the last toggle (grouping, paths, etc.).
    func save() {
        guard hasLoaded, !isLoading else { return }
        persistToUserDefaults()
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.pendingSaveTask = nil
            await self.saveToDatabase()
        }
    }

    /// Write the UserDefaults mirror used at next launch.
    private func persistToUserDefaults() {
        defaults.set(listenPort, forKey: listenPortKey)
        defaults.set(enableUPnP, forKey: enableUPnPKey)
        defaults.set(maxDownloadSlots, forKey: maxDownloadSlotsKey)
        defaults.set(maxUploadSlots, forKey: maxUploadSlotsKey)
        defaults.set(uploadSpeedLimit, forKey: uploadSpeedLimitKey)
        defaults.set(downloadSpeedLimit, forKey: downloadSpeedLimitKey)
        defaults.set(maxSearchResults, forKey: maxSearchResultsKey)
        defaults.set(groupSearchResults, forKey: groupSearchResultsKey)
        if let data = try? JSONEncoder().encode(searchFilters) {
            defaults.set(data, forKey: searchFiltersKey)
        }
        if let data = try? JSONEncoder().encode(searchFilterPresets) {
            defaults.set(data, forKey: searchFilterPresetsKey)
        }
        defaults.set(downloadLocation.path, forKey: downloadLocationKey)
        defaults.set(incompleteLocation.path, forKey: incompleteLocationKey)
        defaults.set(downloadFolderFormat.rawValue, forKey: downloadFolderFormatKey)
        defaults.set(downloadFolderTemplate, forKey: downloadFolderTemplateKey)
        defaults.set(launchAtLogin, forKey: launchAtLoginKey)
        defaults.set(showInMenuBar, forKey: showInMenuBarKey)
        defaults.set(appearance.rawValue, forKey: appearanceKey)
        defaults.set(connectAtLaunch, forKey: connectAtLaunchKey)
        defaults.set(notifyDownloads, forKey: notifyDownloadsKey)
        defaults.set(notifyUploads, forKey: notifyUploadsKey)
        defaults.set(notifyPrivateMessages, forKey: notifyPrivateMessagesKey)
        defaults.set(notifyWishlist, forKey: notifyWishlistKey)
        defaults.set(notifyLeechers, forKey: notifyLeechersKey)
        defaults.set(notifyOnlyInBackground, forKey: notifyOnlyInBackgroundKey)
        defaults.set(selectedNotificationSound.rawValue, forKey: notificationSoundNameKey)
        defaults.set(blockLeechPatternsEnabled, forKey: blockLeechPatternsEnabledKey)
        defaults.set(blockedUsernamePatterns, forKey: blockedUsernamePatternsKey)
        defaults.set(showJoinLeaveMessages, forKey: showJoinLeaveMessagesKey)
        defaults.set(autoJoinRooms, forKey: autoJoinRoomsKey)
        defaults.set(enableNotifications, forKey: enableNotificationsKey)
        defaults.set(notificationSound, forKey: notificationSoundEnabledKey)
        defaults.set(rescanOnStartup, forKey: rescanOnStartupKey)
        defaults.set(shareHiddenFiles, forKey: shareHiddenFilesKey)
        defaults.set(autoFetchMetadata, forKey: autoFetchMetadataKey)
        defaults.set(autoFetchAlbumArt, forKey: autoFetchAlbumArtKey)
        defaults.set(embedAlbumArt, forKey: embedAlbumArtKey)
        defaults.set(setFolderIcons, forKey: setFolderIconsKey)
        defaults.set(organizeDownloads, forKey: organizeDownloadsKey)
        defaults.set(organizationPattern, forKey: organizationPatternKey)
        defaults.set(showOnlineStatus, forKey: showOnlineStatusKey)
        defaults.set(allowBrowsing, forKey: allowBrowsingKey)
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
        defer {
            isLoading = false
            hasLoaded = true
        }

        logger.info("Loading settings from UserDefaults...")
        if defaults.object(forKey: listenPortKey) != nil {
            let savedPort = defaults.integer(forKey: listenPortKey)
            logger.info("Found saved listenPort: \(savedPort)")
            listenPort = savedPort
        } else {
            logger.info("No saved listenPort, using default: \(self.listenPort)")
        }
        if defaults.object(forKey: enableUPnPKey) != nil {
            enableUPnP = defaults.bool(forKey: enableUPnPKey)
        }
        if defaults.object(forKey: maxDownloadSlotsKey) != nil {
            maxDownloadSlots = defaults.integer(forKey: maxDownloadSlotsKey)
        }
        if defaults.object(forKey: maxUploadSlotsKey) != nil {
            maxUploadSlots = defaults.integer(forKey: maxUploadSlotsKey)
        }
        if defaults.object(forKey: uploadSpeedLimitKey) != nil {
            uploadSpeedLimit = defaults.integer(forKey: uploadSpeedLimitKey)
        }
        if defaults.object(forKey: downloadSpeedLimitKey) != nil {
            downloadSpeedLimit = defaults.integer(forKey: downloadSpeedLimitKey)
        }
        if defaults.object(forKey: maxSearchResultsKey) != nil {
            maxSearchResults = defaults.integer(forKey: maxSearchResultsKey)
        }
        if defaults.object(forKey: groupSearchResultsKey) != nil {
            groupSearchResults = defaults.bool(forKey: groupSearchResultsKey)
        }
        if let data = defaults.data(forKey: searchFiltersKey),
           let filters = try? JSONDecoder().decode(PersistedSearchFilters.self, from: data) {
            searchFilters = filters
        }
        if let data = defaults.data(forKey: searchFilterPresetsKey),
           let presets = try? JSONDecoder().decode([SearchFilterPreset].self, from: data) {
            searchFilterPresets = presets
        }
        if let downloadPath = defaults.string(forKey: downloadLocationKey) {
            downloadLocation = URL(fileURLWithPath: downloadPath)
        }
        if let incompletePath = defaults.string(forKey: incompleteLocationKey) {
            incompleteLocation = URL(fileURLWithPath: incompletePath)
        }
        if let formatRaw = defaults.string(forKey: downloadFolderFormatKey),
           let format = DownloadFolderFormat(rawValue: formatRaw) {
            downloadFolderFormat = format
        }
        if let template = defaults.string(forKey: downloadFolderTemplateKey) {
            downloadFolderTemplate = template
        }
        migrateDownloadDefaultsIfNeeded()
        if defaults.object(forKey: showInMenuBarKey) != nil {
            showInMenuBar = defaults.bool(forKey: showInMenuBarKey)
        }
        if let raw = defaults.string(forKey: appearanceKey),
           let value = AppAppearance(rawValue: raw) {
            appearance = value
        }
        connectAtLaunch = defaults.bool(forKey: connectAtLaunchKey)
        if defaults.object(forKey: notifyDownloadsKey) != nil {
            notifyDownloads = defaults.bool(forKey: notifyDownloadsKey)
        }
        if defaults.object(forKey: notifyUploadsKey) != nil {
            notifyUploads = defaults.bool(forKey: notifyUploadsKey)
        }
        if defaults.object(forKey: notifyPrivateMessagesKey) != nil {
            notifyPrivateMessages = defaults.bool(forKey: notifyPrivateMessagesKey)
        }
        if defaults.object(forKey: notifyWishlistKey) != nil {
            notifyWishlist = defaults.bool(forKey: notifyWishlistKey)
        }
        if defaults.object(forKey: notifyLeechersKey) != nil {
            notifyLeechers = defaults.bool(forKey: notifyLeechersKey)
        }
        if defaults.object(forKey: notifyOnlyInBackgroundKey) != nil {
            notifyOnlyInBackground = defaults.bool(forKey: notifyOnlyInBackgroundKey)
        }
        if let soundRaw = defaults.string(forKey: notificationSoundNameKey),
           let sound = NotificationSound(rawValue: soundRaw) {
            selectedNotificationSound = sound
        }
        if defaults.object(forKey: blockLeechPatternsEnabledKey) != nil {
            blockLeechPatternsEnabled = defaults.bool(forKey: blockLeechPatternsEnabledKey)
        }
        if let patterns = defaults.stringArray(forKey: blockedUsernamePatternsKey) {
            blockedUsernamePatterns = patterns
        }
        if defaults.object(forKey: showJoinLeaveMessagesKey) != nil {
            showJoinLeaveMessages = defaults.bool(forKey: showJoinLeaveMessagesKey)
        }
        if let rooms = defaults.stringArray(forKey: autoJoinRoomsKey) {
            autoJoinRooms = rooms
        } else if defaults.object(forKey: listenPortKey) == nil {
            autoJoinRooms = SettingsState.defaultAutoJoinRooms
        }
        if defaults.object(forKey: enableNotificationsKey) != nil {
            enableNotifications = defaults.bool(forKey: enableNotificationsKey)
        }
        if defaults.object(forKey: notificationSoundEnabledKey) != nil {
            notificationSound = defaults.bool(forKey: notificationSoundEnabledKey)
        }
        if defaults.object(forKey: rescanOnStartupKey) != nil {
            rescanOnStartup = defaults.bool(forKey: rescanOnStartupKey)
        }
        if defaults.object(forKey: shareHiddenFilesKey) != nil {
            shareHiddenFiles = defaults.bool(forKey: shareHiddenFilesKey)
        }
        if defaults.object(forKey: autoFetchMetadataKey) != nil {
            autoFetchMetadata = defaults.bool(forKey: autoFetchMetadataKey)
        }
        if defaults.object(forKey: autoFetchAlbumArtKey) != nil {
            autoFetchAlbumArt = defaults.bool(forKey: autoFetchAlbumArtKey)
        }
        if defaults.object(forKey: embedAlbumArtKey) != nil {
            embedAlbumArt = defaults.bool(forKey: embedAlbumArtKey)
        }
        if defaults.object(forKey: setFolderIconsKey) != nil {
            setFolderIcons = defaults.bool(forKey: setFolderIconsKey)
        }
        if defaults.object(forKey: organizeDownloadsKey) != nil {
            organizeDownloads = defaults.bool(forKey: organizeDownloadsKey)
        }
        if let pattern = defaults.string(forKey: organizationPatternKey) {
            organizationPattern = pattern
        }
        if defaults.object(forKey: showOnlineStatusKey) != nil {
            showOnlineStatus = defaults.bool(forKey: showOnlineStatusKey)
        }
        if defaults.object(forKey: allowBrowsingKey) != nil {
            allowBrowsing = defaults.bool(forKey: allowBrowsingKey)
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
        // didSet hooks are suppressed while isLoading — re-push values the
        // network layer consumes, in case it was wired before this load.
        onSearchResponsePolicyChange?(searchResponsePolicy)
        onMaxUploadSlotsChange?(maxUploadSlots)
        onUploadSpeedLimitChange?(uploadSpeedLimit)
        onDownloadSettingsChange?()
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
