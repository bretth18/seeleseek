import SwiftUI
import SeeleseekCore

struct PeerInfoPopover: View {
    let peer: PeerConnectionPool.PeerConnectionInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    private var hasUsername: Bool {
        !peer.username.isEmpty && peer.username != "unknown"
    }

    private var displayName: String {
        hasUsername ? peer.username : peer.ip
    }

    private var stateLabel: String {
        switch peer.state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .handshaking: "Handshaking"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }

    private var stateColor: Color {
        switch peer.state {
        case .connected: SeeleColors.success
        case .connecting, .handshaking: SeeleColors.warning
        case .disconnected: SeeleColors.textTertiary
        case .failed: SeeleColors.error
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            header

            Divider()
                .background(SeeleColors.surfaceSecondary)

            connectionInfo

            Divider()
                .background(SeeleColors.surfaceSecondary)

            transferStats

            if hasUsername {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                actions
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(width: 320)
        .background(SeeleColors.surface)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(displayName)
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
                    Text(stateLabel)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(stateColor)

                    if let version = peer.seeleSeekVersion {
                        // Only set for SeeleSeek peers who completed the
                        // capability handshake; standard Soulseek clients
                        // (Nicotine+, SoulseekQt, etc.) never expose their
                        // version peer-to-peer, so nothing to show.
                        Text("seeleseek v\(version)")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.accent)
                            .padding(.horizontal, SeeleSpacing.xs)
                            .padding(.vertical, SeeleSpacing.xxs)
                            .background(SeeleColors.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Text(peer.connectionType.rawValue)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
                .padding(.horizontal, SeeleSpacing.sm)
                .padding(.vertical, SeeleSpacing.xxs)
                .background(SeeleColors.surfaceSecondary)
                .clipShape(Capsule())
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            DetailRow(label: "IP Address", value: "\(peer.ip):\(peer.port)")

            if let connectedAt = peer.connectedAt {
                DetailRow(label: "Connected", value: connectedAt.formatted(date: .omitted, time: .shortened))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    DetailRow(label: "Duration", value: connectedAt.durationSinceNow)
                }
            }

            // `lastActivity(for:)` reads non-observable shadow storage, so
            // we need to drive our own refresh cadence — otherwise the
            // timestamp freezes at whatever the dict held the first time
            // the popover body ran. The value is minute-resolution, so a
            // 1 Hz TimelineView is plenty.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let lastActivity = appState.networkClient.peerConnectionPool.lastActivity(for: peer.id) {
                    DetailRow(label: "Last Activity", value: lastActivity.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    private var transferStats: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Transfer Statistics")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            HStack(spacing: SeeleSpacing.xl) {
                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text("Downloaded")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text(peer.bytesReceived.formattedBytes)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.success)
                        .contentTransition(.numericText())
                }

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text("Uploaded")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text(peer.bytesSent.formattedBytes)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.accent)
                        .contentTransition(.numericText())
                }
            }

            if peer.currentSpeed > 0 {
                DetailRow(label: "Current Speed", value: peer.currentSpeed.formattedSpeed)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: SeeleSpacing.md) {
            Button {
                appState.browseState.browseUser(peer.username)
                appState.sidebarSelection = .browse
                dismiss()
            } label: {
                Label("Browse", systemImage: "folder")
            }
            .buttonStyle(.borderless)

            Button {
                appState.chatState.selectPrivateChat(peer.username)
                appState.sidebarSelection = .chat
                dismiss()
            } label: {
                Label("Message", systemImage: "bubble.left")
            }
            .buttonStyle(.borderless)

            Spacer()
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
                .textSelection(.enabled)
        }
    }
}
