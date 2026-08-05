import SwiftUI
import SeeleseekCore

/// One folder group: header plus, when expanded, its files.
///
/// Rows are rendered full width and un-indented on purpose. `SearchResultRow`
/// is built around fixed column anchors (`RowLayout.peerCellWidth` and
/// friends) so every field lands at the same X on every row; indenting under
/// a header would break all of them.
struct SearchResultGroupSection: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup

    private var searchState: SearchState { appState.searchState }

    var body: some View {
        // A lone result keeps the pre-grouping appearance — no header, no
        // chrome, just the row.
        if group.isSingleFile, let only = group.results.first {
            SearchResultRow(
                result: only,
                isSelectionMode: searchState.isSelectionMode,
                isSelected: searchState.selectedResults.contains(only.id),
                onToggleSelection: { searchState.toggleSelection(only.id) }
            )
        } else {
            let isExpanded = searchState.isExpanded(group)

            SearchResultGroupHeader(
                group: group,
                isExpanded: isExpanded,
                onToggleExpansion: { searchState.toggleExpansion(group) }
            )

            if isExpanded {
                ForEach(group.results) { result in
                    SearchResultRow(
                        result: result,
                        isNestedInGroup: true,
                        isSelectionMode: searchState.isSelectionMode,
                        isSelected: searchState.selectedResults.contains(result.id),
                        onToggleSelection: { searchState.toggleSelection(result.id) }
                    )
                    // Membership rail. An overlay, not leading padding: the
                    // row's column anchors must not move, and without some
                    // containment cue an expanded folder is indistinguishable
                    // from the loose rows around it.
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(SeeleColors.warning.opacity(0.55))
                            .frame(width: SeeleSpacing.strokeMedium)
                            .accessibilityHidden(true)
                    }
                }

                // Closes the group so the next folder does not read as a
                // continuation of this one. Same divider treatment the rest
                // of the app uses between sections.
                Divider()
                    .background(SeeleColors.surfaceSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
