import SwiftUI

struct MenuBarView: View {
    @Environment(\.appState) private var appState

    private var status: ConnectionStatus {
        appState.connection.connectionStatus
    }

    private var activeDown: Int {
        appState.transferState.activeDownloads.count
    }

    private var activeUp: Int {
        appState.uploadManager.activeUploadCount
    }

    var body: some View {
        Text("Status: \(status.label)")

        if activeDown > 0 {
            Text("\(activeDown) download\(activeDown == 1 ? "" : "s") active")
        }
        if activeUp > 0 {
            Text("\(activeUp) upload\(activeUp == 1 ? "" : "s") active")
        }

        Divider()

        Button("Open SeeleSeek") {
            NSApplication.shared.activate()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

#Preview {
    MenuBarView()
        .environment(\.appState, AppState())
}
