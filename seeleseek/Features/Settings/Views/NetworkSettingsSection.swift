import SwiftUI
import SeeleseekCore

struct NetworkSettingsSection: View {
    @Environment(\.appState) private var appState
    @Bindable var settings: SettingsState

    @State private var isApplyingPort = false
    /// Failed apply attempts are shown until dismissed or retried.
    @State private var portApplyError: String?
    /// Focus on the listen-port TextField. Tracked so we can defocus
    /// the field before reading `settings.listenPort` in the apply
    /// path — `TextField(value:format:)` only writes back to its
    /// binding on focus loss / submit, so a button action that runs
    /// while the field still has focus would otherwise see a stale
    /// value.
    @FocusState private var listenPortFocused: Bool

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
                if let portApplyError {
                    portApplyErrorRow(portApplyError)
                }
                settingsToggle("Enable UPnP", isOn: $settings.enableUPnP)
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
                    .accessibilityHidden(true)
                Spacer()
                TextField("", value: $settings.listenPort, format: .number.grouping(.never))
                    .textFieldStyle(SeeleTextFieldStyle())
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .focused($listenPortFocused)
                    .onSubmit { listenPortFocused = false }
                    .accessibilityLabel("Listen Port")
                    .disabled(isApplyingPort)
                Button(isApplyingPort ? "Applying…" : "Apply") {
                    Task { await applyPortChange() }
                }
                .buttonStyle(.seelePrimary(.small))
                .disabled(
                    !hasReconnectCredentials || isApplyingPort
                        || appState.connection.connectionStatus != .connected
                )
                .help("Reconnect using this listen port")
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

                Text(verbatim: message)
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
        guard !username.isEmpty, !password.isEmpty else { return }

        isApplyingPort = true
        portApplyError = nil
        // Suppress LoginView for the brief `.disconnected` window the
        // bounce produces — see `ConnectionState.isReapplyingSettings`.
        appState.connection.isReapplyingSettings = true
        defer {
            isApplyingPort = false
            appState.connection.isReapplyingSettings = false
        }

        portApplyError = await settings.applyListenPort(
            using: appState.networkClient,
            username: username,
            password: password
        )
        if let portApplyError {
            VoiceOverAnnouncer.shared.announce(portApplyError)
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        NetworkSettingsSection(settings: SettingsState())
            .padding()
    }
    .frame(width: 500, height: 400)
    .background(SeeleColors.background)
}
#endif
