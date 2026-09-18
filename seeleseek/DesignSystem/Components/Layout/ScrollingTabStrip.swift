import SwiftUI

/// Horizontal strip of closable tabs. Left/right arrows and Home/End
/// move the selection while the strip has focus; a selection change
/// scrolls the tab into view.
struct ScrollingTabStrip<Item: Identifiable, Tab: View>: View {
    let items: [Item]
    let selectedIndex: Int
    var spacing: CGFloat = SeeleSpacing.xs
    var horizontalPadding: CGFloat = SeeleSpacing.lg
    let isFocused: FocusState<Bool>.Binding
    let select: (Int) -> Void
    @ViewBuilder let tab: (Int, Item) -> Tab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tab(index, item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, SeeleSpacing.sm)
            }
            .background(SeeleColors.surface.opacity(0.3))
            .focusable()
            .focused(isFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: select(TabCycler.clampedPrevious(selectedIndex, count: items.count))
                case .right: select(TabCycler.clampedNext(selectedIndex, count: items.count))
                default: break
                }
            }
            .onKeyPress(.home) {
                guard !items.isEmpty, selectedIndex != 0 else { return .ignored }
                select(0)
                return .handled
            }
            .onKeyPress(.end) {
                guard !items.isEmpty, selectedIndex != items.count - 1 else { return .ignored }
                select(items.count - 1)
                return .handled
            }
            .onChange(of: selectedIndex) { _, index in
                guard items.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(items[index].id)
                }
            }
        }
    }
}
