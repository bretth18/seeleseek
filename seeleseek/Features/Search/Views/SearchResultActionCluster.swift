import SwiftUI
import SeeleseekCore

/// Trailing cluster of a search row: two hover-revealed secondary actions
/// plus the primary download action. Reads transfer status, folder-request
/// state and hover here so they invalidate only this cluster.
struct SearchResultActionCluster: View {
    @Environment(\.appState) private var appState
    @Environment(\.isRowHovered) private var isHovered

    let result: SearchResult
    let actions: SearchResultActions

    var body: some View {
        #if DEBUG
        let _ = { if SynthDiag.logChanges { Self._printChanges() } }()
        #endif
        let folderRequestState = appState.folderRequestState(for: result)
        HStack(spacing: SeeleSpacing.xxs) {
            // Hit-testing stays on at opacity 0 so the VoiceOver rotor
            // (via the row's named actions) can reach these actions.
            HStack(spacing: SeeleSpacing.xxs) {
                folderSlot(folderRequestState)
                // `person.crop.circle` is the profile glyph app-wide, so
                // this must open the profile, not browse. Browse stays in
                // the context menu.
                RowIconButton(
                    systemName: "person.crop.circle",
                    help: "View \(result.username)'s profile",
                    action: actions.viewProfile
                )
            }
            .opacity(isHovered || folderRequestState != nil ? 1 : 0)
            .frame(width: RowLayout.secondaryActionsWidth(2), alignment: .trailing)

            primaryAction
        }
        .frame(width: SearchResultRowLayout.trailingClusterWidth, alignment: .trailing)
    }

    /// Deliberately not on the download button: a request can run for a
    /// minute, and that button must stay usable for single files.
    @ViewBuilder
    private func folderSlot(_ state: AppState.FolderRequestState?) -> some View {
        if let state {
            FolderRequestIndicator(state: state, username: result.username)
        } else {
            RowIconButton(
                systemName: "folder.badge.questionmark",
                help: "Browse this folder",
                action: actions.browseFolder
            )
        }
    }

    private var primaryAction: some View {
        let status = actions.downloadStatus
        let ignored = actions.isIgnored
        return RowIconButton(
            systemName: Self.actionIcon(status),
            help: actions.actionHelp,
            tint: actionColor(status, ignored: ignored),
            weight: .semibold,
            isProminent: true,
            action: actions.download
        )
        .disabled(actions.isQueued || ignored)
    }

    private static func actionIcon(_ status: Transfer.TransferStatus?) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .transferring, .queued, .waiting, .connecting: "arrow.down.circle.fill"
        case .failed, .cancelled: "arrow.clockwise.circle"
        case .none: "arrow.down.circle"
        }
    }

    private func actionColor(_ status: Transfer.TransferStatus?, ignored: Bool) -> Color {
        if ignored { return SeeleColors.textTertiary }
        return switch status {
        case .completed: SeeleColors.success
        case .transferring, .queued, .waiting, .connecting: SeeleColors.accent
        case .failed, .cancelled: SeeleColors.warning
        case .none: isHovered ? SeeleColors.accent : SeeleColors.textSecondary
        }
    }
}
