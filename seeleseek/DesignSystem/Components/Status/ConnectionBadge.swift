import SwiftUI

enum ConnectionStatus: String, CaseIterable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error

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

struct ConnectionBadge: View {
    let status: ConnectionStatus
    let showLabel: Bool

    init(status: ConnectionStatus, showLabel: Bool = true) {
        self.status = status
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            statusIndicator
            if showLabel {
                Text(status.label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.horizontal, showLabel ? SeeleSpacing.sm : SeeleSpacing.xs)
        .padding(.vertical, SeeleSpacing.xs)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .connecting {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.4)
                .tint(status.color)
                .frame(width: SeeleSpacing.iconSizeSmall - 2, height: SeeleSpacing.iconSizeSmall - 2)
        } else {
            Image(systemName: status.icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall - 2, weight: .medium))
                .foregroundStyle(status.color)
        }
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.lg) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionBadge(status: status)
        }
    }
    .padding()
    .background(SeeleColors.background)
}
