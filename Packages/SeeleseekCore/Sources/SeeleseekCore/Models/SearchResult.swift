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

    // Stored, not computed: each is read several times per search-row body.
    public let displayFilename: String
    public let folderPath: String
    public let fileExtension: String

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

        let components = filename.split(separator: "\\")
        let display = components.last.map(String.init) ?? filename
        self.displayFilename = display
        self.folderPath = components.count > 1
            ? components.dropLast().joined(separator: "\\")
            : ""
        let dot = display.split(separator: ".")
        self.fileExtension = dot.count > 1 ? String(dot[dot.count - 1]).lowercased() : ""
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

    public var isAudioFile: Bool { FileTypes.isAudio(fileExtension) }
    public var isLossless: Bool { FileTypes.isLossless(fileExtension) }
    public var isImageFile: Bool { FileTypes.isImage(fileExtension) }
    public var isVideoFile: Bool { FileTypes.isVideo(fileExtension) }
}
