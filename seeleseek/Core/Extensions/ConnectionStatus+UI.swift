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

    /// Appearance-aware variant of `color`, for surfaces that follow the system
    /// theme instead of the app's pinned dark scheme — the status-bar menu.
    /// Dynamic, so it resolves against the appearance in effect when it is
    /// *drawn* rather than one sampled ahead of time; see `SeeleColors.Adaptive`.
    var adaptiveNSColor: NSColor {
        switch self {
        case .disconnected: SeeleColors.Adaptive.textTertiaryNS
        case .connecting: SeeleColors.Adaptive.warningNS
        case .connected: SeeleColors.Adaptive.successNS
        case .reconnecting: SeeleColors.Adaptive.warningNS
        case .error: SeeleColors.Adaptive.errorNS
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
