import SwiftUI

/// One entry in the chat sidebar: leading glyph, title over subtitle,
/// unread badge. The context menu and its VoiceOver mirror come from the
/// caller.
struct ChatSidebarRow<Leading: View, Menu: View, Actions: View>: View {
    let isSelected: Bool
    let title: String
    let subtitle: String
    let unreadCount: Int
    let accessibilityLabel: String
    let select: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let menu: () -> Menu
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Button(action: select) {
            HStack(spacing: SeeleSpacing.sm) {
                leading()
                    .frame(width: SeeleSpacing.xl)

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(title)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textPrimary)

                    Text(subtitle)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Spacer()

                UnreadCountBadge(count: unreadCount)
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.surfaceSecondary : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityActions { actions() }
    }
}
