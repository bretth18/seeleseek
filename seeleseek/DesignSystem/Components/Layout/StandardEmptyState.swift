import SwiftUI
import SeeleseekCore

/// Apple HIG-aligned empty state view
/// Use for empty lists, no results, and placeholder content
struct StandardEmptyState<Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    var actionTitle: String?
    /// Extra content below the text/action, for example a recent-items
    /// list. Rendered inside the centered column so hosts don't hand-roll
    /// the whole empty state just to append rows.
    let footer: Footer

    init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder footer: () -> Footer
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.footer = footer()
    }

    @State private var appeared = false

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)
                .scaleEffect(appeared ? 1.0 : 0.8)
                .opacity(appeared ? 1.0 : 0.0)
                .accessibilityHidden(true)

            VStack(spacing: SeeleSpacing.sm) {
                Text(title)
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 6)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(SeeleColors.accent)
            }

            footer
                .opacity(appeared ? 1.0 : 0.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: SeeleSpacing.animationSlow)) {
                appeared = true
            }
        }
    }
}

extension StandardEmptyState where Footer == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actionTitle: actionTitle,
            action: action,
            footer: { EmptyView() }
        )
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
