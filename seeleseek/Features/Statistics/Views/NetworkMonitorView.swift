import SwiftUI
import SeeleseekCore

struct NetworkMonitorView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 0) {
            StandardTabBar(selection: Bindable(appState.navigation).monitorTab, icon: { $0.icon }) {
                MonitorLiveStatsBadge()
            }

            Divider()
                .background(SeeleColors.surfaceSecondary)

            ScrollView {
                switch appState.navigation.monitorTab {
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
        .focusedSceneValue(\.tabCommands, .cycling(Bindable(appState.navigation).monitorTab))
    }
}

// MARK: - Live Stats Badge (self-observing)

struct MonitorLiveStatsBadge: View {
    @Environment(\.appState) private var appState

    private var monitor: NetworkMonitorState {
        appState.networkClient.monitor
    }

    var body: some View {
        StandardStatCluster {
            StandardLiveStat(
                icon: "arrow.down",
                value: Int64(monitor.currentDownloadSpeed).formattedSpeed,
                iconColor: SeeleColors.info,
                accessibilityLabel: "Download speed \(monitor.currentDownloadSpeed.formattedSpeed)"
            )
            StandardLiveStat(
                icon: "arrow.up",
                value: Int64(monitor.currentUploadSpeed).formattedSpeed,
                iconColor: SeeleColors.success,
                accessibilityLabel: "Upload speed \(monitor.currentUploadSpeed.formattedSpeed)"
            )
            StandardLiveStat(
                icon: "person.2.fill",
                value: "\(monitor.activeConnections)",
                accessibilityLabel: "\(monitor.activeConnections) active peers"
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live network stats")
        .accessibilityValue("Download \(monitor.currentDownloadSpeed.formattedSpeed), upload \(monitor.currentUploadSpeed.formattedSpeed), \(monitor.activeConnections) active peers")
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

    private var monitor: NetworkMonitorState {
        appState.networkClient.monitor
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
                    Text("\(monitor.activeConnections) active")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .contentTransition(.numericText())
                }

                NetworkTopologyView(
                    connections: Array(monitor.connections.values),
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
