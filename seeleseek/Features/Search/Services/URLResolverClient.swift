import Foundation
import os

/// Resolves music streaming URLs (Spotify, Apple Music, YouTube, SoundCloud, Bandcamp)
/// into artist + title pairs for searching on SoulSeek.
actor URLResolverClient {
    private let logger = Logger(subsystem: "com.seeleseek", category: "URLResolver")
    private let session = URLSession.shared

    // MARK: - Types

    struct ResolvedTrack: Sendable {
        let artist: String
        let title: String
        let source: MusicService
    }

    enum MusicService: String, Sendable {
        case spotify = "Spotify"
        case appleMusic = "Apple Music"
        case youtube = "YouTube"
        case soundcloud = "SoundCloud"
        case bandcamp = "Bandcamp"
    }

    enum ResolveError: LocalizedError {
        case unsupportedURL
        case notATrack
        case parseFailed(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedURL: return "Unsupported music URL"
            case .notATrack: return "URL does not point to a single track"
            case .parseFailed(let detail): return "Could not parse track info: \(detail)"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Resolve a music URL into an artist + title pair
    func resolve(url: String) async throws -> ResolvedTrack {
        guard let service = Self.detectService(from: url) else {
            throw ResolveError.unsupportedURL
        }

        logger.info("Resolving \(service.rawValue) URL: \(url)")

        let track: ResolvedTrack
        switch service {
        case .spotify:
            track = try await resolveSpotify(url: url)
        case .appleMusic:
            track = try await resolveAppleMusic(url: url)
        case .youtube:
            track = try await resolveYouTube(url: url)
        case .soundcloud:
            track = try await resolveSoundCloud(url: url)
        case .bandcamp:
            track = try await resolveBandcamp(url: url)
        }

        logger.info("Resolved: \(track.artist) - \(track.title) [\(service.rawValue)]")
        return track
    }

    /// Detect which music service a URL belongs to, or nil if not a recognized music URL
    static func detectService(from url: String) -> MusicService? {
        let lowered = url.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Spotify: open.spotify.com/track/ or open.spotify.com/intl-*/track/
        if lowered.contains("open.spotify.com/") && lowered.contains("/track/") {
            return .spotify
        }

        // Apple Music: music.apple.com with ?i= (track in album) or /song/
        if lowered.contains("music.apple.com/") {
            if lowered.contains("i=") || lowered.contains("/song/") {
                return .appleMusic
            }
            // Album-only URL without track ID — reject later
            return nil
        }

        // YouTube: youtube.com/watch, youtu.be/, music.youtube.com/watch
        if lowered.contains("youtube.com/watch") || lowered.contains("youtu.be/") || lowered.contains("music.youtube.com/watch") {
            return .youtube
        }

        // SoundCloud: soundcloud.com with at least 2 path segments (artist/track)
        if lowered.contains("soundcloud.com/") {
            if let urlObj = URL(string: url),
               urlObj.pathComponents.filter({ $0 != "/" }).count >= 2 {
                // Reject sets/playlists
                if lowered.contains("/sets/") { return nil }
                return .soundcloud
            }
            return nil
        }

        // Bandcamp: *.bandcamp.com/track/
        if lowered.contains(".bandcamp.com/track/") {
            return .bandcamp
        }

        return nil
    }

    /// Build a search query from artist + title
    static func buildSearchQuery(artist: String, title: String) -> String {
        "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
    }

    /// Clean YouTube-style titles by stripping common video suffixes
    static func cleanTitle(_ title: String) -> String {
        // Pattern to match common video suffixes (case-insensitive)
        let patterns = [
            #"\s*[\(\[]\s*Official\s+(Music\s+)?Video\s*[\)\]]"#,
            #"\s*[\(\[]\s*Official\s+Audio\s*[\)\]]"#,
            #"\s*[\(\[]\s*Official\s+Lyric\s+Video\s*[\)\]]"#,
            #"\s*[\(\[]\s*Official\s+Visualizer\s*[\)\]]"#,
            #"\s*[\(\[]\s*Lyric\s+Video\s*[\)\]]"#,
            #"\s*[\(\[]\s*Audio\s*[\)\]]"#,
            #"\s*[\(\[]\s*HD\s*[\)\]]"#,
            #"\s*[\(\[]\s*HQ\s*[\)\]]"#,
            #"\s*[\(\[]\s*4K\s*[\)\]]"#,
            #"\s*[\(\[]\s*4K\s+Remaster(ed)?\s*[\)\]]"#,
            #"\s*[\(\[]\s*Music\s+Video\s*[\)\]]"#,
            #"\s*[\(\[]\s*Explicit\s*[\)\]]"#,
            #"\s*[\(\[]\s*Visualizer\s*[\)\]]"#,
        ]

        var cleaned = title
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Per-Service Resolvers

    /// Spotify: og:title has track name, og:description has "Artist · Album · Song · Year"
    private func resolveSpotify(url: String) async throws -> ResolvedTrack {
        let html = try await fetchHTML(url: url)

        guard let ogTitle = extractMetaContent(html: html, property: "og:title") else {
            throw ResolveError.parseFailed("No og:title found")
        }

        // og:description format: "Rick Astley · Whenever You Need Somebody · Song · 1987"
        // Artist is the first segment before " · "
        var artist = ""
        if let ogDescription = extractMetaContent(html: html, property: "og:description") {
            if let dotRange = ogDescription.range(of: " \u{00B7} ") {
                artist = String(ogDescription[ogDescription.startIndex..<dotRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return ResolvedTrack(
            artist: artist,
            title: ogTitle.trimmingCharacters(in: .whitespaces),
            source: .spotify
        )
    }

    /// Apple Music: use oEmbed JSON API for reliable structured data
    private func resolveAppleMusic(url: String) async throws -> ResolvedTrack {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let oembedURL = "https://music.apple.com/api/oembed?url=\(encodedURL)"
        let oembed = try await fetchOEmbed(endpoint: oembedURL)

        let artist = oembed.authorName ?? ""
        // oEmbed title often has " - Single" or " - EP" suffix
        var title = oembed.title
        for suffix in [" - Single", " - EP", " - single", " - ep"] {
            if title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count))
                break
            }
        }

        return ResolvedTrack(
            artist: artist.trimmingCharacters(in: .whitespaces),
            title: title.trimmingCharacters(in: .whitespaces),
            source: .appleMusic
        )
    }

    /// YouTube: use oEmbed JSON endpoint, split "Artist - Title" from title field
    private func resolveYouTube(url: String) async throws -> ResolvedTrack {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let oembedURL = "https://www.youtube.com/oembed?url=\(encodedURL)&format=json"
        let oembed = try await fetchOEmbed(endpoint: oembedURL)

        let rawTitle = oembed.title
        let cleanedTitle = Self.cleanTitle(rawTitle)

        // Try splitting on " - " (Artist - Title)
        if let dashRange = cleanedTitle.range(of: " - ") {
            let artist = String(cleanedTitle[cleanedTitle.startIndex..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(cleanedTitle[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty && !title.isEmpty {
                return ResolvedTrack(artist: artist, title: Self.cleanTitle(title), source: .youtube)
            }
        }

        // Fallback: use author_name as artist, full title as title
        let artist = oembed.authorName ?? ""
        return ResolvedTrack(
            artist: artist,
            title: cleanedTitle,
            source: .youtube
        )
    }

    /// SoundCloud: use oEmbed JSON endpoint
    private func resolveSoundCloud(url: String) async throws -> ResolvedTrack {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let oembedURL = "https://soundcloud.com/oembed?url=\(encodedURL)&format=json"
        let oembed = try await fetchOEmbed(endpoint: oembedURL)

        let artist = oembed.authorName ?? ""
        var title = oembed.title

        // SoundCloud oEmbed title is often "Title by Artist" — strip the " by Artist" suffix
        if !artist.isEmpty {
            let suffix = " by \(artist)"
            if title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count))
            }
        }

        return ResolvedTrack(
            artist: artist.trimmingCharacters(in: .whitespaces),
            title: title.trimmingCharacters(in: .whitespaces),
            source: .soundcloud
        )
    }

    /// Bandcamp: fetch HTML and parse og:title ("{Title}, by {Artist}")
    private func resolveBandcamp(url: String) async throws -> ResolvedTrack {
        let html = try await fetchHTML(url: url)
        guard let ogTitle = extractMetaContent(html: html, property: "og:title") else {
            throw ResolveError.parseFailed("No og:title found")
        }

        // Format: "{Title}, by {Artist}" or "{Title} | {Artist}"
        if let byRange = ogTitle.range(of: ", by ", options: .caseInsensitive) {
            let title = String(ogTitle[ogTitle.startIndex..<byRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let artist = String(ogTitle[byRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return ResolvedTrack(artist: artist, title: title, source: .bandcamp)
        }

        // Fallback: try pipe separator
        if let pipeRange = ogTitle.range(of: " | ") {
            let title = String(ogTitle[ogTitle.startIndex..<pipeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let artist = String(ogTitle[pipeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return ResolvedTrack(artist: artist, title: title, source: .bandcamp)
        }

        throw ResolveError.parseFailed("Could not parse Bandcamp og:title: \(ogTitle)")
    }

    // MARK: - Helpers

    private struct OEmbedResponse: Decodable {
        let title: String
        let authorName: String?
        let authorURL: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case authorURL = "author_url"
        }
    }

    /// Fetch oEmbed JSON from an endpoint
    private func fetchOEmbed(endpoint: String) async throws -> OEmbedResponse {
        guard let url = URL(string: endpoint) else {
            throw ResolveError.parseFailed("Invalid oEmbed URL")
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ResolveError.parseFailed("oEmbed request failed with status \(code)")
        }

        return try JSONDecoder().decode(OEmbedResponse.self, from: data)
    }

    /// Fetch HTML from a URL using a bot user-agent to get og: meta tags
    private func fetchHTML(url urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ResolveError.parseFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        // Bot UA so services return server-rendered HTML with meta tags
        request.setValue("Twitterbot/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ResolveError.parseFailed("HTTP \(code) fetching page")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ResolveError.parseFailed("Could not decode HTML as UTF-8")
        }

        return html
    }

    /// Extract content attribute from a <meta property="..." content="..."> tag
    private func extractMetaContent(html: String, property: String) -> String? {
        // Match: <meta property="og:title" content="...">
        // Also handles: <meta name="..." content="..."> and various quote styles
        let patterns = [
            #"<meta\s+property="\#(property)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+property="\#(property)""#,
            #"<meta\s+name="\#(property)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+name="\#(property)""#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                // The content is in the first capture group
                let captureRange: NSRange
                if regex.numberOfCaptureGroups >= 1 {
                    captureRange = match.range(at: 1)
                } else {
                    continue
                }
                if let range = Range(captureRange, in: html) {
                    let content = String(html[range])
                    // Decode HTML entities
                    return content
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "&#x27;", with: "'")
                }
            }
        }

        return nil
    }
}
