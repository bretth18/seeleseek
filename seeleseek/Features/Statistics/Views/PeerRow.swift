import SwiftUI
import SeeleseekCore

struct PeerRow: View {
    let peer: PeerConnectionPool.PeerConnectionInfo

    @State private var isHovered = false
    @State private var showingDetail = false

    private var stateColor: Color {
        switch peer.state {
        case .connected: return SeeleColors.success
        case .connecting, .handshaking: return SeeleColors.warning
        case .disconnected: return SeeleColors.textTertiary
        case .failed: return SeeleColors.error
        }
    }

    private var displayName: String {
        !peer.username.isEmpty && peer.username != "unknown" ? peer.username : peer.ip
    }

    private var subtitleText: String {
        !peer.username.isEmpty && peer.username != "unknown" ? peer.ip : peer.connectionType.rawValue
    }

    private func connectionDuration(now: Date) -> String {
        guard let connectedAt = peer.connectedAt else { return "--" }
        let duration = now.timeIntervalSince(connectedAt)
        if duration < 60 { return "\(Int(duration))s" }
        if duration < 3600 { return "\(Int(duration / 60))m" }
        return "\(Int(duration / 3600))h"
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: SeeleSpacing.md) {
                statusIndicator

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(displayName)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    HStack(spacing: SeeleSpacing.sm) {
                        Text(subtitleText)
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)

                        Text("•")
                            .foregroundStyle(SeeleColors.textTertiary)

                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(connectionDuration(now: ctx.date))
                                .font(SeeleTypography.caption2)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: SeeleSpacing.lg) {
                    Text("↓ \(peer.bytesReceived.formattedBytes)")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.success)
                        .contentTransition(.numericText())

                    Text("↑ \(peer.bytesSent.formattedBytes)")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.accent)
                        .contentTransition(.numericText())
                }

                Text(peer.connectionType.rawValue)
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, SeeleSpacing.xxs)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? SeeleColors.surfaceSecondary : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showingDetail) {
            PeerInfoPopover(peer: peer)
        }
        .contextMenu {
            if !peer.username.isEmpty && peer.username != "unknown" {
                Button("Copy Username") {
                    copyToPasteboard(peer.username)
                }
            }
            Button("Copy IP Address") {
                copyToPasteboard("\(peer.ip):\(peer.port)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(peer.state.accessibilityLabel)")
        .accessibilityValue("Received \(peer.bytesReceived.formattedBytes), sent \(peer.bytesSent.formattedBytes)")
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.3))
                .frame(width: SeeleSpacing.iconSizeLarge, height: SeeleSpacing.iconSizeLarge)

            Circle()
                .fill(stateColor)
                .frame(width: SeeleSpacing.statusDotLarge, height: SeeleSpacing.statusDotLarge)
        }
        .animation(.easeInOut(duration: SeeleSpacing.animationStandard), value: stateColor)
    }

    private func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

private extension PeerConnection.State {
    var accessibilityLabel: String {
        switch self {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .handshaking: return "handshaking"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        }
    }
}
