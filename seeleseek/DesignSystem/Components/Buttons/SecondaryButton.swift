import SwiftUI
import SeeleseekCore


struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                }
                Text(title)
                    .font(SeeleTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SeeleSpacing.xl)
            .padding(.vertical, SeeleSpacing.md)
            .background(SeeleColors.surfaceSecondary)
            .foregroundStyle(SeeleColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Secondary Button") {
    VStack(spacing: SeeleSpacing.lg) {
        SecondaryButton("Cancel", icon: "xmark") {}
    }
    .padding()
    .background(SeeleColors.background)
}
