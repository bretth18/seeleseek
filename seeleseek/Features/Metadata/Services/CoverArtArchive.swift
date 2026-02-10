import Foundation
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Client for Cover Art Archive API to fetch album artwork
actor CoverArtArchive {
    private let logger = Logger(subsystem: "com.seeleseek", category: "CoverArtArchive")
    private let baseURL = "https://coverartarchive.org"
    private let userAgent = "SeeleSeek/1.0 (https://github.com/seeleseek)"

    // Simple in-memory cache
    private var cache: [String: Data] = [:]
    private let maxCacheSize = 50

    // MARK: - Types

    struct CoverArtResponse: Decodable {
        let images: [CoverArtImage]
        let release: String

        struct CoverArtImage: Decodable {
            let id: Int64
            let image: String  // Full size URL
            let thumbnails: Thumbnails
            let front: Bool
            let back: Bool
            let types: [String]

            struct Thumbnails: Decodable {
                let small: String?  // 250px
                let large: String?  // 500px
                let _250: String?
                let _500: String?
                let _1200: String?

                enum CodingKeys: String, CodingKey {
                    case small, large
                    case _250 = "250"
                    case _500 = "500"
                    case _1200 = "1200"
                }
            }
        }
    }

    enum ImageSize {
        case small   // 250px
        case medium  // 500px
        case large   // 1200px
        case full    // Original size
    }

    // MARK: - API Methods

    /// Fetch cover art for a MusicBrainz release
    func getCoverArt(releaseMBID: String, size: ImageSize = .medium) async throws -> Data? {
        // Check cache
        let cacheKey = "\(releaseMBID)-\(size)"
        if let cached = cache[cacheKey] {
            logger.debug("Cover art cache hit: \(releaseMBID)")
            return cached
        }

        // First, get the cover art info to find the front cover
        let infoURL = "\(baseURL)/release/\(releaseMBID)"
        guard let url = URL(string: infoURL) else {
            throw MetadataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.info("Fetching cover art info: \(releaseMBID)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataError.invalidResponse
        }

        // 404 means no cover art available
        if httpResponse.statusCode == 404 {
            logger.info("No cover art available for release: \(releaseMBID)")
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw MetadataError.apiError(httpResponse.statusCode)
        }

        let coverArtResponse = try JSONDecoder().decode(CoverArtResponse.self, from: data)

        // Find the front cover
        guard let frontCover = coverArtResponse.images.first(where: { $0.front }) ?? coverArtResponse.images.first else {
            logger.info("No front cover found for release: \(releaseMBID)")
            return nil
        }

        // Get the appropriate size URL
        let imageURL: String
        switch size {
        case .small:
            imageURL = frontCover.thumbnails.small ?? frontCover.thumbnails._250 ?? frontCover.image
        case .medium:
            imageURL = frontCover.thumbnails.large ?? frontCover.thumbnails._500 ?? frontCover.image
        case .large:
            imageURL = frontCover.thumbnails._1200 ?? frontCover.image
        case .full:
            imageURL = frontCover.image
        }

        // Fetch the actual image
        guard let imgURL = URL(string: imageURL) else {
            throw MetadataError.invalidURL
        }

        var imgRequest = URLRequest(url: imgURL)
        imgRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        logger.info("Fetching cover image: \(imageURL)")

        let (imageData, imgResponse) = try await URLSession.shared.data(for: imgRequest)

        guard let imgHttpResponse = imgResponse as? HTTPURLResponse, imgHttpResponse.statusCode == 200 else {
            throw MetadataError.invalidResponse
        }

        // Cache the result
        addToCache(key: cacheKey, data: imageData)

        return imageData
    }

    /// Get the front cover URL for a release (useful for display before downloading)
    func getFrontCoverURL(releaseMBID: String, size: ImageSize = .medium) async throws -> URL? {
        let infoURL = "\(baseURL)/release/\(releaseMBID)"
        guard let url = URL(string: infoURL) else {
            throw MetadataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw MetadataError.apiError(httpResponse.statusCode)
        }

        let coverArtResponse = try JSONDecoder().decode(CoverArtResponse.self, from: data)

        guard let frontCover = coverArtResponse.images.first(where: { $0.front }) ?? coverArtResponse.images.first else {
            return nil
        }

        let imageURL: String
        switch size {
        case .small:
            imageURL = frontCover.thumbnails.small ?? frontCover.thumbnails._250 ?? frontCover.image
        case .medium:
            imageURL = frontCover.thumbnails.large ?? frontCover.thumbnails._500 ?? frontCover.image
        case .large:
            imageURL = frontCover.thumbnails._1200 ?? frontCover.image
        case .full:
            imageURL = frontCover.image
        }

        return URL(string: imageURL)
    }

    // MARK: - Cache Management

    private func addToCache(key: String, data: Data) {
        // Simple FIFO eviction
        if cache.count >= maxCacheSize {
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[key] = data
    }

    func clearCache() {
        cache.removeAll()
    }
}
