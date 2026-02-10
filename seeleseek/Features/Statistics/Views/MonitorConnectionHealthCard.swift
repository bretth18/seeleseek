import SwiftUI

struct MonitorConnectionHealthCard: View {
    @Environment(\.appState) private var appState

    private var peerPool: PeerConnectionPool {
        appState.networkClient.peerConnectionPool
    }

    private var healthScore: Double {
        let active = Double(peerPool.activeConnections)
        let total = Double(max(peerPool.totalConnections, 1))
        return min(active / total, 1.0) * 100
    }

    private var healthColor: Color {
        if healthScore >= 70 {
            return SeeleColors.success
        } else if healthScore >= 40 {
            return SeeleColors.warning
        } else {
            return SeeleColors.error
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Connection Health")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            HStack(spacing: SeeleSpacing.xl) {
                // Health gauge
                ZStack {
                    Circle()
                        .stroke(SeeleColors.surfaceSecondary, lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: healthScore / 100)
                        .stroke(healthColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: healthScore)

                    VStack {
                        Text(String(format: "%.0f%%", healthScore))
                            .font(SeeleTypography.title2)
                            .foregroundStyle(SeeleColors.textPrimary)
                    }
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    HealthStatRow(
                        label: "Active",
                        value: "\(peerPool.activeConnections)",
                        color: SeeleColors.success
                    )
                    HealthStatRow(
                        label: "Total",
                        value: "\(peerPool.totalConnections)",
                        color: SeeleColors.textSecondary
                    )
                    HealthStatRow(
                        label: "Avg Duration",
                        value: formatDuration(peerPool.averageConnectionDuration),
                        color: SeeleColors.info
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}

struct HealthStatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Spacer()
            Text(value)
                .font(SeeleTypography.mono)
                .foregroundStyle(color)
        }
    }
}
