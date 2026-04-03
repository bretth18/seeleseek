import SwiftUI
import SeeleseekCore

extension Transfer {
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

extension Transfer.TransferStatus {
    var color: SeeleColors.Type {
        SeeleColors.self
    }

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
