import SwiftUI

struct MainView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .preferredColorScheme(.dark)
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
        if appState.connection.connectionStatus == .disconnected {
            LoginView()
        } else {
            switch appState.sidebarSelection {
            case .search:
                SearchView()
            case .transfers:
                TransfersView()
            case .chat:
                ChatView()
            case .browse:
                BrowseView()
            case .user(let name):
                BrowseView()
            case .room(let name):
                ChatView()
            case .statistics:
                StatisticsView()
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
                .font(.system(size: 48, weight: .light))
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
