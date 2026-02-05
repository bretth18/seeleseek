import SwiftUI

/// Visual representation of connected peers as a network graph
struct NetworkTopologyView: View {
    let connections: [PeerConnectionPool.PeerConnectionInfo]
    let centerUsername: String

    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var selectedPeer: String?

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Connection lines
                ForEach(connections) { conn in
                    if let position = nodePositions[conn.id] {
                        ConnectionLine(
                            from: center,
                            to: position,
                            isActive: conn.state == PeerConnection.State.connected,
                            traffic: conn.bytesReceived + conn.bytesSent
                        )
                    }
                }

                // Center node (self)
                CenterNode(username: centerUsername)
                    .position(center)

                // Peer nodes
                ForEach(connections) { conn in
                    if let position = nodePositions[conn.id] {
                        PeerNode(
                            info: conn,
                            isSelected: selectedPeer == conn.id
                        )
                        .position(position)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedPeer = selectedPeer == conn.id ? nil : conn.id
                            }
                        }
                    }
                }

                // Selected peer detail
                if let selected = selectedPeer,
                   let conn = connections.first(where: { $0.id == selected }),
                   let position = nodePositions[selected] {
                    PeerDetailPopover(info: conn)
                        .position(x: position.x, y: position.y - 80)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear {
                calculateNodePositions(in: geometry.size)
            }
            .onChange(of: connections.count) {
                withAnimation(.spring(response: 0.5)) {
                    calculateNodePositions(in: geometry.size)
                }
            }
        }
    }

    private func calculateNodePositions(in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 60

        for (index, conn) in connections.enumerated() {
            let angle = (2 * .pi * Double(index) / Double(max(connections.count, 1))) - .pi / 2
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            nodePositions[conn.id] = CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Connection Line

struct ConnectionLine: View {
    let from: CGPoint
    let to: CGPoint
    let isActive: Bool
    let traffic: UInt64

    private var lineWidth: CGFloat {
        let base: CGFloat = 1
        let trafficFactor = min(CGFloat(traffic) / 1_000_000, 4) // Max 4px extra for 1MB
        return base + trafficFactor
    }

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            isActive ? SeeleColors.success.opacity(0.6) : SeeleColors.textTertiary.opacity(0.3),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

// MARK: - Center Node

struct CenterNode: View {
    let username: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SeeleColors.accent.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                // Main circle
                Circle()
                    .fill(SeeleColors.accent)
                    .frame(width: 50, height: 50)
                    .shadow(color: SeeleColors.accent.opacity(0.5), radius: 10)

                // Icon
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(username)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textPrimary)
        }
    }
}

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
        VStack(spacing: 4) {
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
                    .foregroundStyle(.white)
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

            // Action buttons (only if we have a username)
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
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
            // Header
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

                // Legend
                HStack(spacing: SeeleSpacing.md) {
                    LegendItem(color: SeeleColors.success, label: "Connected")
                    LegendItem(color: SeeleColors.warning, label: "Connecting")
                    LegendItem(color: SeeleColors.error, label: "Failed")
                }
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)

            // Network visualization
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
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}

#Preview {
    NetworkVisualizationView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
