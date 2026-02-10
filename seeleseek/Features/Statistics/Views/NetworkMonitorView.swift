import SwiftUI
import Combine

struct NetworkMonitorView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: MonitorTab = .overview
    @State private var refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    enum MonitorTab: String, CaseIterable {
        case overview = "Overview"
        case peers = "Peers"
        case search = "Search"
        case transfers = "Transfers"

        var icon: String {
            switch self {
            case .overview: "gauge.with.dots.needle.bottom.50percent"
            case .peers: "person.2"
            case .search: "magnifyingglass"
            case .transfers: "arrow.up.arrow.down"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: SeeleSpacing.sm) {
                ForEach(MonitorTab.allCases, id: \.self) { tab in
                    MonitorTabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
                Spacer()

                MonitorLiveStatsBadge(
                    downloadSpeed: peerPool.currentDownloadSpeed,
                    uploadSpeed: peerPool.currentUploadSpeed,
                    peerCount: peerPool.activeConnections
                )
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.surface)

            Divider()
                .background(SeeleColors.surfaceSecondary)

            // Content
            ScrollView {
                switch selectedTab {
                case .overview:
                    NetworkOverviewTab()
                case .peers:
                    MonitorPeersTab()
                case .search:
                    MonitorSearchTab()
                case .transfers:
                    MonitorTransfersTab()
                }
            }
            .background(SeeleColors.background)
        }
        .onReceive(refreshTimer) { _ in
            // Force refresh
        }
    }
}

// MARK: - Tab Button

struct MonitorTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 1, weight: isSelected ? .semibold : .regular))

                Text(title)
                    .font(SeeleTypography.body)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
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

// MARK: - Live Stats Badge

struct MonitorLiveStatsBadge: View {
    let downloadSpeed: Double
    let uploadSpeed: Double
    let peerCount: Int

    var body: some View {
        HStack(spacing: SeeleSpacing.lg) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.success)
                Text(ByteFormatter.formatSpeed(Int64(downloadSpeed)))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.success)
            }

            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.up")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.accent)
                Text(ByteFormatter.formatSpeed(Int64(uploadSpeed)))
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.accent)
            }

            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.info)
                Text("\(peerCount)")
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.info)
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Peers Tab

struct MonitorPeersTab: View {
    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            PeerWorldMap()
            LivePeersView()
        }
        .padding(SeeleSpacing.lg)
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

// MARK: - Transfers Tab

struct MonitorTransfersTab: View {
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                Text("Active Transfers")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text("No active transfers")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, SeeleSpacing.xl)
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    NetworkMonitorView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 700)
}
