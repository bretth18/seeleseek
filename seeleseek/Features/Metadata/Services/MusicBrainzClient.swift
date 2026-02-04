import Foundation
import os

/// Client for MusicBrainz API to look up music metadata
actor MusicBrainzClient {
    private let logger = Logger(subsystem: "com.seeleseek", category: "MusicBrainz")
    private let baseURL = "https://musicbrainz.org/ws/2"
    private let userAgent = "SeeleSeek/1.0 (https://github.com/seeleseek)"

    // Rate limiting: MusicBrainz allows 1 request per second
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.1

    // MARK: - Types

    struct MBRecording: Identifiable, Sendable {
        let id: String
        let title: String
        let artist: String
        let artistMBID: String?
        let releaseTitle: String?
        let releaseMBID: String?
        let duration: Int?  // milliseconds
        let score: Int  // Search relevance score (0-100)

        var durationSeconds: Int? {
            duration.map { $0 / 1000 }
        }
    }

    struct MBRelease: Identifiable, Sendable {
        let id: String
        let title: String
        let artist: String
        let artistMBID: String?
        let date: String?
        let country: String?
        let trackCount: Int
        let tracks: [MBTrack]
    }

    struct MBTrack: Identifiable, Sendable {
        let id: String
        let position: Int
        let title: String
        let duration: Int?  // milliseconds
    }

    struct SearchResponse: Decodable {
        let recordings: [RecordingResult]?
        let count: Int

        struct RecordingResult: Decodable {
            let id: String
            let title: String
            let score: Int
            let length: Int?
            let artistCredit: [ArtistCredit]?
            let releases: [ReleaseResult]?

            enum CodingKeys: String, CodingKey {
                case id, title, score, length
                case artistCredit = "artist-credit"
                case releases
            }
        }

        struct ArtistCredit: Decodable {
            let name: String
            let artist: ArtistInfo

            struct ArtistInfo: Decodable {
                let id: String
                let name: String
            }
        }

        struct ReleaseResult: Decodable {
            let id: String
            let title: String
        }
    }

    struct ReleaseResponse: Decodable {
        let id: String
        let title: String
        let date: String?
        let country: String?
        let artistCredit: [SearchResponse.ArtistCredit]?
        let media: [Media]?

        enum CodingKeys: String, CodingKey {
            case id, title, date, country
            case artistCredit = "artist-credit"
            case media
        }

        struct Media: Decodable {
            let position: Int
            let tracks: [Track]?

            struct Track: Decodable {
                let id: String
                let position: Int
                let title: String
                let length: Int?
            }
        }
    }

    // MARK: - API Methods

    /// Search for recordings by artist and title
    func searchRecording(artist: String, title: String, limit: Int = 10) async throws -> [MBRecording] {
        await enforceRateLimit()

        // Build search query
        var queryParts: [String] = []
        if !artist.isEmpty {
            queryParts.append("artist:\(escapeQuery(artist))")
        }
        if !title.isEmpty {
            queryParts.append("recording:\(escapeQuery(title))")
        }

        guard !queryParts.isEmpty else {
            return []
        }

        let query = queryParts.joined(separator: " AND ")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let urlString = "\(baseURL)/recording?query=\(encodedQuery)&limit=\(limit)&fmt=json"
        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString)")
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        logger.info("Searching MusicBrainz: artist=\(artist) title=\(title)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("MusicBrainz API error: \(httpResponse.statusCode)")
            throw MetadataError.apiError(httpResponse.statusCode)
        }

        let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)

        let recordings = (searchResponse.recordings ?? []).map { result in
            let artistName = result.artistCredit?.first?.name ?? ""
            let artistMBID = result.artistCredit?.first?.artist.id
            let release = result.releases?.first

            return MBRecording(
                id: result.id,
                title: result.title,
                artist: artistName,
                artistMBID: artistMBID,
                releaseTitle: release?.title,
                releaseMBID: release?.id,
                duration: result.length,
                score: result.score
            )
        }

        logger.info("Found \(recordings.count) recordings")
        return recordings
    }

    /// Get detailed release information
    func getRelease(mbid: String) async throws -> MBRelease {
        await enforceRateLimit()

        let urlString = "\(baseURL)/release/\(mbid)?inc=artist-credits+recordings&fmt=json"
        guard let url = URL(string: urlString) else {
            throw MetadataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        logger.info("Fetching release: \(mbid)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw MetadataError.apiError(httpResponse.statusCode)
        }

        let releaseResponse = try JSONDecoder().decode(ReleaseResponse.self, from: data)

        let artistName = releaseResponse.artistCredit?.first?.name ?? ""
        let artistMBID = releaseResponse.artistCredit?.first?.artist.id

        var tracks: [MBTrack] = []
        if let media = releaseResponse.media {
            for medium in media {
                for track in medium.tracks ?? [] {
                    tracks.append(MBTrack(
                        id: track.id,
                        position: track.position,
                        title: track.title,
                        duration: track.length
                    ))
                }
            }
        }

        return MBRelease(
            id: releaseResponse.id,
            title: releaseResponse.title,
            artist: artistName,
            artistMBID: artistMBID,
            date: releaseResponse.date,
            country: releaseResponse.country,
            trackCount: tracks.count,
            tracks: tracks
        )
    }

    // MARK: - Helpers

    private func enforceRateLimit() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                let delay = minRequestInterval - elapsed
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            }
        }
        lastRequestTime = Date()
    }

    private func escapeQuery(_ query: String) -> String {
        // Escape special Lucene characters
        let specialChars = CharacterSet(charactersIn: "+-&|!(){}[]^\"~*?:\\")
        var escaped = ""
        for char in query.unicodeScalars {
            if specialChars.contains(char) {
                escaped += "\\\(char)"
            } else {
                escaped += String(char)
            }
        }
        return escaped
    }
}

// MARK: - Errors

enum MetadataError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case noResults
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .apiError(let code): return "API error: \(code)"
        case .noResults: return "No results found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}
