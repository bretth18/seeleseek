import SwiftUI

/// Consistent metadata badge for file info
struct StandardMetadataBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = SeeleColors.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(color)
            .padding(.horizontal, SeeleSpacing.xs)
            .padding(.vertical, SeeleSpacing.xxs)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusSM, style: .continuous))
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.sm) {
        StandardMetadataBadge("320 kbps", color: SeeleColors.success)
        StandardMetadataBadge("4:32", color: SeeleColors.textTertiary)
        StandardMetadataBadge("8.5 MB", color: SeeleColors.textTertiary)
    }
    .padding()
    .background(SeeleColors.background)
}
