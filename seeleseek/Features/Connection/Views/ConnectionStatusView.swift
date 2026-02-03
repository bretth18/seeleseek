import SwiftUI

struct ConnectionStatusView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            statusCard
            if appState.connection.connectionStatus == .connected {
                serverInfoCard
                actionsCard
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SeeleColors.background)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Connection Status")
                    .seeleHeadline()
                Spacer()
                ConnectionBadge(status: appState.connection.connectionStatus)
            }

            if let username = appState.connection.username {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                HStack {
                    Label("Username", systemImage: "person.fill")
                        .seeleSecondary()
                    Spacer()
                    Text(username)
                        .seeleBody()
                }
            }

            if let error = appState.connection.errorMessage {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                HStack(spacing: SeeleSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SeeleColors.error)
                    Text(error)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.error)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var serverInfoCard: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Server Information")
                .seeleHeadline()

            Divider()
                .background(SeeleColors.surfaceSecondary)

            if let ip = appState.connection.serverIP {
                HStack {
                    Label("Server IP", systemImage: "server.rack")
                        .seeleSecondary()
                    Spacer()
                    Text(ip)
                        .seeleMono()
                }
            }

            HStack {
                Label("Server", systemImage: "globe")
                    .seeleSecondary()
                Spacer()
                Text("server.slsknet.org:2242")
                    .seeleMono()
            }

            if let greeting = appState.connection.serverGreeting {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                Text(greeting)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .italic()
            }
        }
        .cardStyle()
    }

    private var actionsCard: some View {
        VStack(spacing: SeeleSpacing.md) {
            SecondaryButton("Disconnect", icon: "xmark.circle") {
                Task {
                    await disconnect()
                }
            }
        }
        .cardStyle()
    }

    private func disconnect() async {
        await appState.networkClient.disconnect()
        appState.connection.setDisconnected()
    }
}

// MARK: - Compact Connection Status (for toolbar/header)

struct CompactConnectionStatus: View {
    @Environment(\.appState) private var appState

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            ConnectionBadge(status: appState.connection.connectionStatus, showLabel: false)

            if let username = appState.connection.username {
                Text(username)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
        }
    }
}

#Preview("Connected") {
    let state = AppState()
    state.connection.setConnected(
        username: "testuser",
        ip: "208.76.170.59",
        greeting: "Welcome to SoulSeek! Please be respectful to other users."
    )

    return ConnectionStatusView()
        .environment(\.appState, state)
}

#Preview("Disconnected") {
    ConnectionStatusView()
        .environment(\.appState, AppState())
}

#Preview("Error") {
    let state = AppState()
    state.connection.setError("Connection timed out")

    return ConnectionStatusView()
        .environment(\.appState, state)
}
