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
                VStack(spacing: SeeleSpacing.md) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: SeeleSpacing.iconSizeXL, weight: .light))
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("No peers connected")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                    ForEach(sortedPeers) { peer in
                        PeerRow(peer: peer)
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

#Preview {
    LivePeersView()
        .environment(\.appState, AppState())
        .frame(width: 600, height: 400)
}
