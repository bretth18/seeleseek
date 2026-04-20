import SwiftUI
import SeeleseekCore

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
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                HStack {
                    Text("Connected Peers")
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Spacer()

                    HStack(spacing: SeeleSpacing.sm) {
                        Circle()
                            .fill(SeeleColors.success)
                            .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
                        Text("\(peerPool.activeConnections) active")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(peerPool.activeConnections) active peers")
                }

                if sortedPeers.isEmpty {
                    StandardEmptyState(
                        icon: "person.2.slash",
                        title: "No Peers",
                        subtitle: "Peer connections will appear here as they come online."
                    )
                    .frame(minHeight: 160)
                } else {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(sortedPeers) { peer in
                            PeerRow(peer: peer)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    LivePeersView()
        .environment(\.appState, AppState())
        .frame(width: 600, height: 400)
}
