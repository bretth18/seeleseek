import SwiftUI
import SeeleseekCore

// MARK: - Peer Node

struct PeerNode: View {
    let info: PeerConnectionPool.PeerConnectionInfo
    let isSelected: Bool

    private var nodeColor: Color {
        switch info.state {
        case .connected: SeeleColors.success
        case .connecting, .handshaking: SeeleColors.warning
        case .failed: SeeleColors.error
        case .disconnected: SeeleColors.textTertiary
        }
    }

    private var nodeSize: CGFloat {
        let base: CGFloat = 30
        let trafficFactor = min(CGFloat(info.bytesReceived + info.bytesSent) / 10_000_000, 20)
        return base + trafficFactor
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.xs) {
            ZStack {
                if isSelected {
                    Circle()
                        .stroke(SeeleColors.accent, lineWidth: SeeleSpacing.strokeMedium)
                        .frame(width: nodeSize + SeeleSpacing.sm + 2, height: nodeSize + SeeleSpacing.sm + 2)
                }

                Circle()
                    .fill(nodeColor)
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(color: nodeColor.opacity(0.5), radius: isSelected ? 8 : 4)

                Text(connectionTypeIcon)
                    .font(.system(size: nodeSize * 0.4))
                    .foregroundStyle(SeeleColors.textOnAccent)
            }

            Text(info.username.isEmpty || info.username == "unknown" ? info.ip : info.username)
                .font(SeeleTypography.caption2)
                .foregroundStyle(info.username.isEmpty || info.username == "unknown" ? SeeleColors.textTertiary : SeeleColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 80)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var connectionTypeIcon: String {
        switch info.connectionType {
        case .peer: "P"
        case .file: "F"
        case .distributed: "D"
        }
    }
}
