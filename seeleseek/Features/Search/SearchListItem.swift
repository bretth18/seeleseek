import Foundation
import SeeleseekCore

/// One rendered line of the results list, already flattened.
///
/// Grouping used to be expressed by a section view that emitted a *variable*
/// number of subviews — one row when the folder held a single file, header +
/// N rows + divider when expanded. Inside a `LazyVStack`'s `ForEach` that is
/// unsound: the lazy container caches child identity and geometry, and a
/// child whose subview count changes as results stream in produces rows
/// rendered from the wrong branch (children without their header, or header
/// children drawn in the un-nested style). Flattening here means every
/// `ForEach` element emits exactly one view with a stable id.
enum SearchListItem: Identifiable, Hashable {
    /// A folder holding a single file — rendered as a plain row, no chrome.
    case loose(SearchResult)
    case header(SearchResultGroup)
    case child(SearchResult)
    /// Closes an expanded folder so the next one does not read as a
    /// continuation of it.
    case groupEnd(groupID: String)

    var id: String {
        switch self {
        case .loose(let result):
            "loose-\(result.id)"
        case .header(let group):
            "header-\(group.id)"
        case .child(let result):
            "child-\(result.id)"
        case .groupEnd(let groupID):
            "end-\(groupID)"
        }
    }
}
