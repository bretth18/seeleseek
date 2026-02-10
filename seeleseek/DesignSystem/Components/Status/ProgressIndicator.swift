import SwiftUI

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

#Preview {
    VStack(spacing: SeeleSpacing.md) {
        ProgressIndicator(progress: 0.65, showPercentage: true)
        ProgressIndicator(progress: 0.3)
    }
    .padding()
    .background(SeeleColors.background)
}
