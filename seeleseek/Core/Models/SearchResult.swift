import Foundation

struct SearchResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let username: String
    let filename: String
    let size: UInt64
    let bitrate: UInt32?
    let duration: UInt32?
    let isVBR: Bool
    let freeSlots: Bool
    let uploadSpeed: UInt32
    let queueLength: UInt32

    init(
        id: UUID = UUID(),
        username: String,
        filename: String,
        size: UInt64,
        bitrate: UInt32? = nil,
        duration: UInt32? = nil,
        isVBR: Bool = false,
        freeSlots: Bool = true,
        uploadSpeed: UInt32 = 0,
        queueLength: UInt32 = 0
    ) {
        self.id = id
        self.username = username
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.isVBR = isVBR
        self.freeSlots = freeSlots
        self.uploadSpeed = uploadSpeed
        self.queueLength = queueLength
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

    init(query: String, token: UInt32) {
        self.id = UUID()
        self.query = query
        self.token = token
        self.timestamp = Date()
        self.results = []
        self.isSearching = true
    }

    var resultCount: Int {
        results.count
    }

    var uniqueUsers: Int {
        Set(results.map(\.username)).count
    }
}
