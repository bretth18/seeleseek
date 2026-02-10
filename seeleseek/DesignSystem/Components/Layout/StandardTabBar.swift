import SwiftUI

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
