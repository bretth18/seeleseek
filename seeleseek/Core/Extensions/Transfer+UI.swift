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
}
