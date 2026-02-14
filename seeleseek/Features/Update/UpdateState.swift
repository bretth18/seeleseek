import Foundation
import os
#if os(macOS)
import AppKit
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
    private let lastCheckKey = "update.lastCheckDate"
    private let autoCheckKey = "update.autoCheckEnabled"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var currentFullVersion: String {
        "\(currentVersion) (\(currentBuild))"
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoCheckKey) }
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
            let result = try await updateClient.fetchLatestRelease(currentVersion: "\(currentVersion).\(currentBuild)")

            updateAvailable = result.isNewer
            latestVersion = result.release.tagName
            releaseNotes = result.release.body

            if let htmlUrl = URL(string: result.release.htmlUrl) {
                latestReleaseURL = htmlUrl
            }

            if let pkg = result.pkgAsset, let url = URL(string: pkg.browserDownloadUrl) {
                latestPkgURL = url
            }

            if !result.isNewer {
                logger.info("App is up to date")
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

        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let lastCheckDate = Date(timeIntervalSince1970: lastCheck)
        let hoursSinceLastCheck = Date().timeIntervalSince(lastCheckDate) / 3600

        guard lastCheck == 0 || hoursSinceLastCheck >= 24 else { return }

        Task {
            await checkForUpdate()
        }
    }
}
