import SwiftUI

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
                // Selection ring
                if isSelected {
                    Circle()
                        .stroke(SeeleColors.accent, lineWidth: 2)
                        .frame(width: nodeSize + 10, height: nodeSize + 10)
                }

                // Main circle
                Circle()
                    .fill(nodeColor)
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(color: nodeColor.opacity(0.5), radius: isSelected ? 8 : 4)

                // Connection type indicator
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

// MARK: - Peer Detail Popover

struct PeerDetailPopover: View {
    let info: PeerConnectionPool.PeerConnectionInfo
    @Environment(\.appState) private var appState

    private var hasUsername: Bool {
        !info.username.isEmpty && info.username != "unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text(hasUsername ? info.username : "Peer: \(info.ip)")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Divider()
                .background(SeeleColors.surfaceSecondary)

            HStack {
                Label(info.ip, systemImage: "network")
                Text(":\(info.port)")
            }
            .font(SeeleTypography.caption)
            .foregroundStyle(SeeleColors.textSecondary)

            HStack(spacing: SeeleSpacing.md) {
                Label("↓ \(ByteFormatter.format(Int64(info.bytesReceived)))", systemImage: "arrow.down")
                    .foregroundStyle(SeeleColors.success)

                Label("↑ \(ByteFormatter.format(Int64(info.bytesSent)))", systemImage: "arrow.up")
                    .foregroundStyle(SeeleColors.accent)
            }
            .font(SeeleTypography.caption)

            if let connectedAt = info.connectedAt {
                Text("Connected \(formatDuration(since: connectedAt))")
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if hasUsername {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                HStack(spacing: SeeleSpacing.md) {
                    Button {
                        appState.browseState.browseUser(info.username)
                        appState.sidebarSelection = .browse
                    } label: {
                        Label("Browse", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.chatState.selectPrivateChat(info.username)
                        appState.sidebarSelection = .chat
                    } label: {
                        Label("Chat", systemImage: "bubble.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10)
    }

    private func formatDuration(since date: Date) -> String {
        let duration = Date().timeIntervalSince(date)
        if duration < 60 {
            return "\(Int(duration))s ago"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m ago"
        } else {
            return "\(Int(duration / 3600))h ago"
        }
    }
}

// MARK: - Full Screen Network View

struct NetworkVisualizationView: View {
    @Environment(\.appState) private var appState
    @State private var peerPool = PeerConnectionPool()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Network Topology")
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("\(peerPool.activeConnections) active connections")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

                Spacer()

                HStack(spacing: SeeleSpacing.md) {
                    LegendItem(color: SeeleColors.success, label: "Connected")
                    LegendItem(color: SeeleColors.warning, label: "Connecting")
                    LegendItem(color: SeeleColors.error, label: "Failed")
                }
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)

            NetworkTopologyView(
                connections: Array(peerPool.connections.values),
                centerUsername: appState.networkClient.username
            )
            .padding(SeeleSpacing.lg)
        }
        .background(SeeleColors.background)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}
