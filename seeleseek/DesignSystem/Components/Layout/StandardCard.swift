import SwiftUI

/// Consistent card container for grouped content
struct StandardCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusLG, style: .continuous))
    }
}

#Preview {
    StandardCard {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Card Title")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            Text("Card content goes here")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }
    .padding()
    .background(SeeleColors.background)
}
