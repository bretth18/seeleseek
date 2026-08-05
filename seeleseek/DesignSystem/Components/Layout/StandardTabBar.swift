import SwiftUI
import SeeleseekCore

/// Consistent tab bar. One focus stop: arrow keys move the selection along
/// the bar's axis, Home/End jump to the ends.
///
/// `.horizontal` is a compact chip strip above content. `.vertical` is a
/// full-width sidebar list — the presentation differences (fixed icon
/// column, accent-tinted icon, rows filling the width) follow from the axis
/// rather than being separate knobs.
struct StandardTabBar<Tab: Hashable & CaseIterable & RawRepresentable, Trailing: View>: View where Tab.RawValue == String {
    @Binding var selection: Tab
    let tabs: [Tab]
    var axis: Axis
    var badge: ((Tab) -> Int)?
    /// Spoken unit for the badge count, for example "unread".
    /// Without a unit, VoiceOver reads the badge as a bare number.
    var badgeUnit: String
    var icon: ((Tab) -> String)?
    /// Set false when the host supplies its own background.
    var showsBackground: Bool
    /// Status or actions anchored at the bar's trailing edge. In-layout —
    /// never an `.overlay`, which sits on top of the tabs at narrow widths.
    let trailing: Trailing

    @FocusState private var isFocused: Bool

    init(
        selection: Binding<Tab>,
        tabs: [Tab] = Array(Tab.allCases),
        axis: Axis = .horizontal,
        badgeUnit: String = "items",
        showsBackground: Bool = true,
        icon: ((Tab) -> String)? = nil,
        badge: ((Tab) -> Int)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._selection = selection
        self.tabs = tabs
        self.axis = axis
        self.badgeUnit = badgeUnit
        self.showsBackground = showsBackground
        self.icon = icon
        self.badge = badge
        self.trailing = trailing()
    }

    var body: some View {
        stack
            .background(showsBackground ? SeeleColors.surface.opacity(0.5) : Color.clear)
            .focusable()
            .focused($isFocused)
            // Default ring would wrap the full-width bar; the selected tab draws its own.
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch (axis, direction) {
                case (.horizontal, .left), (.vertical, .up):
                    moveSelection { TabCycler.clampedPrevious($0, count: $1) }
                case (.horizontal, .right), (.vertical, .down):
                    moveSelection { TabCycler.clampedNext($0, count: $1) }
                default:
                    break
                }
            }
            .onKeyPress(.home) {
                guard let first = tabs.first, selection != first else { return .ignored }
                select(first)
                return .handled
            }
            .onKeyPress(.end) {
                guard let last = tabs.last, selection != last else { return .ignored }
                select(last)
                return .handled
            }
    }

    @ViewBuilder
    private var stack: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: SeeleSpacing.sm) {
                ForEach(tabs, id: \.self) { tabButton(for: $0) }
                Spacer()
                trailing
            }
            // Same outer metrics as StandardActionBar: a view's header slot
            // is the same height whether it leads with tabs or controls (#67).
            .frame(minHeight: SeeleSpacing.controlHeight)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.md)
        case .vertical:
            VStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tabButton(for: $0) }
                Spacer()
                trailing
            }
            .padding(.horizontal, SeeleSpacing.xs)
        }
    }

    private func moveSelection(_ step: (Int, Int) -> Int) {
        guard let index = tabs.firstIndex(of: selection) else { return }
        let target = tabs[step(index, tabs.count)]
        if target != selection {
            select(target)
        }
    }

    /// The sidebar tints the glyph itself so the icon column reads as the
    /// selection indicator. The compact bar tints the row uniformly, so this
    /// returns exactly what the container applies and nothing changes there.
    private func iconTint(isSelected: Bool) -> Color {
        switch axis {
        case .vertical:
            isSelected ? SeeleColors.accent : SeeleColors.textTertiary
        case .horizontal:
            isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary
        }
    }

    private func select(_ tab: Tab) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selection = tab
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = selection == tab
        let badgeCount = badge?(tab) ?? 0

        return Button {
            select(tab)
        } label: {
            HStack(spacing: axis == .vertical ? SeeleSpacing.sm : SeeleSpacing.xs) {
                // Selection is shown by color/background only. Weight
                // changes alter glyph width, so every tab to the right
                // shifts on each selection change.
                if let iconName = icon?(tab) {
                    Image(systemName: iconName)
                        .font(.system(
                            size: axis == .vertical ? SeeleSpacing.iconSizeSmall : SeeleSpacing.iconSizeSmall - 1,
                            weight: axis == .vertical ? .medium : .regular
                        ))
                        // Fixed column so labels align down the sidebar
                        // regardless of glyph width.
                        .frame(width: axis == .vertical ? SeeleSpacing.iconSizeMedium : nil)
                        .foregroundStyle(iconTint(isSelected: isSelected))
                }

                Text(tab.rawValue)
                    .font(SeeleTypography.body)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(SeeleTypography.badgeText)
                        .contentTransition(.numericText())
                        .foregroundStyle(isSelected ? SeeleColors.textOnAccent : SeeleColors.textSecondary)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(
                            isSelected ? SeeleColors.accent : SeeleColors.surfaceElevated,
                            in: Capsule()
                        )
                        .transition(.scale.combined(with: .opacity))
                }

                if axis == .vertical { Spacer(minLength: 0) }
            }
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .leading)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
            )
            .seeleTabFocusRing(isSelected && isFocused)
            .contentShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) \(badgeUnit)" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension StandardTabBar where Trailing == EmptyView {
    init(
        selection: Binding<Tab>,
        tabs: [Tab] = Array(Tab.allCases),
        axis: Axis = .horizontal,
        badgeUnit: String = "items",
        showsBackground: Bool = true,
        icon: ((Tab) -> String)? = nil,
        badge: ((Tab) -> Int)? = nil
    ) {
        self.init(
            selection: selection,
            tabs: tabs,
            axis: axis,
            badgeUnit: badgeUnit,
            showsBackground: showsBackground,
            icon: icon,
            badge: badge,
            trailing: { EmptyView() }
        )
    }
}

#Preview {
    enum PreviewTab: String, Hashable, CaseIterable {
        case downloads = "Downloads"
        case uploads = "Uploads"
        case history = "History"
    }

    struct Preview: View {
        @State var selection: PreviewTab = .downloads

        var body: some View {
            VStack {
                StandardTabBar(selection: $selection, badge: { tab in
                    switch tab {
                    case .downloads: return 3
                    case .uploads: return 0
                    case .history: return 5
                    }
                })
                Spacer()
            }
            .background(SeeleColors.background)
        }
    }

    return Preview()
}
