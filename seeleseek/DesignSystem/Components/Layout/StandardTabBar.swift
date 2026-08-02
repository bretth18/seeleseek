import SwiftUI
import SeeleseekCore

/// Consistent horizontal tab bar.
///
/// The bar is a single Tab stop, like a native segmented control: focus it
/// with Tab, then Left/Right arrows move the selection (Home/End jump to the
/// first/last tab). Selection follows the keyboard directly — switching tabs
/// is cheap and non-destructive, so there is no separate activation step.
struct StandardTabBar<Tab: Hashable & CaseIterable & RawRepresentable>: View where Tab.RawValue == String {
    @Binding var selection: Tab
    let tabs: [Tab]
    var badge: ((Tab) -> Int)?
    /// Spoken unit for the badge count, for example "unread".
    /// Without a unit, VoiceOver reads the badge as a bare number.
    var badgeUnit: String
    /// Optional SF Symbol shown before each tab's title.
    var icon: ((Tab) -> String)?
    /// The bar draws its own surface background unless the host already
    /// supplies one (for example a header it is embedded in).
    var showsBackground: Bool

    @FocusState private var isFocused: Bool

    init(
        selection: Binding<Tab>,
        tabs: [Tab] = Array(Tab.allCases),
        badgeUnit: String = "items",
        showsBackground: Bool = true,
        icon: ((Tab) -> String)? = nil,
        badge: ((Tab) -> Int)? = nil
    ) {
        self._selection = selection
        self.tabs = tabs
        self.badgeUnit = badgeUnit
        self.showsBackground = showsBackground
        self.icon = icon
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
        .background(showsBackground ? SeeleColors.surface : Color.clear)
        .focusable()
        .focused($isFocused)
        // The default ring would wrap the full-width bar; a ring on the
        // selected tab (drawn in tabButton) marks focus instead.
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
                if let iconName = icon?(tab) {
                    Image(systemName: iconName)
                        .font(.system(size: SeeleSpacing.iconSizeSmall - 1, weight: isSelected ? .semibold : .regular))
                }

                Text(tab.rawValue)
                    .font(SeeleTypography.body)
                    .fontWeight(isSelected ? .medium : .regular)

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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) \(badgeUnit)" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
