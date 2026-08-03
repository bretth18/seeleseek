import SwiftUI
import SeeleseekCore

/// Consistent horizontal tab bar. One focus stop: arrow keys move the
/// selection, Home/End jump to the ends.
struct StandardTabBar<Tab: Hashable & CaseIterable & RawRepresentable, Trailing: View>: View where Tab.RawValue == String {
    @Binding var selection: Tab
    let tabs: [Tab]
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
        badgeUnit: String = "items",
        showsBackground: Bool = true,
        icon: ((Tab) -> String)? = nil,
        badge: ((Tab) -> Int)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._selection = selection
        self.tabs = tabs
        self.badgeUnit = badgeUnit
        self.showsBackground = showsBackground
        self.icon = icon
        self.badge = badge
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(for: tab)
            }
            Spacer()
            trailing
        }
        // Same outer metrics as StandardActionBar: a view's header slot is
        // the same height whether it leads with tabs or with controls (#67).
        .frame(minHeight: SeeleSpacing.controlHeight)
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.md)
        .background(showsBackground ? SeeleColors.surface.opacity(0.5) : Color.clear)
        .focusable()
        .focused($isFocused)
        // Default ring would wrap the full-width bar; the selected tab draws its own.
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: moveSelection { TabCycler.clampedPrevious($0, count: $1) }
            case .right: moveSelection { TabCycler.clampedNext($0, count: $1) }
            default: break
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

    private func moveSelection(_ step: (Int, Int) -> Int) {
        guard let index = tabs.firstIndex(of: selection) else { return }
        let target = tabs[step(index, tabs.count)]
        if target != selection {
            select(target)
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
            HStack(spacing: SeeleSpacing.xs) {
                // Selection is shown by color/background only. Weight
                // changes alter glyph width, so every tab to the right
                // shifts on each selection change.
                if let iconName = icon?(tab) {
                    Image(systemName: iconName)
                        .font(.system(size: SeeleSpacing.iconSizeSmall - 1))
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
            .overlay {
                if isSelected && isFocused {
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                        .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                }
            }
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
        badgeUnit: String = "items",
        showsBackground: Bool = true,
        icon: ((Tab) -> String)? = nil,
        badge: ((Tab) -> Int)? = nil
    ) {
        self.init(
            selection: selection,
            tabs: tabs,
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
