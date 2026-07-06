import SwiftUI
import SeeleseekCore

struct LoginView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        @Bindable var connectionState = appState.connection

        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SeeleSpacing.xxl) {
                // Logo / Title
                VStack(spacing: SeeleSpacing.md) {
                    Image(nsImage: .gsgaag2)
                        .renderingMode(.template)

                    .foregroundStyle(SeeleColors.accent)

                    Text("seeleseek")
                        .font(SeeleTypography.logo)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("a soulseek client for your seele")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

                // Login Form
                VStack(spacing: SeeleSpacing.lg) {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        Text("Username")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        TextField("", text: $connectionState.loginUsername)
                            .textFieldStyle(SeeleTextFieldStyle())
                            .textContentType(.username)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        Text("Password")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        SecureField("", text: $connectionState.loginPassword)
                            .textFieldStyle(SeeleTextFieldStyle())
                            .textContentType(.password)
                    }

                    Toggle("Remember me", isOn: $connectionState.rememberCredentials)
                        .toggleStyle(SeeleToggleStyle())
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textSecondary)

                    if let error = appState.connection.errorMessage {
                        HStack(spacing: SeeleSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.error)
                        .padding(SeeleSpacing.md)
                        .frame(maxWidth: .infinity)
                        .background(SeeleColors.error.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PrimaryButton(
                        "Connect",
                        icon: "network",
                        isLoading: appState.connection.connectionStatus == .connecting
                    ) {
                        Task {
                            await connect()
                        }
                    }
                    .disabled(!appState.connection.isLoginValid)
                }
                .frame(maxWidth: 320)
                .animation(.easeInOut(duration: SeeleSpacing.animationStandard), value: appState.connection.errorMessage != nil)
            }
            .padding(SeeleSpacing.xxl)
            .cardStyle()

            Spacer()

            // Footer
            VStack(spacing: SeeleSpacing.xs) {
                Text("Connecting to server.slsknet.org:2242")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .padding(.bottom, SeeleSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeeleColors.background)
        .onAppear {
            loadSavedCredentials()
        }
    }

    private func connect() async {
        appState.connection.setConnecting()

        // Connection-status handling is wired app-wide in
        // AppState.wireNetworkClient() — this stays form-local.
        appState.networkClient.acceptDistributedChildren = appState.settings.respondToSearches

        await appState.networkClient.connect(
            server: ServerConnection.defaultHost,
            port: ServerConnection.defaultPort,
            username: appState.connection.loginUsername,
            password: appState.connection.loginPassword,
            preferredListenPort: UInt16(appState.settings.listenPort)
        )

        if let error = appState.networkClient.connectionError {
            appState.connection.setError(error)
        }
    }

    private func loadSavedCredentials() {
        // Only prefill when both fields are empty — the view re-appears
        // (e.g. after a failed attempt) and reloading would clobber
        // whatever the user has typed.
        guard appState.connection.loginUsername.isEmpty,
              appState.connection.loginPassword.isEmpty,
              let credentials = CredentialStorage.load() else { return }
        appState.connection.loginUsername = credentials.username
        appState.connection.loginPassword = credentials.password
    }
}

#Preview("Login - Empty") {
    LoginView()
        .environment(\.appState, AppState())
}

#Preview("Login - With Error") {
    let state = AppState()
    state.connection.loginUsername = "testuser"
    state.connection.loginPassword = "wrongpassword"
    state.connection.setError("Invalid username or password")

    return LoginView()
        .environment(\.appState, state)
}

