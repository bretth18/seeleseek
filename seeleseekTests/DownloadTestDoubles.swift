import Foundation
@testable import SeeleseekCore

@MainActor
final class MockDownloadSettings: DownloadSettingsProviding {
    var downloadLocation: URL
    var activeDownloadTemplate: String
    var incompleteDownloadDirectory: URL
    var setFolderIcons: Bool = false

    init(downloadLocation: URL, template: String = DownloadManager.fallbackTemplate) {
        self.downloadLocation = downloadLocation
        self.activeDownloadTemplate = template
        self.incompleteDownloadDirectory = downloadLocation.appendingPathComponent("Incomplete")
    }
}

/// Returns tags only for registered paths, so a folder can mix tagged and
/// untagged files.
final class MockMetadataReader: MetadataReading, @unchecked Sendable {
    var metadata: [URL: AudioFileMetadata] = [:]

    func extractAudioMetadata(from url: URL) async -> AudioFileMetadata? { metadata[url] }
    func extractArtwork(from url: URL) async -> Data? { nil }
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool { false }
}
