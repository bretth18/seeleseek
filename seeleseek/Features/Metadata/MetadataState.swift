import SwiftUI
import os

/// State management for metadata enrichment
@Observable
@MainActor
final class MetadataState {
    private let logger = Logger(subsystem: "com.seeleseek", category: "MetadataState")

    // MARK: - Services
    let musicBrainz = MusicBrainzClient()
    let coverArtArchive = CoverArtArchive()

    // MARK: - Editor State
    var isEditorPresented = false
    var currentFilePath: URL?
    var currentFilename: String = ""

    // Parsed from filename
    var detectedArtist: String = ""
    var detectedTitle: String = ""

    // Search results
    var searchResults: [MusicBrainzClient.MBRecording] = []
    var selectedRecording: MusicBrainzClient.MBRecording?
    var selectedRelease: MusicBrainzClient.MBRelease?

    // Cover art
    var coverArtData: Data?
    var coverArtURL: URL?
    var isLoadingCoverArt = false

    // State
    var isSearching = false
    var searchError: String?
    var isApplying = false

    // MARK: - Configuration
    var autoEnrichOnDownload = false
    var showEditorOnDownload = false

    // MARK: - Actions

    /// Show the metadata editor for a downloaded file
    func showEditor(for filePath: URL, detectedMetadata: DetectedMetadata? = nil) {
        currentFilePath = filePath
        currentFilename = filePath.lastPathComponent

        // Use detected metadata or parse from filename
        if let metadata = detectedMetadata {
            detectedArtist = metadata.artist
            detectedTitle = metadata.title
        } else {
            let parsed = parseFilename(currentFilename)
            detectedArtist = parsed.artist
            detectedTitle = parsed.title
        }

        // Clear previous state
        searchResults = []
        selectedRecording = nil
        selectedRelease = nil
        coverArtData = nil
        coverArtURL = nil
        searchError = nil

        isEditorPresented = true

        // Auto-search if we have metadata
        if !detectedArtist.isEmpty || !detectedTitle.isEmpty {
            Task {
                await search()
            }
        }
    }

    /// Close the metadata editor
    func closeEditor() {
        isEditorPresented = false
        currentFilePath = nil
        currentFilename = ""
        detectedArtist = ""
        detectedTitle = ""
        searchResults = []
        selectedRecording = nil
        selectedRelease = nil
        coverArtData = nil
        coverArtURL = nil
    }

    /// Search MusicBrainz for matching recordings
    func search() async {
        guard !detectedArtist.isEmpty || !detectedTitle.isEmpty else {
            searchError = "Enter artist or title to search"
            return
        }

        isSearching = true
        searchError = nil

        do {
            let results = try await musicBrainz.searchRecording(
                artist: detectedArtist,
                title: detectedTitle,
                limit: 15
            )

            searchResults = results
            logger.info("Found \(results.count) recordings")

            // Auto-select first result if high confidence
            if let first = results.first, first.score >= 90 {
                await selectRecording(first)
            }
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            searchError = error.localizedDescription
        }

        isSearching = false
    }

    /// Select a recording from search results
    func selectRecording(_ recording: MusicBrainzClient.MBRecording) async {
        selectedRecording = recording
        detectedArtist = recording.artist
        detectedTitle = recording.title

        // Fetch release details and cover art if available
        if let releaseMBID = recording.releaseMBID {
            await fetchReleaseAndCoverArt(releaseMBID: releaseMBID)
        }
    }

    /// Fetch release details and cover art
    private func fetchReleaseAndCoverArt(releaseMBID: String) async {
        // Fetch release details
        do {
            let release = try await musicBrainz.getRelease(mbid: releaseMBID)
            selectedRelease = release
        } catch {
            logger.warning("Failed to fetch release: \(error.localizedDescription)")
        }

        // Fetch cover art
        isLoadingCoverArt = true
        do {
            if let data = try await coverArtArchive.getCoverArt(releaseMBID: releaseMBID, size: .medium) {
                coverArtData = data
                logger.info("Loaded cover art for release \(releaseMBID)")
            }
            coverArtURL = try await coverArtArchive.getFrontCoverURL(releaseMBID: releaseMBID, size: .large)
        } catch {
            logger.warning("Failed to fetch cover art: \(error.localizedDescription)")
        }
        isLoadingCoverArt = false
    }

    /// Apply selected metadata to the file
    func applyMetadata() async -> Bool {
        guard let _ = currentFilePath, selectedRecording != nil else {
            return false
        }

        isApplying = true

        // TODO: Implement actual ID3 tag writing
        // This would require a library like ID3TagEditor or TagLib
        // For now, just simulate success
        logger.info("Would apply metadata to file: artist=\(self.detectedArtist) title=\(self.detectedTitle)")

        try? await Task.sleep(for: .milliseconds(500))

        isApplying = false
        return true
    }

    // MARK: - Filename Parsing

    struct DetectedMetadata {
        let artist: String
        let title: String
        let album: String?
        let trackNumber: Int?
    }

    /// Parse artist and title from filename
    func parseFilename(_ filename: String) -> (artist: String, title: String) {
        // Remove extension
        let name = (filename as NSString).deletingPathExtension

        // Common patterns:
        // "Artist - Title"
        // "01 - Title"
        // "01. Title"
        // "Artist - Album - 01 - Title"

        // Try "Artist - Title" pattern
        let dashParts = name.components(separatedBy: " - ")
        if dashParts.count >= 2 {
            // Check if first part is a track number
            let firstPart = dashParts[0].trimmingCharacters(in: .whitespaces)
            if firstPart.count <= 3 && Int(firstPart) != nil {
                // First part is track number, treat rest as title
                return ("", dashParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces))
            }

            // Otherwise, first part is artist
            let artist = firstPart
            let title = dashParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)

            // Remove track number prefix from title if present
            let cleanTitle = removeTrackNumber(title)
            return (artist, cleanTitle)
        }

        // Try "01. Title" pattern
        if let dotRange = name.range(of: ". ", range: name.startIndex..<name.endIndex) {
            let prefix = String(name[..<dotRange.lowerBound])
            if prefix.count <= 3 && Int(prefix.trimmingCharacters(in: .whitespaces)) != nil {
                let title = String(name[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                return ("", title)
            }
        }

        // No pattern matched, return filename as title
        return ("", name.trimmingCharacters(in: .whitespaces))
    }

    private func removeTrackNumber(_ title: String) -> String {
        // Remove leading track number patterns like "01 ", "01. ", "1 - "
        let patterns = [
            "^\\d{1,3}\\.?\\s+",  // "01 " or "01. "
            "^\\d{1,3}\\s*-\\s*"   // "01 - "
        ]

        var result = title
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
