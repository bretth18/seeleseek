import Foundation

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let username: String
    let filename: String
    let size: UInt64
    let bitrate: UInt32?
    let duration: UInt32?
    let sampleRate: UInt32?
    let bitDepth: UInt32?
    let isVBR: Bool
    let freeSlots: Bool
    let uploadSpeed: UInt32
    let queueLength: UInt32
    let isPrivate: Bool  // Buddy-only / locked file

    nonisolated init(
        id: UUID = UUID(),
        username: String,
        filename: String,
        size: UInt64,
        bitrate: UInt32? = nil,
        duration: UInt32? = nil,
        sampleRate: UInt32? = nil,
        bitDepth: UInt32? = nil,
        isVBR: Bool = false,
        freeSlots: Bool = true,
        uploadSpeed: UInt32 = 0,
        queueLength: UInt32 = 0,
        isPrivate: Bool = false
    ) {
        self.id = id
        self.username = username
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.isVBR = isVBR
        self.freeSlots = freeSlots
        self.uploadSpeed = uploadSpeed
        self.queueLength = queueLength
        self.isPrivate = isPrivate
    }

    var displayFilename: String {
        // Extract just the filename from the full path
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    var folderPath: String {
        // Get the folder path without the filename
        let components = filename.split(separator: "\\")
        if components.count > 1 {
            return components.dropLast().joined(separator: "\\")
        }
        return ""
    }

    var formattedSize: String {
        ByteFormatter.format(Int64(size))
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedBitrate: String? {
        guard let bitrate else { return nil }
        if isVBR {
            return "~\(bitrate) kbps"
        }
        return "\(bitrate) kbps"
    }

    var formattedSpeed: String {
        ByteFormatter.formatSpeed(Int64(uploadSpeed))
    }

    var formattedSampleRate: String? {
        guard let sampleRate, sampleRate > 0 else { return nil }
        if sampleRate % 1000 == 0 {
            return "\(sampleRate / 1000) kHz"
        }
        let khz = Double(sampleRate) / 1000.0
        // Format like 44.1 kHz, 88.2 kHz
        if khz == khz.rounded(.toNearestOrEven) {
            return "\(Int(khz)) kHz"
        }
        return String(format: "%.1f kHz", khz)
    }

    var formattedBitDepth: String? {
        guard let bitDepth, bitDepth > 0 else { return nil }
        return "\(bitDepth)-bit"
    }

    var fileExtension: String {
        let components = displayFilename.split(separator: ".")
        if components.count > 1, let ext = components.last {
            return String(ext).lowercased()
        }
        return ""
    }

    var isAudioFile: Bool {
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "alac", "wma", "ape"]
        return audioExtensions.contains(fileExtension)
    }

    var isLossless: Bool {
        let losslessExtensions = ["flac", "wav", "aiff", "alac", "ape"]
        return losslessExtensions.contains(fileExtension)
    }
}

struct SearchQuery: Identifiable, Hashable, Sendable {
    let id: UUID
    let query: String
    let token: UInt32
    let timestamp: Date
    var results: [SearchResult]
    var isSearching: Bool

    /// Convenience init for new searches
    nonisolated init(query: String, token: UInt32) {
        self.id = UUID()
        self.query = query
        self.token = token
        self.timestamp = Date()
        self.results = []
        self.isSearching = true
    }

    /// Full memberwise init for database restoration
    nonisolated init(
        id: UUID,
        query: String,
        token: UInt32,
        timestamp: Date,
        results: [SearchResult],
        isSearching: Bool
    ) {
        self.id = id
        self.query = query
        self.token = token
        self.timestamp = timestamp
        self.results = results
        self.isSearching = isSearching
    }

    var resultCount: Int {
        results.count
    }

    var uniqueUsers: Int {
        Set(results.map(\.username)).count
    }
}
