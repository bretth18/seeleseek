import SwiftUI
import SeeleseekCore

struct MenuBarView: View {
    @Environment(\.appState) private var appState

    private var status: ConnectionStatus {
        appState.connection.connectionStatus
    }

    private var connectedUsername: String? {
        status == .connected ? appState.connection.username : nil
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
        // Hoisted: activeDownloads/activeUploads/queuedDownloads each re-filter
        // the full transfer array on every read.
        let downloads = activeDownloads
        let uploads = activeUploads
        let queued = queuedCount

        Text("\(Image(systemName: status.icon)) \(connectedUsername ?? status.label)")
            .foregroundStyle(status.color)
            .accessibilityLabel(headerAccessibilityLabel)

        if connectedUsername != nil {
            Text(status.label)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
        }

        if status == .connected {
            let down = downSpeed.formattedSpeed
            let up = upSpeed.formattedSpeed

            Text(speedLine(down: down, up: up))
                .accessibilityLabel("Download speed \(down), upload speed \(up)")

            // No shortcut: ⌘⇧A is already bound in CommandMenu("Connection").
            Toggle("Away", isOn: awayBinding)
        }

        if !downloads.isEmpty || !uploads.isEmpty || queued > 0 {
            Divider()

            if !downloads.isEmpty {
                transferMenu(downloads, noun: "download", systemImage: "arrow.down.circle.fill")
            }

            if !uploads.isEmpty {
                transferMenu(uploads, noun: "upload", systemImage: "arrow.up.circle.fill")
            }

            if queued > 0 {
                Button {
                    open(.transfers)
                } label: {
                    Label("\(queued) queued", systemImage: "clock.fill")
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
    private func speedLine(down: String, up: String) -> AttributedString {
        var downRun = AttributedString("↓ \(down)")
        downRun.foregroundColor = SeeleColors.info
        var upRun = AttributedString("     ↑ \(up)")
        upRun.foregroundColor = SeeleColors.success
        return downRun + upRun
    }

    private func open(_ item: SidebarItem) {
        appState.sidebarSelection = item
        NSApplication.shared.activate()
    }

    private var headerAccessibilityLabel: String {
        var label = "Connection status: \(status.label)"
        if let connectedUsername {
            label += " as \(connectedUsername)"
        }
        return label
    }
}

#if DEBUG
@MainActor
private func previewState(
    _ status: ConnectionStatus,
    downloads: [Transfer] = [],
    uploads: [Transfer] = [],
    away: Bool = false
) -> AppState {
    let state = switch status {
    case .connected: PreviewData.connectedAppState
    case .connecting: PreviewData.connectingAppState
    case .reconnecting: PreviewData.reconnectingAppState
    case .error: PreviewData.errorAppState
    case .disconnected: PreviewData.disconnectedAppState
    }

    if away {
        state.connection.onlineStatus = .away
    }

    state.transferState.downloads = downloads
    state.transferState.uploads = uploads
    // Seeds the totals from the transfers above, exactly as the 1Hz timer
    // would, so the first frame is not blank.
    state.transferState.updateSpeeds()

    return state
}

/// `MenuBarView` returns menu items, so rendering it bare stacks them as plain
/// views and hides the exact flattening this file is written around. Every
/// preview goes through a real `Menu` — click it to see what ships.
private struct MenuBarPreview: View {
    let title: String
    let state: AppState

    var body: some View {
        Menu {
            MenuBarView()
                .previewAppState(state)
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
            state: previewState(
                .connected,
                downloads: PreviewData.sampleDownloads,
                uploads: PreviewData.sampleUploads
            )
        )
    }
    .padding()
    .frame(width: 320, alignment: .leading)
}

#Preview("Connected, transferring") {
    MenuBarPreview(
        title: "SeeleSeek",
        state: previewState(
            .connected,
            downloads: PreviewData.sampleDownloads,
            uploads: PreviewData.sampleUploads
        )
    )
    .padding()
}

#Preview("Disconnected") {
    MenuBarPreview(title: "SeeleSeek", state: previewState(.disconnected))
        .padding()
}
#endif
