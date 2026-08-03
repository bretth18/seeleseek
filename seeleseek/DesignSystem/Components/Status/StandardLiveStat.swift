import SwiftUI
import SeeleseekCore

/// Quiet icon + mono value pair for header/footer status clusters.
/// Only the icon carries color (down = info, up = success, counts
/// neutral); the value always reads in the standard text color.
struct StandardLiveStat: View {
    let icon: String
    let value: String
    var iconColor: Color = SeeleColors.textSecondary
    /// Spoken description; the bare value is meaningless without one.
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(SeeleTypography.mono)
                .foregroundStyle(SeeleColors.textSecondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.lg) {
        StandardLiveStat(
            icon: "arrow.down",
            value: "1.2 MB/s",
            iconColor: SeeleColors.info,
            accessibilityLabel: "Download speed 1.2 MB/s"
        )
        StandardLiveStat(
            icon: "person.2.fill",
            value: "14",
            accessibilityLabel: "14 active peers"
        )
    }
    .padding()
    .background(SeeleColors.background)
}
