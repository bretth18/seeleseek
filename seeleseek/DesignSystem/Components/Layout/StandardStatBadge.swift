import SwiftUI

/// Consistent stat/metric badge
struct StandardStatBadge: View {
    let label: String
    let value: String
    let icon: String?
    let color: Color

    init(_ label: String, value: String, icon: String? = nil, color: Color = SeeleColors.textSecondary) {
        self.label = label
        self.value = value
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                Text(value)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(color)
            }
        }
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.lg) {
        StandardStatBadge("Downloads", value: "42", icon: "arrow.down", color: SeeleColors.success)
        StandardStatBadge("Uploads", value: "17", icon: "arrow.up", color: SeeleColors.accent)
    }
    .padding()
    .background(SeeleColors.background)
}
