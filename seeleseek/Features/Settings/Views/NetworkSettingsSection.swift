import SwiftUI
import SeeleseekCore

struct NetworkSettingsSection: View {
    @Environment(\.appState) private var appState
    @Bindable var settings: SettingsState

    @State private var isApplyingPort = false
    /// One-shot error surfaced under the Apply row when the bounce
    /// fails (e.g. the requested port is already in use). Cleared
    /// when the user starts another apply attempt.
    @State private var portApplyError: String?
    /// Focus on the listen-port TextField. Tracked so we can defocus
    /// the field before reading `settings.listenPort` in the apply
    /// path — `TextField(value:format:)` only writes back to its
    /// binding on focus loss / submit, so a button action that runs
    /// while the field still has focus would otherwise see a stale
    /// value.
    @FocusState private var listenPortFocused: Bool

    /// Port the listener is currently bound to (0 when offline).
    private var boundPort: Int { Int(appState.networkClient.listenPort) }

    /// True when the user has typed a port that differs from what the
    /// listener is actually bound to *and* there's a live session to
    /// bounce. While disconnected, the new value is picked up
    /// automatically on the next `connect()`, so the row stays hidden.
    private var portChangeIsLive: Bool {
        appState.connection.connectionStatus == .connected
            && boundPort > 0
            && settings.listenPort != boundPort
    }

    /// Re-issuing `connect()` needs the in-memory username/password the
    /// login form populated. They survive for the session — but if both
    /// happen to be empty (e.g. an unusual auto-login path) the Apply
    /// button stays disabled rather than failing silently.
    private var hasReconnectCredentials: Bool {
        !appState.connection.loginUsername.isEmpty
            && !appState.connection.loginPassword.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Network")

            settingsGroup("Connection") {
                listenPortRow
                if portChangeIsLive {
                    applyPortRow
                }
                if let portApplyError {
                    portApplyErrorRow(portApplyError)
                }
                settingsToggle("Enable UPnP", isOn: $settings.enableUPnP)
                settingsToggle("Use Obfuscated Peer Protocol", isOn: $settings.enableObfuscation)
            }

            settingsGroup("Transfer Slots") {
                settingsStepper("Max Download Slots", value: $settings.maxDownloadSlots, range: 1...20)
                settingsStepper("Max Upload Slots", value: $settings.maxUploadSlots, range: 1...20)
            }

            settingsGroup("Speed Limits") {
                settingsNumberField("Upload Limit (KB/s)", value: $settings.uploadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
                settingsNumberField("Download Limit (KB/s)", value: $settings.downloadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
            }
        }
    }

    /// Inlined version of `settingsNumberField` that exposes
    /// `FocusState` so the apply path can force a commit before
    /// reading the bound value.
    private var listenPortRow: some View {
        settingsRow {
            HStack {
                Text("Listen Port")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                Spacer()
                TextField("", value: $settings.listenPort, format: .number)
                    .textFieldStyle(SeeleTextFieldStyle())
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .focused($listenPortFocused)
                    .onSubmit { listenPortFocused = false }
            }
        }
    }

    private var applyPortRow: some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.md) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.warning)
                    .accessibilityHidden(true)

                Text("Listening on \(boundPort). Reconnect to switch to \(settings.listenPort).")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: SeeleSpacing.sm)

                Button(isApplyingPort ? "Applying…" : "Apply") {
                    Task { await applyPortChange() }
                }
                .disabled(!hasReconnectCredentials || isApplyingPort)
                .help(
                    hasReconnectCredentials
                        ? "Disconnect and reconnect using the new port"
                        : "Sign in again to apply port changes while connected"
                )
            }
        }
    }

    private func portApplyErrorRow(_ message: String) -> some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.error)
                    .accessibilityHidden(true)

                Text(message)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(3)

                Spacer(minLength: SeeleSpacing.sm)

                Button("Dismiss") {
                    portApplyError = nil
                }
                .buttonStyle(.plain)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.accent)
            }
        }
    }

    private func applyPortChange() async {
        // Force the TextField to commit any in-flight typing to the
        // binding before we read settings.listenPort. Yield to the
        // runloop so the focus change actually propagates. SwiftUI
        // commits @FocusState transitions on the next runloop tick;
        // a single yield is enough today but the dependency is fragile
        // — if a future SwiftUI release reorders this, the apply path
        // will silently use the stale port.
        listenPortFocused = false
        await Task.yield()

        let username = appState.connection.loginUsername
        let password = appState.connection.loginPassword
        let targetPort = settings.listenPort
        // Snapshot before disconnect — `boundPort` reads listenPort,
        // which `performDisconnect` clears to 0.
        let originalPort = boundPort
        guard !username.isEmpty, !password.isEmpty else { return }
        guard targetPort != originalPort else { return }

        isApplyingPort = true
        portApplyError = nil
        // Suppress LoginView for the brief `.disconnected` window the
        // bounce produces — see `ConnectionState.isReapplyingSettings`.
        appState.connection.isReapplyingSettings = true
        defer {
            isApplyingPort = false
            appState.connection.isReapplyingSettings = false
        }

        // disconnectAsync (vs sync disconnect) awaits the listener / NAT
        // teardown so the follow-up start() doesn't race a still-pending
        // stop() on the listenerService actor — that race left the new
        // listener cancelled and the old one leaking on its original port.
        await appState.networkClient.disconnectAsync()
        await appState.networkClient.connect(
            server: ServerConnection.defaultHost,
            port: ServerConnection.defaultPort,
            username: username,
            password: password,
            preferredListenPort: UInt16(targetPort)
        )

        // If the bounce didn't end with us connected, the listener
        // either failed to bind the requested port (already in use,
        // privileged, etc.) or the server login failed. NetworkClient
        // schedules an auto-reconnect with the *same* preferredListenPort,
        // which would loop forever on a bad port. Cancel the loop, revert
        // the field, reconnect on the original port, and surface a
        // visible error so the user knows the apply didn't take.
        if appState.connection.connectionStatus != .connected {
            await appState.networkClient.disconnectAsync()
            settings.listenPort = originalPort
            portApplyError = "Couldn't bind port \(targetPort). Reverted to \(originalPort)."
            if originalPort > 0 {
                await appState.networkClient.connect(
                    server: ServerConnection.defaultHost,
                    port: ServerConnection.defaultPort,
                    username: username,
                    password: password,
                    preferredListenPort: UInt16(originalPort)
                )
            }
        }
    }
}

#Preview {
    ScrollView {
        NetworkSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
