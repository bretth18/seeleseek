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

            Section("Chat") {
                SidebarRow(item: .chat)
                // Dynamic rooms would go here
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
                .font(SeeleTypography.headline)
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

    var body: some View {
        Label(item.title, systemImage: item.icon)
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
