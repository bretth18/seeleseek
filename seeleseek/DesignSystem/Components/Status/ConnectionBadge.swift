import SwiftUI

enum ConnectionStatus: String, CaseIterable {
    case disconnected
    case connecting
    case connected
    case error

    var color: Color {
        switch self {
        case .disconnected: SeeleColors.textTertiary
        case .connecting: SeeleColors.warning
        case .connected: SeeleColors.success
        case .error: SeeleColors.error
        }
    }

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .error: "Error"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: "circle.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

struct ConnectionBadge: View {
    let status: ConnectionStatus
    let showLabel: Bool

    init(status: ConnectionStatus, showLabel: Bool = true) {
        self.status = status
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            statusIndicator
            if showLabel {
                Text(status.label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.horizontal, showLabel ? SeeleSpacing.sm : SeeleSpacing.xs)
        .padding(.vertical, SeeleSpacing.xs)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if status == .connecting {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.4)
                .tint(status.color)
                .frame(width: SeeleSpacing.iconSizeSmall - 2, height: SeeleSpacing.iconSizeSmall - 2)
        } else {
            Image(systemName: status.icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall - 2, weight: .medium))
                .foregroundStyle(status.color)
        }
    }
}

struct SpeedBadge: View {
    let bytesPerSecond: Int64
    let direction: Direction

    enum Direction {
        case download
        case upload

        var icon: String {
            switch self {
            case .download: "arrow.down"
            case .upload: "arrow.up"
            }
        }

        var color: Color {
            switch self {
            case .download: SeeleColors.info
            case .upload: SeeleColors.success
            }
        }
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.xxs) {
            Image(systemName: direction.icon)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
            Text(formatSpeed(bytesPerSecond))
                .font(SeeleTypography.monoSmall)
        }
        .foregroundStyle(direction.color)
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.xxs)
        .background(direction.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }
}

struct ProgressIndicator: View {
    let progress: Double
    let showPercentage: Bool

    init(progress: Double, showPercentage: Bool = false) {
        self.progress = progress
        self.showPercentage = showPercentage
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                        .fill(SeeleColors.surfaceSecondary)
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                        .fill(SeeleColors.accent)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: SeeleSpacing.progressBarHeight)

            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

#Preview("Status Components") {
    VStack(spacing: SeeleSpacing.lg) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionBadge(status: status)
        }

        Divider()

        SpeedBadge(bytesPerSecond: 1_500_000, direction: .download)
        SpeedBadge(bytesPerSecond: 256_000, direction: .upload)

        Divider()

        ProgressIndicator(progress: 0.65, showPercentage: true)
        ProgressIndicator(progress: 0.3)
    }
    .padding()
    .background(SeeleColors.background)
}
