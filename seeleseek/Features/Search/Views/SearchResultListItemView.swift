import SwiftUI
import SeeleseekCore

/// Renders exactly one `SearchListItem`.
///
/// "Exactly one" is the point: this sits inside a `ForEach` in a
/// `LazyVStack`, and emitting a variable number of subviews per element is
/// what corrupted grouped rendering as results streamed in. Every branch
/// below produces a single view.
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

        case .child(let result, _):
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
            isSelected: searchState.selectedResults.contains(result.id),
            onToggleSelection: { searchState.toggleSelection(result.id) }
        )
    }
}
