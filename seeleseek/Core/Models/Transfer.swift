import Foundation

struct Transfer: Identifiable, Hashable, Sendable {
    let id: UUID
    let username: String
    let filename: String
    let size: UInt64
    let direction: TransferDirection
    var status: TransferStatus
    var bytesTransferred: UInt64
    var startTime: Date?
    var speed: Int64
    var queuePosition: Int?
    var error: String?

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
        error: String? = nil
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
    }

    var displayFilename: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
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
