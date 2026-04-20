import SwiftUI
import SeeleseekCore

struct NetworkMonitorView: View {
    @State private var selectedTab: MonitorTab = .overview

    enum MonitorTab: String, CaseIterable {
        case overview = "Overview"
        case peers = "Peers"
        case search = "Search"
        case history = "History"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SeeleSpacing.sm) {
                StandardTabBar(selection: $selectedTab)
                Spacer(minLength: 0)
                MonitorLiveStatsBadge()
                    .padding(.trailing, SeeleSpacing.md)
            }
            .background(SeeleColors.surface)

            Divider()
                .background(SeeleColors.surfaceSecondary)

            ScrollView {
                switch selectedTab {
                case .overview:
                    NetworkOverviewTab()
                case .peers:
                    MonitorPeersTab()
                case .search:
                    MonitorSearchTab()
                case .history:
                    MonitorHistoryTab()
                }
            }
            .background(SeeleColors.background)
        }
    }
}

// MARK: - Live Stats Badge (self-observing)

struct MonitorLiveStatsBadge: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.lg) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.success)
                Text(peerPool.currentDownloadSpeed.formattedSpeed)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.success)
                    .contentTransition(.numericText())
            }

            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.up")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.accent)
                Text(peerPool.currentUploadSpeed.formattedSpeed)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.info)
                Text("\(peerPool.activeConnections)")
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.info)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live network stats")
        .accessibilityValue("Download \(peerPool.currentDownloadSpeed.formattedSpeed), upload \(peerPool.currentUploadSpeed.formattedSpeed), \(peerPool.activeConnections) active peers")
    }
}

// MARK: - Peers Tab

struct MonitorPeersTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            MonitorTopologyCard()
            LivePeersView()
        }
        .padding(SeeleSpacing.lg)
    }
}

private struct MonitorTopologyCard: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    var body: some View {
        StandardCard {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                HStack {
                    Text("Network Topology")
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                    Spacer()
                    Text("\(peerPool.activeConnections) active")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .contentTransition(.numericText())
                }

                NetworkTopologyView(
                    connections: Array(peerPool.connections.values),
                    centerUsername: appState.connection.username ?? "You"
                )
                .frame(height: 320)
            }
        }
    }
}

// MARK: - Search Tab

struct MonitorSearchTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            SearchActivityView()
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    NetworkMonitorView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 700)
}
