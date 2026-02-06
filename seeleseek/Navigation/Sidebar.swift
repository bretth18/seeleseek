import SwiftUI

struct Sidebar: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo and connection header
            connectionHeader
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.top, SeeleSpacing.md)
                .padding(.bottom, SeeleSpacing.sm)

//            Divider()
//                .background(SeeleColors.divider)

            // Navigation sections
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                sidebarSection("Navigation") {
                    SidebarRow(item: .search)
                    SidebarRow(item: .transfers)
                    SidebarRow(item: .browse)
                }

                sidebarSection("Social") {
                    SidebarRow(item: .social)
                    SidebarRow(item: .chat)
                }

                sidebarSection("Monitor") {
                    SidebarRow(item: .statistics)
                    SidebarRow(item: .networkMonitor)
                }

                Spacer()

                SidebarRow(item: .settings)
                    .padding(.horizontal, SeeleSpacing.sm)
            }
            .padding(.vertical, SeeleSpacing.sm)
        }
        .background(SeeleColors.surface)
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        #endif
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .padding(.horizontal, SeeleSpacing.md)

            VStack(spacing: SeeleSpacing.xxs) {
                content()
            }
            .padding(.horizontal, SeeleSpacing.sm)
        }
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            
            HStack(spacing:
                    SeeleSpacing.xs) {
                Image(nsImage: .gsgaag2)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(SeeleColors.accent)
                Text("seeleseek")
                    .font(SeeleTypography.logo)
                    .foregroundStyle(SeeleColors.textPrimary)
            }

            HStack(spacing: SeeleSpacing.xs) {
                Circle()
                    .fill(appState.connection.connectionStatus.color.opacity(0.8))
                    .frame(width: 8, height: 8)

                if appState.connection.connectionStatus == .connected,
                   let username = appState.connection.username {
                    Text(username)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textPrimary.opacity(0.8))
                } else {
                    Text(appState.connection.connectionStatus.label)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
        }
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    @Environment(\.appState) private var appState

    private var isSelected: Bool {
        appState.sidebarSelection == item
    }

    private var badgeCount: Int {
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
        Button {
            appState.sidebarSelection = item
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .medium))
                    .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textSecondary)
                    .frame(width: 18)

                Text(item.title)
                    .font(SeeleTypography.body)
                    .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)

                Spacer()

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(SeeleTypography.badgeText)
                        .foregroundStyle(item == .chat ? SeeleColors.textOnAccent : SeeleColors.textSecondary)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(
                            item == .chat ? SeeleColors.accent : SeeleColors.surfaceElevated,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.rowVertical)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
