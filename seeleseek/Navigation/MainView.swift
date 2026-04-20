import SwiftUI
import SeeleseekCore

struct MainView: View {
    @Environment(\.appState) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .onChange(of: appState.updateState.showUpdatePrompt) { _, show in
            if show { openWindow(id: "update-prompt") }
        }
        .task {
            // Catch the case where checkForUpdate() already flipped the flag
            // before onChange had a chance to install.
            if appState.updateState.showUpdatePrompt {
                openWindow(id: "update-prompt")
            }
        }
        #endif
        .alert("Server Message", isPresented: Binding(
            get: { appState.showAdminMessageAlert },
            set: { appState.showAdminMessageAlert = $0 }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = appState.latestAdminMessage {
                Text(msg.message)
            }
        }
        #if DEBUG
        .onAppear {
            // Cmd+Shift+T to run protocol test
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "t" {
                    Task {
                        await ProtocolTest.runLocalServerTest()
                    }
                    return nil
                }
                return event
            }
        }
        #endif
    }

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: Binding(
            get: { appState.socialState.showProfileSheet },
            set: { appState.socialState.showProfileSheet = $0 }
        )) {
            if let profile = appState.socialState.viewingProfile {
                UserProfileSheet(profile: profile)
            }
        }
    }
    #endif

    #if os(iOS)
    private var iOSLayout: some View {
        TabView(selection: $appState.selectedTab) {
            ForEach(NavigationTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: NavigationTab) -> some View {
        switch tab {
        case .search:
            PlaceholderView(title: "Search", icon: "magnifyingglass")
        case .transfers:
            PlaceholderView(title: "Transfers", icon: "arrow.down.arrow.up")
        case .chat:
            PlaceholderView(title: "Chat", icon: "bubble.left.and.bubble.right")
        case .browse:
            PlaceholderView(title: "Browse", icon: "folder")
        case .settings:
            PlaceholderView(title: "Settings", icon: "gear")
        }
    }
    #endif

    @ViewBuilder
    private var detailView: some View {
        // Show login when disconnected OR when there's a login error (so user can retry).
        // `isReapplyingSettings` suppresses the flash when something like a port
        // change is intentionally bouncing the connection — the user should keep
        // seeing whatever they were looking at, not the login screen.
        if (appState.connection.connectionStatus == .disconnected ||
            appState.connection.connectionStatus == .error) &&
           !appState.connection.isReapplyingSettings {
            LoginView()
        } else {
            switch appState.sidebarSelection {
            case .search:
                SearchView()
            case .wishlists:
                WishlistView()
            case .transfers:
                TransfersView()
            case .chat:
                ChatView()
            case .browse:
                BrowseView()
            case .social:
                SocialView()
            case .user:
                BrowseView()
            case .room:
                ChatView()
            case .networkMonitor:
                NetworkMonitorView()
            case .settings:
                SettingsView()
            case nil:
                SearchView()
            }
        }
    }
}

// MARK: - Placeholder View

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text(title)
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Coming soon")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeeleColors.background)
    }
}

#Preview {
    MainView()
        .environment(\.appState, AppState())
}
