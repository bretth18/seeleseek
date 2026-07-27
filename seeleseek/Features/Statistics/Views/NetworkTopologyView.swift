import SwiftUI
import SeeleseekCore

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

                CenterNode(username: centerUsername)
                    .position(center)

                ForEach(connections) { conn in
                    if let position = nodePositions[conn.id] {
                        Button {
                            selectedPeer = conn.id
                        } label: {
                            PeerNode(
                                info: conn,
                                isSelected: selectedPeer == conn.id
                            )
                        }
                        .buttonStyle(.plain)
                        .position(position)
                        .popover(
                            isPresented: Binding(
                                get: { selectedPeer == conn.id },
                                set: { if !$0 { selectedPeer = nil } }
                            ),
                            attachmentAnchor: .point(.top),
                            arrowEdge: .bottom
                        ) {
                            PeerInfoPopover(peer: conn)
                        }
                        .contextMenu {
                            if !conn.username.isEmpty && conn.username != "unknown" {
                                UserContextMenuItems(
                                    username: conn.username,
                                    showAddBuddy: true,
                                    navigateOnBrowse: true,
                                    navigateOnMessage: true
                                )
                            }
                        }
                        .accessibilityLabel(conn.username.isEmpty || conn.username == "unknown" ? conn.ip : conn.username)
                        .accessibilityValue(nodeAccessibilityValue(for: conn))
                        .accessibilityHint("Show peer details")
                        .accessibilityActions {
                            if !conn.username.isEmpty && conn.username != "unknown" {
                                UserAccessibilityActions(
                                    username: conn.username,
                                    showAddBuddy: true,
                                    navigateOnBrowse: true,
                                    navigateOnMessage: true
                                )
                            }
                        }
                    }
                }
            }
            // `.contain` keeps the node buttons navigable while the
            // container speaks a graph-level summary.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Network topology")
            .accessibilityValue(topologySummary)
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

    private var topologySummary: String {
        var connected = 0
        var connecting = 0
        var failed = 0
        for conn in connections {
            switch conn.state {
            case .connected: connected += 1
            case .connecting, .handshaking: connecting += 1
            case .failed: failed += 1
            case .disconnected: break
            }
        }
        return "\(connections.count) peers: \(connected) connected, \(connecting) connecting, \(failed) failed"
    }

    /// Spoken state for a node. The node circle shows state by color
    /// and connection type by a bare letter, so both must be audible.
    private func nodeAccessibilityValue(for conn: PeerConnectionPool.PeerConnectionInfo) -> String {
        let state: String
        switch conn.state {
        case .connected: state = "Connected"
        case .connecting: state = "Connecting"
        case .handshaking: state = "Handshaking"
        case .disconnected: state = "Disconnected"
        case .failed: state = "Failed"
        }
        let type: String
        switch conn.connectionType {
        case .peer: type = "peer"
        case .file: type = "file transfer"
        case .distributed: type = "distributed"
        }
        return "\(state), \(type), received \(conn.bytesReceived.formattedBytes), sent \(conn.bytesSent.formattedBytes)"
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
        let trafficFactor = min(CGFloat(traffic) / 1_000_000, 4)
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
        .animation(.easeInOut(duration: SeeleSpacing.animationStandard), value: isActive)
    }
}

// MARK: - Center Node

struct CenterNode: View {
    let username: String

    var body: some View {
        VStack(spacing: SeeleSpacing.xs) {
            ZStack {
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

                Circle()
                    .fill(SeeleColors.accent)
                    .frame(width: 50, height: 50)
                    .shadow(color: SeeleColors.accent.opacity(0.5), radius: 10)

                Image(systemName: "person.fill")
                    .font(.system(size: SeeleSpacing.iconSizeMedium, weight: .semibold))
                    .foregroundStyle(SeeleColors.textOnAccent)
            }

            Text(username)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(username)")
    }
}
