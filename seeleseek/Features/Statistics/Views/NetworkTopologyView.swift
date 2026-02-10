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
        .animation(.easeInOut(duration: 0.3), value: isActive)
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
    }
}

#Preview {
    NetworkVisualizationView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
