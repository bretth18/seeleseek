import SwiftUI

/// Consistent progress bar
struct StandardProgressBar: View {
    let progress: Double
    let color: Color

    init(progress: Double, color: Color = SeeleColors.accent) {
        self.progress = progress
        self.color = color
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                    .fill(SeeleColors.surfaceSecondary)

                RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, geometry.size.width * min(progress, 1.0)))
            }
        }
        .frame(height: SeeleSpacing.progressBarHeight)
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.md) {
        StandardProgressBar(progress: 0.65)
        StandardProgressBar(progress: 0.3, color: SeeleColors.success)
        StandardProgressBar(progress: 0.9, color: SeeleColors.warning)
    }
    .frame(width: 200)
    .padding()
    .background(SeeleColors.background)
}
