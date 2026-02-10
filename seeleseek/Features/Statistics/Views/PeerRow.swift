import SwiftUI

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
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(!peer.username.isEmpty && peer.username != "unknown" ? peer.username : peer.ip)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textPrimary)

                HStack(spacing: SeeleSpacing.sm) {
                    Text(!peer.username.isEmpty && peer.username != "unknown" ? peer.ip : peer.connectionType.rawValue)
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
                VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
                    Text("↓ \(ByteFormatter.format(Int64(peer.bytesReceived)))")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.success)
                }

                VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
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
