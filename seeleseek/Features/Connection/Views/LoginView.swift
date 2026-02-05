import SwiftUI

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
//                        .frame(width: SeeleSpacing.iconSize, height: SeeleSpacing.iconSize)

//                    .font(.system(size: SeeleSpacing.iconSizeHero + 16, weight: .light))
                    .foregroundStyle(SeeleColors.accent)

                    Text("seeleseek")
                        .font(SeeleTypography.largeTitle)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("a soulseek client from The Virtuous Corporation")
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

        // Set up callbacks
        appState.networkClient.onConnectionStatusChanged = { status in
            switch status {
            case .connected:
                if appState.connection.rememberCredentials {
                    CredentialStorage.save(
                        username: appState.connection.loginUsername,
                        password: appState.connection.loginPassword
                    )
                }
                appState.connection.setConnected(
                    username: appState.connection.loginUsername,
                    ip: "",
                    greeting: nil
                )
                // Resume any queued downloads from previous session
                appState.downloadManager.resumeQueuedDownloads()
            case .disconnected:
                appState.connection.setDisconnected()
            case .connecting:
                appState.connection.setConnecting()
            case .error:
                appState.connection.setError(appState.networkClient.connectionError ?? "Unknown error")
            }
        }

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
        if let credentials = CredentialStorage.load() {
            appState.connection.loginUsername = credentials.username
            appState.connection.loginPassword = credentials.password
        }
    }
}

// MARK: - Custom TextField Style

struct SeeleTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm + 2)
            .background(SeeleColors.surfaceSecondary)
            .foregroundStyle(SeeleColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.border, lineWidth: 1)
            )
    }
}

// MARK: - Custom Toggle Style

struct SeeleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(configuration.isOn ? SeeleColors.accent : SeeleColors.surfaceElevated)
                    .frame(width: 46, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(configuration.isOn ? SeeleColors.accent : SeeleColors.border, lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Form Section Style

struct SeeleFormSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text(title)
                .font(SeeleTypography.caption)
                .fontWeight(.medium)
                .foregroundStyle(SeeleColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 0) {
                content
            }
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Form Row Style

struct SeeleFormRow<Content: View>: View {
    let content: Content
    let showDivider: Bool

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.vertical, SeeleSpacing.sm + 2)

            if showDivider {
                Divider()
                    .background(SeeleColors.border)
                    .padding(.leading, SeeleSpacing.md)
            }
        }
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

