import SwiftUI
import SeeleseekCore

/// Tri-state checkbox for a whole folder group. Its own view so a selection
/// change re-renders the checkbox rather than the header and every row
/// beneath it.
struct SearchGroupSelectionToggle: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup

    private var state: SearchState.GroupSelection {
        appState.searchState.selectionState(of: group)
    }

    var body: some View {
        Button {
            appState.searchState.toggleSelection(of: group)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: SeeleSpacing.iconSize))
                .foregroundStyle(state == .none ? SeeleColors.textTertiary : SeeleColors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select all in \(group.displayName)")
        .accessibilityValue(accessibilityValue)
    }

    private var symbol: String {
        switch state {
        case .none: "circle"
        case .partial: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .none: "none selected"
        case .partial: "some selected"
        case .all: "all selected"
        }
    }
}
