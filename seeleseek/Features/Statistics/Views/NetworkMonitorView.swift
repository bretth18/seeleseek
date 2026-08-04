import SwiftUI
import SeeleseekCore

struct NetworkMonitorView: View {
    @State private var selectedTab: MonitorTab = .overview

    enum MonitorTab: String, CaseIterable {
        case overview = "Overview"
        case peers = "Peers"
        case search = "Search"
        case history = "History"
        
        var icon: String {
            switch self {
            case .overview: "waveform.path.ecg"
            case .peers: "person.line.dotted.person"
            case .search: "magnifyingglass"
            case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardTabBar(selection: $selectedTab, icon: { $0.icon } ) {
                MonitorLiveStatsBadge()
            }

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
        }
        .background(SeeleColors.background)
        .focusedSceneValue(\.tabCommands, .cycling($selectedTab))
    }
}

// MARK: - Live Stats Badge (self-observing)

struct MonitorLiveStatsBadge: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    var body: some View {
        StandardStatCluster {
            StandardLiveStat(
                icon: "arrow.down",
                value: Int64(peerPool.currentDownloadSpeed).formattedSpeed,
                iconColor: SeeleColors.info,
                accessibilityLabel: "Download speed \(peerPool.currentDownloadSpeed.formattedSpeed)"
            )
            StandardLiveStat(
                icon: "arrow.up",
                value: Int64(peerPool.currentUploadSpeed).formattedSpeed,
                iconColor: SeeleColors.success,
                accessibilityLabel: "Upload speed \(peerPool.currentUploadSpeed.formattedSpeed)"
            )
            StandardLiveStat(
                icon: "person.2.fill",
                value: "\(peerPool.activeConnections)",
                accessibilityLabel: "\(peerPool.activeConnections) active peers"
            )
        }
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
                        .accessibilityAddTraits(.isHeader)
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
