import SwiftUI
import SeeleseekCore

/// Tri-state checkbox for a whole folder group. Its own view so a selection
/// change re-renders the checkbox rather than the header and every row
/// beneath it.
struct SearchGroupSelectionToggle: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup

    var body: some View {
        // Read once: `selectionState(of:)` scans the group's results against
        // the selection set, and this was previously evaluated three times
        // per render (tint, symbol, spoken value).
        let state = appState.searchState.selectionState(of: group)

        Button {
            appState.searchState.toggleSelection(of: group)
        } label: {
            Image(systemName: Self.symbol(for: state))
                .font(.system(size: SeeleSpacing.iconSize))
                .foregroundStyle(state == .none ? SeeleColors.textTertiary : SeeleColors.accent)
                // Same hit target as `SearchResultRow`'s checkbox, or the
                // header's glyph and title stop lining up with its rows the
                // moment selection mode is on.
                .frame(width: RowGlyph.size, height: RowGlyph.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select all in \(group.displayName)")
        .accessibilityValue(Self.spokenValue(for: state))
    }

    private static func symbol(for state: SearchState.GroupSelection) -> String {
        switch state {
        case .none: "circle"
        case .partial: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
        }
    }

    private static func spokenValue(for state: SearchState.GroupSelection) -> String {
        switch state {
        case .none: "none selected"
        case .partial: "some selected"
        case .all: "all selected"
        }
    }
}
