import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Verifies `TransferState.salvageableDownloadIDs` stays in sync with
/// `downloads`, so the salvage path on `DownloadManager.handlePoolTransferRequest`
/// can look up candidates in O(1) instead of filtering every history entry.
@Suite("TransferState salvage index")
@MainActor
struct TransferStateSalvageIndexTests {

    @Test("Salvageable statuses land in the index")
    func salvageableStatusesLandInIndex() {
        let state = TransferState()
        let id = UUID()
        state.downloads = [
            Transfer(id: id, username: "alice", filename: "song.mp3",
                     size: 100, direction: .download, status: .queued)
        ]
        let found = state.findSalvageableDownload(username: "alice", filename: "song.mp3")
        #expect(found?.id == id)
    }

    @Test("Terminal statuses are excluded from the index")
    func terminalStatusesExcluded() {
        let state = TransferState()
        state.downloads = [
            Transfer(id: UUID(), username: "alice", filename: "a.mp3",
                     size: 1, direction: .download, status: .completed),
            Transfer(id: UUID(), username: "alice", filename: "b.mp3",
                     size: 1, direction: .download, status: .failed),
            Transfer(id: UUID(), username: "alice", filename: "c.mp3",
                     size: 1, direction: .download, status: .cancelled),
            Transfer(id: UUID(), username: "alice", filename: "d.mp3",
                     size: 1, direction: .download, status: .transferring),
        ]
        #expect(state.findSalvageableDownload(username: "alice", filename: "a.mp3") == nil)
        #expect(state.findSalvageableDownload(username: "alice", filename: "b.mp3") == nil)
        #expect(state.findSalvageableDownload(username: "alice", filename: "c.mp3") == nil)
        #expect(state.findSalvageableDownload(username: "alice", filename: "d.mp3") == nil)
    }

    @Test("Status transition updates the index")
    func statusTransitionUpdatesIndex() {
        let state = TransferState()
        let id = UUID()
        state.downloads = [
            Transfer(id: id, username: "alice", filename: "song.mp3",
                     size: 100, direction: .download, status: .queued)
        ]
        #expect(state.findSalvageableDownload(username: "alice", filename: "song.mp3") != nil)

        state.updateTransfer(id: id) { $0.status = .completed }
        #expect(state.findSalvageableDownload(username: "alice", filename: "song.mp3") == nil,
                "completed entries must fall out of the salvage index")
    }

    @Test("Bulk history does not poison the salvage lookup")
    func bulkHistoryIgnored() {
        let state = TransferState()
        let liveID = UUID()
        var entries: [Transfer] = (0..<5_000).map { i in
            Transfer(id: UUID(), username: "alice", filename: "done-\(i).mp3",
                     size: 1, direction: .download, status: .completed)
        }
        entries.append(Transfer(id: liveID, username: "alice", filename: "live.mp3",
                                size: 1, direction: .download, status: .queued))
        state.downloads = entries

        #expect(state.findSalvageableDownload(username: "alice", filename: "live.mp3")?.id == liveID)
        #expect(state.findSalvageableDownload(username: "alice", filename: "done-1234.mp3") == nil)
    }
}
