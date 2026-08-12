import Foundation
@testable import SeeleseekCore

@MainActor
final class MockDownloadSettings: DownloadSettingsProviding {
    var downloadDirectory: URL
    var activeDownloadTemplate: String
    var incompleteDownloadDirectory: URL
    var setFolderIcons: Bool = false

    init(downloadDirectory: URL, template: String = DownloadManager.fallbackTemplate) {
        self.downloadDirectory = downloadDirectory
        self.activeDownloadTemplate = template
        self.incompleteDownloadDirectory = downloadDirectory.appendingPathComponent("Incomplete")
    }
}

/// Returns tags only for paths explicitly registered, so tests can model a
/// mixed folder: tagged tracks, an untagged track, and cover art.
final class MockMetadataReader: MetadataReading, @unchecked Sendable {
    var metadata: [URL: AudioFileMetadata] = [:]

    func extractAudioMetadata(from url: URL) async -> AudioFileMetadata? { metadata[url] }
    func extractArtwork(from url: URL) async -> Data? { nil }
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool { false }
}
