import SwiftUI

// MARK: - Standard Empty State

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

// MARK: - Standard Section Header

/// Consistent section header for lists and content areas
struct StandardSectionHeader: View {
    let title: String
    var count: Int?
    var trailing: AnyView?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let count {
                Text("(\(count))")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
    }
}

// MARK: - Standard Card

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

// MARK: - Standard Toolbar

/// Consistent toolbar for view headers
struct StandardToolbar<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder center: () -> Center = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            leading
            Spacer()
            center
            Spacer()
            trailing
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface.opacity(0.5))
    }
}

// MARK: - Standard Tab Bar

/// Consistent horizontal tab bar
struct StandardTabBar<Tab: Hashable & CaseIterable & RawRepresentable>: View where Tab.RawValue == String {
    @Binding var selection: Tab
    let tabs: [Tab]
    var badge: ((Tab) -> Int)?

    init(selection: Binding<Tab>, tabs: [Tab] = Array(Tab.allCases), badge: ((Tab) -> Int)? = nil) {
        self._selection = selection
        self.tabs = tabs
        self.badge = badge
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(SeeleColors.surface)
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selection == tab
        let badgeCount = badge?(tab) ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = tab
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Text(tab.rawValue)
                    .font(SeeleTypography.body)
                    .fontWeight(isSelected ? .medium : .regular)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(SeeleTypography.badgeText)
                        .foregroundStyle(isSelected ? SeeleColors.textOnAccent : SeeleColors.textSecondary)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(
                            isSelected ? SeeleColors.accent : SeeleColors.surfaceElevated,
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standard Search Field

/// Consistent search field component
struct StandardSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(SeeleColors.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

// MARK: - Standard List Row

/// Consistent list row with hover support
struct StandardListRow<Content: View>: View {
    let content: Content
    @State private var isHovered = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.md)
            .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Standard Stat Badge

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

// MARK: - Standard Progress Indicator

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

// MARK: - Standard Status Dot

/// Consistent status indicator dot
struct StandardStatusDot: View {
    let status: BuddyStatus
    var size: CGFloat = SeeleSpacing.statusDot

    private var statusColor: Color {
        switch status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.textTertiary
        }
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
    }
}

// MARK: - Standard Metadata Badge

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

// MARK: - Previews

#Preview("Empty State") {
    StandardEmptyState(
        icon: "music.note.list",
        title: "No Results",
        subtitle: "Try a different search term",
        actionTitle: "Clear Search"
    ) {}
    .background(SeeleColors.background)
}

#Preview("Tab Bar") {
    enum PreviewTab: String, Hashable, CaseIterable {
        case downloads = "Downloads"
        case uploads = "Uploads"
        case history = "History"
    }

    struct Preview: View {
        @State var selection: PreviewTab = .downloads

        var body: some View {
            VStack {
                StandardTabBar(selection: $selection) { tab in
                    switch tab {
                    case .downloads: return 3
                    case .uploads: return 0
                    case .history: return 5
                    }
                }
                Spacer()
            }
            .background(SeeleColors.background)
        }
    }

    return Preview()
}

#Preview("Components") {
    VStack(spacing: SeeleSpacing.lg) {
        StandardSearchField(text: .constant(""), placeholder: "Search files...")

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

        HStack(spacing: SeeleSpacing.lg) {
            StandardStatBadge("Downloads", value: "42", icon: "arrow.down", color: SeeleColors.success)
            StandardStatBadge("Uploads", value: "17", icon: "arrow.up", color: SeeleColors.accent)
        }

        HStack(spacing: SeeleSpacing.sm) {
            StandardMetadataBadge("320 kbps", color: SeeleColors.success)
            StandardMetadataBadge("4:32", color: SeeleColors.textTertiary)
            StandardMetadataBadge("8.5 MB", color: SeeleColors.textTertiary)
        }

        StandardProgressBar(progress: 0.65)
            .frame(width: 200)
    }
    .padding()
    .background(SeeleColors.background)
}
