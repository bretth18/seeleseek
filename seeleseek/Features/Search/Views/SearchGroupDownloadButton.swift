import SwiftUI
import SeeleseekCore

/// Download-whole-folder action for a group header.
///
/// Routes through the same `downloadContainingFolder` path a single row
/// uses, so the group inherits the existing request tracking — spinner
/// while fetching, warning triangle on failure, re-entrancy guard — rather
/// than growing a parallel mechanism.
///
/// Drawn with the same `RowIconButton(isProminent:)` as a row's primary
/// action so the two line up and read alike. In particular the idle glyph is
/// the *outlined* `arrow.down.circle` in `textSecondary`: rows reserve the
/// filled accent variant for a download that is already running, so an
/// accent-filled header button reads as "in progress" when it is not.
struct SearchGroupDownloadButton: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup
    var isHovered: Bool = false

    /// Any member identifies the folder; the request keys on username+folder.
    private var representative: SearchResult? { group.results.first }

    private var requestState: AppState.FolderRequestState? {
        representative.flatMap { appState.folderRequestState(for: $0) }
    }

    var body: some View {
        if let requestState, let representative {
            FolderRequestIndicator(state: requestState, username: representative.username)
        } else {
            RowIconButton(
                systemName: "arrow.down.circle",
                help: "Download all \(group.fileCount) files in this folder",
                tint: isHovered ? SeeleColors.accent : SeeleColors.textSecondary,
                weight: .semibold,
                isProminent: true,
                action: download
            )
            .accessibilityLabel("Download folder \(group.displayName), \(group.fileCount) files")
        }
    }

    private func download() {
        guard let representative else { return }
        Task { await appState.downloadContainingFolder(of: representative) }
    }
}
