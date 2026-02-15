import AVFoundation
import AppKit
import os

/// Off-main-thread actor for reading metadata (especially artwork) from audio files.
/// Supports MP3 (ID3v2), FLAC (Vorbis Comment + PICTURE), and AIF/AIFF.
actor MetadataReader {
    private let logger = Logger(subsystem: "com.seeleseek", category: "MetadataReader")

    /// Extract embedded album artwork from an audio file.
    /// Returns the raw image data (JPEG or PNG) or nil if none found.
    func extractArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.commonMetadata)
            let artworkItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .commonIdentifierArtwork
            )
            if let item = artworkItems.first {
                return try await item.load(.dataValue)
            }
        } catch {
            logger.debug("Failed to extract artwork from \(url.lastPathComponent): \(error.localizedDescription)")
        }
        return nil
    }

    /// Scan a directory for the first audio file with embedded artwork and return the image data.
    /// Checks common audio extensions: mp3, flac, aif, aiff, m4a, ogg.
    func extractArtworkFromDirectory(_ directory: URL) async -> Data? {
        let audioExtensions: Set<String> = ["mp3", "flac", "aif", "aiff", "m4a", "ogg"]

        // Collect audio file URLs synchronously to avoid Swift 6 async-safety warning
        let audioFiles: [URL] = {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                return []
            }
            var files: [URL] = []
            for case let fileURL as URL in enumerator {
                if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                    files.append(fileURL)
                }
            }
            return files
        }()

        for fileURL in audioFiles {
            if let artwork = await extractArtwork(from: fileURL) {
                logger.info("Found artwork in \(fileURL.lastPathComponent)")
                return artwork
            }
        }
        return nil
    }

    /// Set a folder's Finder icon from image data.
    /// Returns true on success.
    @discardableResult
    func setFolderIcon(imageData: Data, forDirectory directory: URL) -> Bool {
        guard let image = NSImage(data: imageData) else {
            logger.warning("Could not create NSImage from artwork data")
            return false
        }
        let success = NSWorkspace.shared.setIcon(image, forFile: directory.path, options: [])
        if success {
            logger.info("Set folder icon for \(directory.lastPathComponent)")
        } else {
            logger.warning("Failed to set folder icon for \(directory.lastPathComponent)")
        }
        return success
    }

    /// Extract artwork from a directory and apply it as the folder icon.
    /// Convenience method combining extractArtworkFromDirectory + setFolderIcon.
    /// Returns true if artwork was found and applied.
    @discardableResult
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool {
        guard let artwork = await extractArtworkFromDirectory(directory) else {
            return false
        }
        return setFolderIcon(imageData: artwork, forDirectory: directory)
    }
}
