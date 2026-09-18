import SwiftUI

/// Icon + mono caption in one tint. The icon is decorative; the text
/// carries the spoken meaning.
struct RowStatusLabel: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .accessibilityHidden(true)
            Text(text)
                .font(SeeleTypography.monoSmall)
        }
        .foregroundStyle(tint)
        .lineLimit(1)
    }
}
