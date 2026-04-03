import Foundation

public struct Transfer: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String
    public let filename: String  // Original path from peer (e.g., "@@music\Artist\Album\01 Song.mp3")
    public let size: UInt64
    public let direction: TransferDirection
    public var status: TransferStatus
    public var bytesTransferred: UInt64
    public var startTime: Date?
    public var speed: Int64
    public var queuePosition: Int?
    public var error: String?
    public var localPath: URL?  // Local file path after download completes
    public var retryCount: Int  // Number of retry attempts (nicotine+ style)

    public enum TransferDirection: String, Sendable {
        case download
        case upload
    }

    public enum TransferStatus: String, Sendable {
        case queued
        case connecting
        case transferring
        case completed
        case failed
        case cancelled
        case waiting

        public var icon: String {
            switch self {
            case .queued: "clock"
            case .connecting: "arrow.triangle.2.circlepath"
            case .transferring: "arrow.down"
            case .completed: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            case .cancelled: "xmark.circle"
            case .waiting: "hourglass"
            }
        }

        public var displayText: String {
            switch self {
            case .queued: "Queued"
            case .connecting: "Connecting to peer..."
            case .transferring: "Transferring"
            case .completed: "Completed"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            case .waiting: "Waiting in remote queue"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        username: String,
        filename: String,
        size: UInt64,
        direction: TransferDirection,
        status: TransferStatus = .queued,
        bytesTransferred: UInt64 = 0,
        startTime: Date? = nil,
        speed: Int64 = 0,
        queuePosition: Int? = nil,
        error: String? = nil,
        localPath: URL? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.username = username
        self.filename = filename
        self.size = size
        self.direction = direction
        self.status = status
        self.bytesTransferred = bytesTransferred
        self.startTime = startTime
        self.speed = speed
        self.queuePosition = queuePosition
        self.error = error
        self.localPath = localPath
        self.retryCount = retryCount
    }

    public var displayFilename: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    /// Extract artist/album path from filename (e.g., "Artist/Album" from "@@music\Artist\Album\Song.mp3")
    public var folderPath: String? {
        let parts = filename.split(separator: "\\").map(String.init)
        guard parts.count >= 2 else { return nil }
        // Skip root share (@@music) and filename, return middle parts
        let startIndex = parts[0].hasPrefix("@@") ? 1 : 0
        let endIndex = parts.count - 1
        guard startIndex < endIndex else { return nil }
        return parts[startIndex..<endIndex].joined(separator: " / ")
    }

    /// Check if this is an audio file
    public var isAudioFile: Bool {
        let audioExtensions = ["mp3", "flac", "wav", "m4a", "aac", "ogg", "wma", "aiff", "alac"]
        let ext = (displayFilename as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }

    public var progress: Double {
        guard size > 0 else { return 0 }
        return Double(bytesTransferred) / Double(size)
    }

    public var formattedProgress: String {
        "\(ByteFormatter.format(Int64(bytesTransferred))) / \(ByteFormatter.format(Int64(size)))"
    }

    public var formattedSpeed: String {
        ByteFormatter.formatSpeed(speed)
    }

    public var isActive: Bool {
        switch status {
        case .connecting, .transferring:
            return true
        default:
            return false
        }
    }

    public var canCancel: Bool {
        switch status {
        case .queued, .connecting, .transferring, .waiting:
            return true
        default:
            return false
        }
    }

    public var canRetry: Bool {
        switch status {
        case .failed, .cancelled:
            return true
        default:
            return false
        }
    }

}
