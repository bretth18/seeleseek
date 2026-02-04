import Foundation

struct Transfer: Identifiable, Hashable, Sendable {
    let id: UUID
    let username: String
    let filename: String  // Original path from peer (e.g., "@@music\Artist\Album\01 Song.mp3")
    let size: UInt64
    let direction: TransferDirection
    var status: TransferStatus
    var bytesTransferred: UInt64
    var startTime: Date?
    var speed: Int64
    var queuePosition: Int?
    var error: String?
    var localPath: URL?  // Local file path after download completes

    enum TransferDirection: String, Sendable {
        case download
        case upload
    }

    enum TransferStatus: String, Sendable {
        case queued
        case connecting
        case transferring
        case completed
        case failed
        case cancelled
        case waiting

        var icon: String {
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

        var color: SeeleColors.Type {
            SeeleColors.self
        }

        var displayText: String {
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

    init(
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
        localPath: URL? = nil
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
    }

    var displayFilename: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    /// Extract artist/album path from filename (e.g., "Artist/Album" from "@@music\Artist\Album\Song.mp3")
    var folderPath: String? {
        let parts = filename.split(separator: "\\").map(String.init)
        guard parts.count >= 2 else { return nil }
        // Skip root share (@@music) and filename, return middle parts
        let startIndex = parts[0].hasPrefix("@@") ? 1 : 0
        let endIndex = parts.count - 1
        guard startIndex < endIndex else { return nil }
        return parts[startIndex..<endIndex].joined(separator: " / ")
    }

    /// Check if this is an audio file
    var isAudioFile: Bool {
        let audioExtensions = ["mp3", "flac", "wav", "m4a", "aac", "ogg", "wma", "aiff", "alac"]
        let ext = (displayFilename as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }

    var progress: Double {
        guard size > 0 else { return 0 }
        return Double(bytesTransferred) / Double(size)
    }

    var formattedProgress: String {
        "\(ByteFormatter.format(Int64(bytesTransferred))) / \(ByteFormatter.format(Int64(size)))"
    }

    var formattedSpeed: String {
        ByteFormatter.formatSpeed(speed)
    }

    var isActive: Bool {
        switch status {
        case .connecting, .transferring:
            return true
        default:
            return false
        }
    }

    var canCancel: Bool {
        switch status {
        case .queued, .connecting, .transferring, .waiting:
            return true
        default:
            return false
        }
    }

    var canRetry: Bool {
        switch status {
        case .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    var statusColor: Color {
        switch status {
        case .queued, .waiting: SeeleColors.warning
        case .connecting: SeeleColors.info
        case .transferring: SeeleColors.accent
        case .completed: SeeleColors.success
        case .failed: SeeleColors.error
        case .cancelled: SeeleColors.textTertiary
        }
    }
}

import SwiftUI
