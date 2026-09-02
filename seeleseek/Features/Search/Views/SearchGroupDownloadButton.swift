import SwiftUI
import SeeleseekCore

/// Download-whole-folder action for a group header.
///
/// Routes through `downloadContainingFolder`, so the group inherits the
/// existing request tracking rather than growing a parallel mechanism.
///
/// The idle glyph must stay the *outlined* `arrow.down.circle` in
/// `textSecondary`: rows reserve the filled accent variant for a download
/// already running, so an accent-filled header button reads as "in progress".
struct SearchGroupDownloadButton: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup
    @Environment(\.isRowHovered) private var isHovered

    /// Any member identifies the folder; the request keys on username+folder.
    private var representative: SearchResult? { group.results.first }

    private var requestState: AppState.FolderRequestState? {
        representative.flatMap { appState.folderRequestState(for: $0) }
    }

    var body: some View {
        if let requestState, let representative {
            FolderRequestIndicator(state: requestState, username: representative.username)
        } else {
            // No file count in the wording: `downloadContainingFolder`
            // queues everything the peer's folder holds, which can be more
            // than this group shows.
            RowIconButton(
                systemName: "arrow.down.circle",
                help: "Download the entire folder from \(group.username)",
                tint: isHovered ? SeeleColors.accent : SeeleColors.textSecondary,
                weight: .semibold,
                isProminent: true,
                action: download
            )
            .accessibilityLabel("Download entire folder \(group.displayName)")
        }
    }

    private func download() {
        guard let representative else { return }
        Task { await appState.downloadContainingFolder(of: representative) }
    }
}
