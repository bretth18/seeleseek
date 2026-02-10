import SwiftUI

struct SpeedGaugeView: View {
    let title: String
    let currentSpeed: Double
    let maxSpeed: Double
    let color: Color

    private var percentage: Double {
        min(currentSpeed / maxSpeed, 1.0)
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.xs) {
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(SeeleColors.surfaceSecondary, lineWidth: 8)
                    .rotationEffect(.degrees(135))

                // Progress arc
                Circle()
                    .trim(from: 0, to: percentage * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.5), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .animation(.easeInOut(duration: 0.3), value: percentage)

                // Speed text
                VStack(spacing: 0) {
                    Text(ByteFormatter.formatSpeed(Int64(currentSpeed)))
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                }
            }
            .frame(width: 100, height: 100)

            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
}
