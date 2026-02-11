import Foundation
import os

actor GitHubUpdateClient {
    private let logger = Logger(subsystem: "com.seeleseek", category: "GitHubUpdateClient")
    private let session = URLSession.shared
    private let baseURL = "https://api.github.com/repos/bretth18/seeleseek/releases/latest"

    struct UpdateResult {
        let release: GitHubRelease
        let pkgAsset: GitHubAsset?
        let isNewer: Bool
    }

    func fetchLatestRelease(currentVersion: String) async throws -> UpdateResult {
        guard let url = URL(string: baseURL) else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleasesFound
            }
            throw UpdateError.httpError(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        guard !release.draft, !release.prerelease else {
            throw UpdateError.noStableRelease
        }

        let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
        let isNewer = Self.isVersion(release.tagName, newerThan: currentVersion)

        logger.info("Latest release: \(release.tagName), current: \(currentVersion), newer: \(isNewer)")

        return UpdateResult(release: release, pkgAsset: pkgAsset, isNewer: isNewer)
    }

    func downloadPkg(from urlString: String, version: String, onProgress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.seeleseek/updates", isDirectory: true)

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destination = cacheDir.appendingPathComponent("SeeleSeek-\(version).pkg")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destination)

        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = httpResponse.expectedContentLength
        var downloadedBytes: Int64 = 0
        var fileData = Data()

        if expectedLength > 0 {
            fileData.reserveCapacity(Int(expectedLength))
        }

        for try await byte in bytes {
            fileData.append(byte)
            downloadedBytes += 1

            if expectedLength > 0, downloadedBytes % 65536 == 0 {
                let progress = Double(downloadedBytes) / Double(expectedLength)
                onProgress(min(progress, 1.0))
            }
        }

        onProgress(1.0)

        try fileData.write(to: destination)
        logger.info("Downloaded \(downloadedBytes) bytes to \(destination.path)")

        return destination
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteParts = parseVersion(remote)
        let localParts = parseVersion(local)

        let maxCount = max(remoteParts.count, localParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private static func parseVersion(_ version: String) -> [Int] {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned.split(separator: ".").compactMap { Int($0) }
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noReleasesFound
    case noStableRelease
    case noPkgAsset
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .invalidResponse: "Invalid server response"
        case .httpError(let code): "Server returned status \(code)"
        case .noReleasesFound: "No releases found"
        case .noStableRelease: "No stable release available"
        case .noPkgAsset: "No .pkg installer found in release"
        case .downloadFailed: "Download failed"
        }
    }
}
