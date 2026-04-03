import SwiftUI
import SeeleseekCore

extension ConnectionStatus {
    var color: Color {
        switch self {
        case .disconnected: SeeleColors.textTertiary
        case .connecting: SeeleColors.warning
        case .connected: SeeleColors.success
        case .reconnecting: SeeleColors.warning
        case .error: SeeleColors.error
        }
    }

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .reconnecting: "Reconnecting..."
        case .error: "Error"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: "circle.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}
