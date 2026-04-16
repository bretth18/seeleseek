import Foundation

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String
    public let filename: String
    public let size: UInt64
    public let bitrate: UInt32?
    public let duration: UInt32?
    public let sampleRate: UInt32?
    public let bitDepth: UInt32?
    public let isVBR: Bool
    public let freeSlots: Bool
    public let uploadSpeed: UInt32
    public let queueLength: UInt32
    public let isPrivate: Bool  // Buddy-only / locked file

    public nonisolated init(
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

    public var displayFilename: String {
        // Extract just the filename from the full path
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    public var folderPath: String {
        // Get the folder path without the filename
        let components = filename.split(separator: "\\")
        if components.count > 1 {
            return components.dropLast().joined(separator: "\\")
        }
        return ""
    }

    public var formattedSize: String {
        size.formattedBytes
    }

    public var formattedDuration: String? {
        guard let duration else { return nil }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var formattedBitrate: String? {
        guard let bitrate else { return nil }
        if isVBR {
            return "~\(bitrate) kbps"
        }
        return "\(bitrate) kbps"
    }

    public var formattedSpeed: String {
        uploadSpeed.formattedSpeed
    }

    public var formattedSampleRate: String? {
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

    public var formattedBitDepth: String? {
        guard let bitDepth, bitDepth > 0 else { return nil }
        return "\(bitDepth)-bit"
    }

    public var fileExtension: String {
        let components = displayFilename.split(separator: ".")
        if components.count > 1, let ext = components.last {
            return String(ext).lowercased()
        }
        return ""
    }

    public var isAudioFile: Bool { FileTypes.isAudio(fileExtension) }
    public var isLossless: Bool { FileTypes.isLossless(fileExtension) }
}
