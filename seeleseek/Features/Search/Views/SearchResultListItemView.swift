import SwiftUI
import SeeleseekCore

/// Renders exactly one `SearchListItem`. Every branch must emit a single
/// view — see `SearchListItem` for why a variable subview count is unsound
/// inside the results list.
struct SearchResultListItemView: View {
    @Environment(\.appState) private var appState

    let item: SearchListItem

    private var searchState: SearchState { appState.searchState }

    var body: some View {
        switch item {
        case .loose(let result):
            row(result, nested: false)

        case .header(let group):
            SearchResultGroupHeader(group: group)

        case .child(let result):
            row(result, nested: true)
                // Membership rail. An overlay, not leading padding: the row's
                // column anchors must not move.
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(SeeleColors.warning.opacity(0.55))
                        .frame(width: SeeleSpacing.strokeMedium)
                        .accessibilityHidden(true)
                }

        case .groupEnd:
            Divider()
                .background(SeeleColors.surfaceSecondary)
                .accessibilityHidden(true)
        }
    }

    private func row(_ result: SearchResult, nested: Bool) -> some View {
        SearchResultRow(
            result: result,
            isNestedInGroup: nested,
            isSelectionMode: searchState.isSelectionMode,
            isSelected: searchState.selectedResults.contains(result.id)
        )
    }
}
