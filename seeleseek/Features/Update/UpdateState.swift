import Foundation
import os
#if os(macOS)
import AppKit
import SeeleseekCore
#endif

@MainActor
@Observable
final class UpdateState {
    private let logger = Logger(subsystem: "com.seeleseek", category: "UpdateState")

    private let updateClient = GitHubUpdateClient()

    // State
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var updateAvailable: Bool = false
    var latestVersion: String?
    var latestReleaseURL: URL?
    var latestPkgURL: URL?
    var releaseNotes: String?
    var lastCheckDate: Date?
    var errorMessage: String?
    var downloadProgress: Double?
    var downloadedPkgURL: URL?

    // UserDefaults keys
    private let lastCheckKey = "updateLastCheckDate"
    private let autoCheckKey = "updateAutoCheckEnabled"
    private let skippedVersionKey = "updateSkippedVersion"

    /// Whether the launch prompt sheet should be shown. Separate from
    /// `updateAvailable` so Settings can show update info without auto-popping
    /// the sheet, and so "Skip this version" suppresses future prompts.
    var showUpdatePrompt: Bool = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var currentFullVersion: String {
        "\(currentVersion) (\(currentBuild))"
    }
    
    var currentFullVersionFormatted: String {
        "\(currentVersion).\(currentBuild)"
    }

    var autoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoCheckKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoCheckKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    func checkForUpdate() async {
        isChecking = true
        errorMessage = nil

        defer {
            isChecking = false
            lastCheckDate = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        }

        do {
            let currentFull = "\(currentVersion).\(currentBuild)"
            logger.info("Update check: current=\(currentFull) skipped=\(self.skippedVersion ?? "<none>")")
            let result = try await updateClient.fetchLatestRelease(currentVersion: currentFull)

            updateAvailable = result.isNewer
            latestVersion = result.release.tagName
            releaseNotes = result.release.body

            if let htmlUrl = URL(string: result.release.htmlUrl) {
                latestReleaseURL = htmlUrl
            }

            if let pkg = result.pkgAsset, let url = URL(string: pkg.browserDownloadUrl) {
                latestPkgURL = url
            }

            logger.info("Update check: latest=\(result.release.tagName) isNewer=\(result.isNewer) pkg=\(result.pkgAsset?.browserDownloadUrl ?? "<none>")")

            if !result.isNewer {
                logger.info("App is up to date")
            } else if latestVersion == skippedVersion {
                logger.info("Update \(self.latestVersion ?? "?") available but user skipped it")
            } else {
                logger.info("Update available — opening prompt window")
                showUpdatePrompt = true
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func downloadAndInstall() async {
        guard let pkgAsset = latestPkgURL, let version = latestVersion else { return }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            let pkgURL = try await updateClient.downloadPkg(
                from: pkgAsset.absoluteString,
                version: version,
                onProgress: { @Sendable [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress
                    }
                }
            )

            downloadedPkgURL = pkgURL
            isDownloading = false
            downloadProgress = nil

            #if os(macOS)
            NSWorkspace.shared.open(pkgURL)
            #endif
        } catch {
            logger.error("Download failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isDownloading = false
            downloadProgress = nil
        }
    }

    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedVersionKey) }
    }

    func skipCurrentVersion() {
        skippedVersion = latestVersion
        showUpdatePrompt = false
    }

    func remindLater() {
        showUpdatePrompt = false
    }

    func dismissUpdate() {
        updateAvailable = false
        latestVersion = nil
        releaseNotes = nil
        latestReleaseURL = nil
        latestPkgURL = nil
        errorMessage = nil
    }

    func checkOnLaunch() {
        guard autoCheckEnabled else { return }
        // Always check on launch — the 24h cooldown was for polling during a
        // long-running session, which we don't do. If an update exists and
        // wasn't skipped, the prompt window opens.
        Task { await checkForUpdate() }
    }
}
