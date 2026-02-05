import SwiftUI
import MapKit

/// World map visualization showing peer connection locations
struct PeerWorldMap: View {
    @Environment(\.appState) private var appState
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var peerLocations: [PeerConnectionPool.PeerConnectionInfo] {
        Array(appState.networkClient.peerConnectionPool.connections.values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            // Header
            HStack {
                Text("Peer Network")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(peerLocations.count) peers")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            // Map or placeholder
            ZStack {
                if peerLocations.isEmpty {
                    // Empty state
                    RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius)
                        .fill(SeeleColors.surfaceSecondary)
                        .overlay {
                            VStack(spacing: SeeleSpacing.md) {
                                Image(systemName: "map")
                                    .font(.system(size: SeeleSpacing.iconSizeXL, weight: .light))
                                    .foregroundStyle(SeeleColors.textTertiary)
                                Text("No peer connections")
                                    .font(SeeleTypography.subheadline)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        }
                } else {
                    // Simplified network visualization (without actual geo-location)
                    NetworkRadialView(peers: peerLocations)
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

            // Stats row
            HStack(spacing: SeeleSpacing.xl) {
                StatPill(label: "Active", value: "\(appState.networkClient.peerConnectionPool.activeConnections)", color: SeeleColors.success)
                StatPill(label: "Total", value: "\(appState.networkClient.peerConnectionPool.totalConnections)", color: SeeleColors.info)
                StatPill(label: "Speed", value: ByteFormatter.formatSpeed(Int64(appState.networkClient.peerConnectionPool.currentDownloadSpeed + appState.networkClient.peerConnectionPool.currentUploadSpeed)), color: SeeleColors.accent)
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

// MARK: - Network Radial View

/// A radial visualization showing peers connected to the center (you)
struct NetworkRadialView: View {
    let peers: [PeerConnectionPool.PeerConnectionInfo]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 40

            // Background grid rings
            for ring in 1...3 {
                let ringRadius = radius * CGFloat(ring) / 3
                let path = Path(ellipseIn: CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                ))
                context.stroke(path, with: .color(SeeleColors.surfaceSecondary), lineWidth: 1)
            }

            // Connection lines and peer nodes
            let peerCount = max(peers.count, 1)
            for (index, peer) in peers.enumerated() {
                let angle = CGFloat(index) / CGFloat(peerCount) * 2 * .pi - .pi / 2
                // Use a deterministic distance based on peer ID hash
                let hashValue = abs(peer.id.hashValue)
                let varianceRatio = CGFloat(hashValue % 100) / 200.0
                let distance = radius * (0.6 + varianceRatio)

                let peerPoint = CGPoint(
                    x: center.x + cos(angle) * distance,
                    y: center.y + sin(angle) * distance
                )

                // Connection line
                var linePath = Path()
                linePath.move(to: center)
                linePath.addLine(to: peerPoint)

                let lineColor: Color = peer.state == .connected ? SeeleColors.success.opacity(0.5) : SeeleColors.textTertiary.opacity(0.3)
                context.stroke(linePath, with: .color(lineColor), lineWidth: peer.state == .connected ? 2 : 1)

                // Peer node
                let nodeSize: CGFloat = 12
                let nodeRect = CGRect(
                    x: peerPoint.x - nodeSize / 2,
                    y: peerPoint.y - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                )

                let nodeColor: Color = {
                    switch peer.state {
                    case .connected: return SeeleColors.success
                    case .connecting, .handshaking: return SeeleColors.warning
                    case .disconnected: return SeeleColors.textTertiary
                    case .failed: return SeeleColors.error
                    }
                }()

                // Glow
                let glowRect = CGRect(
                    x: peerPoint.x - nodeSize,
                    y: peerPoint.y - nodeSize,
                    width: nodeSize * 2,
                    height: nodeSize * 2
                )
                context.fill(Path(ellipseIn: glowRect), with: .color(nodeColor.opacity(0.3)))

                // Node
                context.fill(Path(ellipseIn: nodeRect), with: .color(nodeColor))
            }

            // Center node
            let centerGlowSize: CGFloat = 40
            let centerGlowRect = CGRect(
                x: center.x - centerGlowSize / 2,
                y: center.y - centerGlowSize / 2,
                width: centerGlowSize,
                height: centerGlowSize
            )
            context.fill(Path(ellipseIn: centerGlowRect), with: .color(SeeleColors.accent.opacity(0.4)))

            let centerSize: CGFloat = 16
            let centerRect = CGRect(
                x: center.x - centerSize / 2,
                y: center.y - centerSize / 2,
                width: centerSize,
                height: centerSize
            )
            context.fill(Path(ellipseIn: centerRect), with: .color(SeeleColors.accent))
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: SeeleSpacing.xxs) {
            Text(value)
                .font(SeeleTypography.mono)
                .foregroundStyle(color)
            Text(label)
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
    }
}

#Preview {
    PeerWorldMap()
        .environment(\.appState, AppState())
        .frame(width: 500, height: 400)
}
