import SwiftUI
import SeeleseekCore

struct MenuBarView: View {
    @Environment(\.appState) private var appState

    private var status: ConnectionStatus {
        appState.connection.connectionStatus
    }

    private var username: String? {
        appState.connection.username
    }

    private var isNamed: Bool {
        status == .connected && username != nil
    }

    private var activeDownloads: [Transfer] {
        appState.transferState.activeDownloads
    }

    private var activeUploads: [Transfer] {
        appState.transferState.activeUploads
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

    private var awayBinding: Binding<Bool> {
        Binding(
            get: { appState.connection.onlineStatus == .away },
            set: { appState.setOnlineStatus($0 ? .away : .online) }
        )
    }

    var body: some View {
        Text("\(Image(systemName: status.icon)) \(isNamed ? (username ?? "") : status.label)")
            .foregroundStyle(status.color)
            .accessibilityLabel(headerAccessibilityLabel)

        if isNamed {
            Text(status.label)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
        }

        if status == .connected {
            Text(speedLine)
                .accessibilityLabel(
                    "Download speed \(downSpeed.formattedSpeed), upload speed \(upSpeed.formattedSpeed)"
                )

            // No shortcut: ⌘⇧A is already bound in CommandMenu("Connection").
            Toggle("Away", isOn: awayBinding)
        }

        if !activeDownloads.isEmpty || !activeUploads.isEmpty || queuedCount > 0 {
            Divider()

            if !activeDownloads.isEmpty {
                transferMenu(
                    activeDownloads,
                    noun: "download",
                    systemImage: "arrow.down.circle.fill"
                )
            }

            if !activeUploads.isEmpty {
                transferMenu(
                    activeUploads,
                    noun: "upload",
                    systemImage: "arrow.up.circle.fill"
                )
            }

            if queuedCount > 0 {
                Button {
                    open(.transfers)
                } label: {
                    Label("\(queuedCount) queued", systemImage: "clock.fill")
                }
            }
        }

        Divider()

        Button {
            NSApplication.shared.activate()
        } label: {
            Label("Open SeeleSeek", systemImage: "macwindow")
        }
        .keyboardShortcut("o")

        // No shortcut: ⌘, is the system Settings equivalent already.
        SettingsLink {
            Label("Settings…", systemImage: "gear")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit SeeleSeek", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func transferMenu(
        _ transfers: [Transfer],
        noun: String,
        systemImage: String
    ) -> some View {
        Menu {
            ForEach(transfers) { transfer in
                Button("\(transfer.displayFilename)  ·  \(transfer.formattedSpeed)") {
                    open(.transfers)
                }
            }
        } label: {
            Label(
                "\(transfers.count) \(noun)\(transfers.count == 1 ? "" : "s")",
                systemImage: systemImage
            )
        }
    }

    /// Two colors in one row. Adjacent `Text`s would become two rows.
    private var speedLine: AttributedString {
        var down = AttributedString("↓ \(downSpeed.formattedSpeed)")
        down.foregroundColor = SeeleColors.info
        var up = AttributedString("     ↑ \(upSpeed.formattedSpeed)")
        up.foregroundColor = SeeleColors.success
        return down + up
    }

    private func open(_ item: SidebarItem) {
        appState.sidebarSelection = item
        NSApplication.shared.activate()
    }

    private var headerAccessibilityLabel: String {
        var label = "Connection status: \(status.label)"
        if status == .connected, let username {
            label += " as \(username)"
        }
        return label
    }
}

#if DEBUG
@MainActor
private func previewState(
    _ status: ConnectionStatus,
    username: String = "cdtest123",
    downloads: [Transfer] = [],
    uploads: [Transfer] = [],
    away: Bool = false
) -> AppState {
    let state = AppState()

    switch status {
    case .connected:
        state.connection.setConnected(username: username, ip: "51.161.9.10", greeting: nil)
    case .connecting:
        state.connection.setConnecting()
    case .reconnecting:
        state.connection.setReconnecting(reason: "Socket closed")
    case .error:
        state.connection.setError("Login failed: invalid password")
    case .disconnected:
        state.connection.setDisconnected()
    }

    if away {
        state.connection.onlineStatus = .away
    }

    state.transferState.downloads = downloads
    state.transferState.uploads = uploads
    // The 1Hz timer recomputes these from the transfers above; seeding them
    // matches so the first frame is not blank.
    state.transferState.totalDownloadSpeed = downloads
        .filter(\.isActive).reduce(0) { $0 + $1.speed }
    state.transferState.totalUploadSpeed = uploads
        .filter(\.isActive).reduce(0) { $0 + $1.speed }

    return state
}

private let previewDownloads: [Transfer] = [
    Transfer(username: "lofihouse_terrorist",
             filename: "@@music\\COMPUTER DATA\\2019 - Emotional Shift (FLAC)\\02 - Healing.flac",
             size: 32_400_000, direction: .download, status: .transferring,
             bytesTransferred: 18_900_000, startTime: Date(timeIntervalSinceNow: -22),
             speed: 2_400_000),
    Transfer(username: "shoegazer_91",
             filename: "shared\\My Bloody Valentine - Loveless (1991) [FLAC]\\04 - To Here Knows When.flac",
             size: 38_700_000, direction: .download, status: .transferring,
             bytesTransferred: 9_200_000, startTime: Date(timeIntervalSinceNow: -8),
             speed: 1_950_000),
    Transfer(username: "ok_computer_fan",
             filename: "@@radiohead\\OK Computer (1997) [FLAC]\\02 Paranoid Android.flac",
             size: 42_800_000, direction: .download, status: .queued, queuePosition: 4),
    Transfer(username: "NeckBeard22",
             filename: "Music\\Cindy Lee\\Diamond Jubilee [MP3 320]\\03 Baby Blue.mp3",
             size: 6_500_000, direction: .download, status: .queued, queuePosition: 14)
]

private let previewUploads: [Transfer] = [
    Transfer(username: "driftwavecore",
             filename: "Music\\Fennesz\\Endless Summer\\01 - Made In Hong Kong.flac",
             size: 56_200_000, direction: .upload, status: .transferring,
             bytesTransferred: 31_400_000, startTime: Date(timeIntervalSinceNow: -42),
             speed: 1_120_000)
]

/// `MenuBarView` returns menu items, so rendering it bare stacks them as plain
/// views and hides the exact flattening this file is written around. Every
/// preview goes through a real `Menu` — click it to see what ships.
private struct MenuBarPreview: View {
    let title: String
    let state: AppState

    var body: some View {
        Menu {
            MenuBarView()
                .environment(\.appState, state)
        } label: {
            Label(title, systemImage: "menubar.arrow.up.rectangle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview("All states") {
    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
        MenuBarPreview(title: "Disconnected", state: previewState(.disconnected))
        MenuBarPreview(title: "Connecting", state: previewState(.connecting))
        MenuBarPreview(title: "Reconnecting", state: previewState(.reconnecting))
        MenuBarPreview(title: "Error", state: previewState(.error))
        MenuBarPreview(title: "Connected, idle", state: previewState(.connected))
        MenuBarPreview(title: "Connected, away", state: previewState(.connected, away: true))
        MenuBarPreview(
            title: "Connected, transferring",
            state: previewState(.connected, downloads: previewDownloads, uploads: previewUploads)
        )
    }
    .padding()
    .frame(width: 320, alignment: .leading)
}

#Preview("Connected, transferring") {
    MenuBarPreview(
        title: "SeeleSeek",
        state: previewState(.connected, downloads: previewDownloads, uploads: previewUploads)
    )
    .padding()
}

#Preview("Disconnected") {
    MenuBarPreview(title: "SeeleSeek", state: previewState(.disconnected))
        .padding()
}
#endif
