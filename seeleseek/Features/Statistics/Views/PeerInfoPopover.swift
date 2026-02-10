import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(displayName)
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text(peer.state == .connected ? "Connected" : String(describing: peer.state))
                        .font(SeeleTypography.caption)
                        .foregroundStyle(peer.state == .connected ? SeeleColors.success : SeeleColors.textTertiary)
                }

                Spacer()

                Text(peer.connectionType.rawValue)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, 4)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(Capsule())
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Connection info
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                DetailRow(label: "IP Address", value: peer.ip)
                DetailRow(label: "Port", value: "\(peer.port)")

                if let connectedAt = peer.connectedAt {
                    DetailRow(label: "Connected", value: formatDate(connectedAt))
                    DetailRow(label: "Duration", value: formatDuration(Date().timeIntervalSince(connectedAt)))
                }

                if let lastActivity = peer.lastActivity {
                    DetailRow(label: "Last Activity", value: formatDate(lastActivity))
                }
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Transfer stats
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Transfer Statistics")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)

                HStack(spacing: SeeleSpacing.xl) {
                    VStack(alignment: .leading) {
                        Text("Downloaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(ByteFormatter.format(Int64(peer.bytesReceived)))
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.success)
                    }

                    VStack(alignment: .leading) {
                        Text("Uploaded")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text(ByteFormatter.format(Int64(peer.bytesSent)))
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.accent)
                    }
                }

                if peer.currentSpeed > 0 {
                    DetailRow(label: "Current Speed", value: ByteFormatter.formatSpeed(Int64(peer.currentSpeed)))
                }
            }

            // Actions (only if we have a username)
            if hasUsername {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                HStack(spacing: SeeleSpacing.md) {
                    Button {
                        appState.browseState.browseUser(peer.username)
                        appState.sidebarSelection = .browse
                        dismiss()
                    } label: {
                        Label("Browse", systemImage: "folder")
                            .font(SeeleTypography.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SeeleColors.info)

                    Button {
                        appState.chatState.selectPrivateChat(peer.username)
                        appState.sidebarSelection = .chat
                        dismiss()
                    } label: {
                        Label("Message", systemImage: "bubble.left")
                            .font(SeeleTypography.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SeeleColors.info)

                    Spacer()
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(width: 300)
        .background(SeeleColors.surface)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
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
        }
    }
}
