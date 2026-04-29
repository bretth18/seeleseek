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
    /// When the next scheduled retry should fire. Persisted so an in-flight
    /// retry survives an app quit — without this, the in-memory retry Task
    /// dies on quit and the row sits at `.failed` with a stale "Retrying
    /// in 28m..." string forever. `nil` means no retry pending. Cleared by
    /// the manager when the retry fires, the row moves out of `.failed`,
    /// or the user cancels.
    public var nextRetryAt: Date?

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

        /// True for statuses where an in-flight upload-side message
        /// (`UploadDenied` / `UploadFailed`) is still relevant. Used to
        /// drop late peer messages that would otherwise stomp a
        /// `.completed` / `.cancelled` row.
        public var isLiveDownloadAttempt: Bool {
            switch self {
            case .queued, .waiting, .connecting, .transferring: return true
            case .completed, .failed, .cancelled: return false
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
        retryCount: Int = 0,
        nextRetryAt: Date? = nil
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
        self.nextRetryAt = nextRetryAt
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
        return parts[startIndex..<endIndex].joined(separator: "/")
    }

    public var isAudioFile: Bool {
        FileTypes.isAudio((displayFilename as NSString).pathExtension.lowercased())
    }

    public var progress: Double {
        guard size > 0 else { return 0 }
        return Double(bytesTransferred) / Double(size)
    }

    public var formattedProgress: String {
        "\(bytesTransferred.formattedBytes) / \(size.formattedBytes)"
    }

    public var formattedSpeed: String {
        speed.formattedSpeed
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
