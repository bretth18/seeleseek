import SwiftUI

/// Real-time visualization of connected peers with activity indicators
struct LivePeersView: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    private var sortedPeers: [PeerConnectionPool.PeerConnectionInfo] {
        peerPool.connections.values
            .sorted { ($0.bytesReceived + $0.bytesSent) > ($1.bytesReceived + $1.bytesSent) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            // Header
            HStack {
                Text("Connected Peers")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                HStack(spacing: SeeleSpacing.sm) {
                    Circle()
                        .fill(SeeleColors.success)
                        .frame(width: 8, height: 8)
                    Text("\(peerPool.activeConnections) active")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }

            if sortedPeers.isEmpty {
                // Empty state
                VStack(spacing: SeeleSpacing.md) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("No peers connected")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Peers list
                LazyVStack(spacing: 1) {
                    ForEach(sortedPeers) { peer in
                        PeerRow(peer: peer)
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

// MARK: - Peer Row

struct PeerRow: View {
    let peer: PeerConnectionPool.PeerConnectionInfo

    @State private var isHovered = false
    @State private var showingDetail = false

    private var stateColor: Color {
        switch peer.state {
        case .connected:
            return SeeleColors.success
        case .connecting, .handshaking:
            return SeeleColors.warning
        case .disconnected:
            return SeeleColors.textTertiary
        case .failed:
            return SeeleColors.error
        }
    }

    private var connectionDuration: String {
        guard let connectedAt = peer.connectedAt else { return "--" }
        let duration = Date().timeIntervalSince(connectedAt)

        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h"
        }
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Status indicator with pulse animation
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.3))
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)

                // Activity pulse for active connections
                if peer.currentSpeed > 0 {
                    Circle()
                        .stroke(stateColor, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .opacity(0.5)
                        .scaleEffect(1.3)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: peer.currentSpeed
                        )
                }
            }

            // Username and info
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.username)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textPrimary)

                HStack(spacing: SeeleSpacing.sm) {
                    Text(peer.ip)
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text("•")
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text(connectionDuration)
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            Spacer()

            // Transfer stats
            HStack(spacing: SeeleSpacing.lg) {
                // Download
                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(ByteFormatter.format(Int64(peer.bytesReceived)))")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.success)
                }

                // Upload
                VStack(alignment: .trailing, spacing: 2) {
                    Text("↑ \(ByteFormatter.format(Int64(peer.bytesSent)))")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.accent)
                }
            }

            // Connection type badge
            Text(peer.connectionType.rawValue)
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)
                .padding(.horizontal, SeeleSpacing.sm)
                .padding(.vertical, 2)
                .background(SeeleColors.surfaceSecondary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(isHovered ? SeeleColors.surfaceSecondary : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            showingDetail = true
        }
        .popover(isPresented: $showingDetail) {
            PeerInfoPopover(peer: peer)
        }
    }
}

// MARK: - Peer Info Popover

struct PeerInfoPopover: View {
    let peer: PeerConnectionPool.PeerConnectionInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(peer.username)
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text(peer.state == .connected ? "Connected" : String(describing: peer.state))
                        .font(SeeleTypography.caption)
                        .foregroundStyle(peer.state == .connected ? SeeleColors.success : SeeleColors.textTertiary)
                }

                Spacer()

                // Connection type badge
                Text(peer.connectionType.rawValue)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, 4)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(Capsule())
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Connection info
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                DetailRow(label: "IP Address", value: peer.ip)
                DetailRow(label: "Port", value: "\(peer.port)")

                if let connectedAt = peer.connectedAt {
                    DetailRow(label: "Connected", value: formatDate(connectedAt))
                    DetailRow(label: "Duration", value: formatDuration(Date().timeIntervalSince(connectedAt)))
                }

                if let lastActivity = peer.lastActivity {
                    DetailRow(label: "Last Activity", value: formatDate(lastActivity))
                }
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Transfer stats
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Transfer Statistics")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)

                HStack(spacing: SeeleSpacing.xl) {
                    VStack(alignment: .leading) {
                        Text("Downloaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(ByteFormatter.format(Int64(peer.bytesReceived)))
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.success)
                    }

                    VStack(alignment: .leading) {
                        Text("Uploaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(ByteFormatter.format(Int64(peer.bytesSent)))
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.accent)
                    }
                }

                if peer.currentSpeed > 0 {
                    DetailRow(label: "Current Speed", value: ByteFormatter.formatSpeed(Int64(peer.currentSpeed)))
                }
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Actions
            HStack(spacing: SeeleSpacing.md) {
                Button {
                    // Browse user's files
                } label: {
                    Label("Browse", systemImage: "folder")
                        .font(SeeleTypography.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeeleColors.info)

                Button {
                    // Send private message
                } label: {
                    Label("Message", systemImage: "bubble.left")
                        .font(SeeleTypography.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeeleColors.info)

                Spacer()

                Button {
                    // Disconnect
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .font(SeeleTypography.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeeleColors.error)
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(width: 300)
        .background(SeeleColors.surface)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Spacer()
            Text(value)
                .font(SeeleTypography.mono)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}

#Preview {
    LivePeersView()
        .environment(\.appState, AppState())
        .frame(width: 600, height: 400)
}
