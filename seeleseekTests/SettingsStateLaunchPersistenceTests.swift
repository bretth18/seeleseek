import Foundation
import Testing
@testable import seeleseek

/// Regression for launch-at-login wiping prefs: MenuBarExtra (and other
/// bindings) can call `save()` while `SettingsState` still holds factory
/// defaults, before `configure()` → `load()` restores UserDefaults.
@MainActor
@Suite("SettingsState launch persistence")
struct SettingsStateLaunchPersistenceTests {

    @Test("Pre-load save does not wipe grouping, download path, or notifyDownloads")
    func preLoadSaveDoesNotWipePrefs() async throws {
        let defaults = TestDefaults.isolated()
        let customPath = "/tmp/seeleseek-custom-downloads"
        defaults.set(true, forKey: "settingsGroupSearchResults")
        defaults.set(customPath, forKey: "settingsDownloadLocation")
        defaults.set(false, forKey: "settingsNotifyDownloads")
        // Skip one-shot download-path migration so it cannot rewrite the seed.
        defaults.set(true, forKey: "settingsDownloadDefaultsMigratedV2")

        let settings = SettingsState(defaults: defaults)
        // Same write MenuBarExtra's isInserted binding can fire on first frame.
        settings.showInMenuBar = true
        try await Task.sleep(for: .milliseconds(700))

        #expect(defaults.bool(forKey: "settingsGroupSearchResults") == true)
        #expect(defaults.string(forKey: "settingsDownloadLocation") == customPath)
        #expect(defaults.bool(forKey: "settingsNotifyDownloads") == false)
    }

    @Test("Notification, metadata, shares, and privacy toggles round-trip through load")
    func previouslyUnpersistedTogglesRoundTrip() {
        let defaults = TestDefaults.isolated()
        defaults.set(true, forKey: "settingsDownloadDefaultsMigratedV2")

        let settings = SettingsState(defaults: defaults)
        settings.load()

        settings.enableNotifications = false
        settings.notificationSound = false
        settings.rescanOnStartup = false
        settings.shareHiddenFiles = true
        settings.autoFetchMetadata = false
        settings.autoFetchAlbumArt = false
        settings.embedAlbumArt = false
        settings.setFolderIcons = false
        settings.organizeDownloads = true
        settings.organizationPattern = "{album}/{filename}"
        settings.showOnlineStatus = false
        settings.allowBrowsing = false

        let restored = SettingsState(defaults: defaults)
        restored.load()

        #expect(restored.enableNotifications == false)
        #expect(restored.notificationSound == false)
        #expect(restored.rescanOnStartup == false)
        #expect(restored.shareHiddenFiles == true)
        #expect(restored.autoFetchMetadata == false)
        #expect(restored.autoFetchAlbumArt == false)
        #expect(restored.embedAlbumArt == false)
        #expect(restored.setFolderIcons == false)
        #expect(restored.organizeDownloads == true)
        #expect(restored.organizationPattern == "{album}/{filename}")
        #expect(restored.showOnlineStatus == false)
        #expect(restored.allowBrowsing == false)
    }
}
