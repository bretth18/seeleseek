import SwiftUI

/// Apple HIG-aligned empty state view
/// Use for empty lists, no results, and placeholder content
struct StandardEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    var actionTitle: String?

    init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            VStack(spacing: SeeleSpacing.sm) {
                Text(title)
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(subtitle)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(SeeleColors.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StandardEmptyState(
        icon: "music.note.list",
        title: "No Results",
        subtitle: "Try a different search term",
        actionTitle: "Clear Search"
    ) {}
    .background(SeeleColors.background)
}
