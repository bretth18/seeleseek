import SwiftUI

struct Sidebar: View {
    @Environment(\.appState) private var appState

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.sidebarSelection) {
            Section {
                connectionHeader
            }

            Section("Navigation") {
                SidebarRow(item: .search)
                SidebarRow(item: .transfers)
                SidebarRow(item: .browse)
            }

            Section("Social") {
                SidebarRow(item: .social)
                SidebarRow(item: .chat)
            }

            Section("Monitor") {
                SidebarRow(item: .statistics)
                SidebarRow(item: .networkMonitor)
            }

            Section {
                SidebarRow(item: .settings)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SeeleColors.surface)
        .navigationTitle("SeeleSeek")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        #endif
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            
            Text("seeleseek")
                .font(SeeleTypography.logo)
                .foregroundStyle(SeeleColors.textPrimary)
            
            HStack {
                ConnectionBadge(status: appState.connection.connectionStatus)
                Spacer()
            }

            if appState.connection.connectionStatus == .connected,
               let username = appState.connection.username {
                Text(username)
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
        .padding(.vertical, SeeleSpacing.xs)
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    @Environment(\.appState) private var appState

    var isSelected: Bool {
        appState.sidebarSelection == item
    }

    /// Badge count for this item (e.g., unread messages for chat)
    var badgeCount: Int {
        switch item {
        case .chat:
            return appState.chatState.totalUnreadCount
        case .social:
            return appState.socialState.onlineBuddies.count
        default:
            return 0
        }
    }

    var body: some View {
        HStack {
            Label(item.title, systemImage: item.icon)
            Spacer()
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item == .chat ? .white : SeeleColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item == .chat ? Color.red : SeeleColors.surfaceSecondary, in: Capsule())
            }
        }
        .tag(item)
        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textPrimary)
    }
}

#Preview {
    NavigationSplitView {
        Sidebar()
    } detail: {
        Text("Detail")
    }
    .environment(\.appState, {
        let state = AppState()
        state.connection.connectionStatus = .connected
        state.connection.username = "testuser"
        return state
    }())
}
