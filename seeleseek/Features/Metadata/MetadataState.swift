import SwiftUI
import os
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

    // Parsed from filename (used for search)
    var detectedArtist: String = ""
    var detectedTitle: String = ""

    // MARK: - Editable Metadata Fields
    var editTitle: String = ""
    var editArtist: String = ""
    var editAlbum: String = ""
    var editYear: String = ""
    var editTrackNumber: String = ""
    var editGenre: String = ""

    // Search results
    var searchResults: [MusicBrainzClient.MBRecording] = []
    var selectedRecording: MusicBrainzClient.MBRecording?
    var selectedRelease: MusicBrainzClient.MBRelease?

    // Cover art
    var coverArtData: Data?
    var coverArtURL: URL?
    var isLoadingCoverArt = false
    var coverArtSource: CoverArtSource = .none

    enum CoverArtSource {
        case none
        case musicBrainz
        case manual
    }

    // State
    var isSearching = false
    var searchError: String?
    var isApplying = false
    var applyError: String?

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
            editArtist = metadata.artist
            editTitle = metadata.title
            editAlbum = metadata.album ?? ""
            editTrackNumber = metadata.trackNumber.map { String($0) } ?? ""
        } else {
            let parsed = parseFilename(currentFilename)
            detectedArtist = parsed.artist
            detectedTitle = parsed.title
            editArtist = parsed.artist
            editTitle = parsed.title
            editAlbum = ""
            editTrackNumber = ""
        }

        // Clear other editable fields
        editYear = ""
        editGenre = ""

        // Clear previous state
        searchResults = []
        selectedRecording = nil
        selectedRelease = nil
        coverArtData = nil
        coverArtURL = nil
        coverArtSource = .none
        searchError = nil
        applyError = nil

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
        editTitle = ""
        editArtist = ""
        editAlbum = ""
        editYear = ""
        editTrackNumber = ""
        editGenre = ""
        searchResults = []
        selectedRecording = nil
        selectedRelease = nil
        coverArtData = nil
        coverArtURL = nil
        coverArtSource = .none
        applyError = nil
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

        // Populate editable fields from the recording
        editTitle = recording.title
        editArtist = recording.artist
        editAlbum = recording.releaseTitle ?? ""

        // Also update search fields for next search
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

            // Populate year from release date
            if let date = release.date, date.count >= 4 {
                editYear = String(date.prefix(4))
            }

            // Update album name from release
            editAlbum = release.title
        } catch {
            logger.warning("Failed to fetch release: \(error.localizedDescription)")
        }

        // Only fetch cover art if we don't already have manual cover art
        guard coverArtSource != .manual else {
            logger.info("Skipping cover art fetch - manual art already set")
            return
        }

        // Clear previous MusicBrainz cover art before fetching new one
        coverArtData = nil
        coverArtURL = nil
        coverArtSource = .none

        // Fetch cover art from Cover Art Archive
        isLoadingCoverArt = true
        do {
            logger.info("Fetching cover art for release \(releaseMBID)...")
            if let data = try await coverArtArchive.getCoverArt(releaseMBID: releaseMBID, size: .medium) {
                coverArtData = data
                coverArtSource = .musicBrainz
                logger.info("Loaded cover art for release \(releaseMBID) (\(data.count) bytes)")
            } else {
                logger.info("No cover art available for release \(releaseMBID)")
            }
            coverArtURL = try await coverArtArchive.getFrontCoverURL(releaseMBID: releaseMBID, size: .large)
        } catch {
            logger.warning("Failed to fetch cover art: \(error.localizedDescription)")
        }
        isLoadingCoverArt = false
    }

    /// Set cover art manually from image data
    func setCoverArt(_ data: Data) {
        coverArtData = data
        coverArtSource = .manual
        coverArtURL = nil
        logger.info("Manual cover art set (\(data.count) bytes)")
    }

    /// Clear cover art
    func clearCoverArt() {
        coverArtData = nil
        coverArtSource = .none
        coverArtURL = nil
    }

    #if os(macOS)
    /// Open file picker to select cover art image
    func selectCoverArtFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select Cover Art"
        panel.message = "Choose an image file for album artwork"

        if panel.runModal() == .OK, let url = panel.url {
            loadCoverArtFromFile(url)
        }
    }

    /// Load cover art from a file URL
    func loadCoverArtFromFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            // Verify it's a valid image
            if NSImage(data: data) != nil {
                setCoverArt(data)
            } else {
                logger.error("Invalid image file: \(url.path)")
            }
        } catch {
            logger.error("Failed to load cover art: \(error.localizedDescription)")
        }
    }
    #endif

    /// Apply selected metadata to the file
    /// Returns true if metadata can be applied (validation passed)
    func applyMetadata() async -> Bool {
        guard let filePath = currentFilePath else {
            applyError = "No file selected"
            return false
        }

        // At minimum need title or artist
        guard !editTitle.isEmpty || !editArtist.isEmpty else {
            applyError = "Please enter at least a title or artist"
            return false
        }

        isApplying = true
        applyError = nil

        // Collect metadata to apply
        let metadata = EditableMetadata(
            title: editTitle,
            artist: editArtist,
            album: editAlbum,
            year: editYear,
            trackNumber: Int(editTrackNumber),
            genre: editGenre,
            coverArt: coverArtData
        )

        logger.info("Applying metadata to file: \(filePath.path)")
        logger.info("  Title: \(metadata.title)")
        logger.info("  Artist: \(metadata.artist)")
        logger.info("  Album: \(metadata.album)")
        logger.info("  Year: \(metadata.year)")
        logger.info("  Track: \(metadata.trackNumber ?? 0)")
        logger.info("  Genre: \(metadata.genre)")
        logger.info("  Cover art: \(metadata.coverArt != nil ? "\(metadata.coverArt!.count) bytes" : "none")")

        // TODO: Implement actual ID3 tag writing
        // This would require a library like ID3TagEditor or TagLib
        // For now, just simulate success
        try? await Task.sleep(for: .milliseconds(500))

        isApplying = false
        return true
    }

    /// Metadata structure for applying to files
    struct EditableMetadata {
        let title: String
        let artist: String
        let album: String
        let year: String
        let trackNumber: Int?
        let genre: String
        let coverArt: Data?
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
