import SwiftUI

struct MenuBarView: View {
    @Environment(\.appState) private var appState

    private var status: ConnectionStatus {
        appState.connection.connectionStatus
    }

    private var username: String? {
        appState.connection.username
    }

    private var activeDown: Int {
        appState.transferState.activeDownloads.count
    }

    private var activeUp: Int {
        appState.uploadManager.activeUploadCount
    }

    private var queuedCount: Int {
        appState.transferState.queuedDownloads.count
    }

    private var downSpeed: Int64 {
        appState.transferState.totalDownloadSpeed
    }

    private var upSpeed: Int64 {
        appState.transferState.totalUploadSpeed
    }

    var body: some View {
        // Connection header
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .medium))
            VStack(alignment: .leading, spacing: 1) {
                if let username, status == .connected {
                    Text(username)
                        .font(SeeleTypography.headline)
                } else {
                    Text(status.label)
                        .font(SeeleTypography.headline)
                }
                Text(status == .connected ? "Connected" : status.label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(status.color)
                    .opacity(status == .connected && username != nil ? 1 : 0)
            }
        }
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.xs)

        if activeDown > 0 || activeUp > 0 {
            Divider()

            // Active transfers
            if activeDown > 0 {
                HStack(spacing: SeeleSpacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(SeeleColors.info)
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                    Text("\(activeDown) download\(activeDown == 1 ? "" : "s")")
                        .font(SeeleTypography.body)
                    Spacer()
                    if downSpeed > 0 {
                        Text(ByteFormatter.formatSpeed(downSpeed))
                            .font(SeeleTypography.monoSmall)
                            .foregroundStyle(SeeleColors.info)
                    }
                }
                .padding(.horizontal, SeeleSpacing.sm)
                .padding(.vertical, SeeleSpacing.xxs)
            }

            if activeUp > 0 {
                HStack(spacing: SeeleSpacing.sm) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(SeeleColors.success)
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                    Text("\(activeUp) upload\(activeUp == 1 ? "" : "s")")
                        .font(SeeleTypography.body)
                    Spacer()
                    if upSpeed > 0 {
                        Text(ByteFormatter.formatSpeed(upSpeed))
                            .font(SeeleTypography.monoSmall)
                            .foregroundStyle(SeeleColors.success)
                    }
                }
                .padding(.horizontal, SeeleSpacing.sm)
                .padding(.vertical, SeeleSpacing.xxs)
            }
        }

        if queuedCount > 0 {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(SeeleColors.warning)
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                Text("\(queuedCount) queued")
                    .font(SeeleTypography.body)
                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.xxs)
        }

        Divider()

        Button {
            NSApplication.shared.activate()
        } label: {
            Label("Open SeeleSeek", systemImage: "macwindow")
        }
        .keyboardShortcut("o")

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit SeeleSeek", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}

#Preview {
    MenuBarView()
        .environment(\.appState, AppState())
}
