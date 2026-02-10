import SwiftUI

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
            Text(ByteFormatter.formatSpeed(bytesPerSecond))
                .font(SeeleTypography.monoSmall)
        }
        .foregroundStyle(direction.color)
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.xxs)
        .background(direction.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.md) {
        SpeedBadge(bytesPerSecond: 1_500_000, direction: .download)
        SpeedBadge(bytesPerSecond: 256_000, direction: .upload)
    }
    .padding()
    .background(SeeleColors.background)
}
