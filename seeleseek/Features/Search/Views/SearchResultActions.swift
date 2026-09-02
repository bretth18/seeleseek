import SwiftUI
import SeeleseekCore

/// Row-level actions and the live state they gate on. `downloadStatus` and
/// `isIgnored` read observables at the call site, so only the view whose
/// body calls them subscribes — the row shell must not.
struct SearchResultActions: Equatable {
    let result: SearchResult
    private let appState: AppState

    init(result: SearchResult, appState: AppState) {
        self.result = result
        self.appState = appState
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.result == rhs.result && lhs.appState === rhs.appState
    }

    var downloadStatus: Transfer.TransferStatus? {
        appState.transferState.downloadStatus(for: result.filename, from: result.username)
    }

    var isIgnored: Bool {
        appState.socialState.isIgnored(result.username)
    }

    var isQueued: Bool {
        guard let s = downloadStatus else { return false }
        return s != .completed && s != .cancelled && s != .failed
    }

    var actionHelp: String {
        if isIgnored { return "User is ignored" }
        return switch downloadStatus {
        case .completed: "Already downloaded"
        case .transferring: "Downloading…"
        case .queued, .waiting, .connecting: "In queue"
        case .failed, .cancelled: "Retry download"
        case .none: "Download"
        }
    }

    func download() {
        guard !isQueued, !isIgnored else { return }
        Task { await appState.downloadManager.queueDownload(from: result) }
    }

    func browseUser() {
        appState.browseState.browseUser(result.username)
        appState.sidebarSelection = .browse
    }

    func viewProfile() {
        Task { await appState.socialState.loadProfile(for: result.username) }
    }

    func browseFolder() {
        appState.browseState.browseUser(result.username, targetPath: result.filename)
        appState.sidebarSelection = .browse
    }

    func downloadContainingFolder() {
        Task { await appState.downloadContainingFolder(of: result) }
    }

    func toggleSelection() {
        appState.searchState.toggleSelection(result.id)
    }

    func copyFilename() {
        result.displayFilename.copyToPasteboard()
    }

    func copyPath() {
        result.filename.copyToPasteboard()
    }
}
