import SwiftUI

struct MonitorQuickPeersCard: View {
    @Environment(\.appState) private var appState

    private var topPeers: [PeerConnectionPool.PeerConnectionInfo] {
        appState.networkClient.peerConnectionPool.topPeersByTraffic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Top Peers")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            if topPeers.isEmpty {
                Text("No peer activity")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SeeleSpacing.xl)
            } else {
                ForEach(topPeers.prefix(5)) { peer in
                    QuickPeerRow(peer: peer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

struct QuickPeerRow: View {
    let peer: PeerConnectionPool.PeerConnectionInfo

    private var displayName: String {
        !peer.username.isEmpty && peer.username != "unknown" ? peer.username : peer.ip
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Circle()
                .fill(peer.state == .connected ? SeeleColors.success : SeeleColors.textTertiary)
                .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)

            Text(displayName)
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(ByteFormatter.format(Int64(peer.bytesReceived + peer.bytesSent)))
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}
