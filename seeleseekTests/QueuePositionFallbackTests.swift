import Foundation
import Testing
@testable import SeeleseekCore

/// Regression tests for the case-insensitive / pending-fallback paths in
/// `handlePlaceInQueueReply`.
///
/// Previously the lookup required strict (username, filename) equality.
/// Some peers normalise filenames before echoing them back in
/// `PlaceInQueueReply`, which silently dropped the position update — the
/// audit's "queue position not shown" symptom. The fix layers two
/// fallbacks: case-insensitive match against `transferState.downloads`,
/// then a single-match lookup against `pendingDownloads` keyed on
/// (lowercased username, lowercased filename).
@MainActor
@Suite("PlaceInQueueReply username/filename fallbacks")
struct QueuePositionFallbackTests {

    private func makeTransfer(username: String, filename: String, status: Transfer.TransferStatus = .waiting) -> Transfer {
        Transfer(
            id: UUID(),
            username: username,
            filename: filename,
            size: 1_000_000,
            direction: .download,
            status: status
        )
    }

    @Test("Exact username/filename match still wins")
    func exactMatch() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\song.mp3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)

        manager._handlePlaceInQueueReplyForTest(username: "alice", filename: "@@music\\song.mp3", position: 7)

        let updated = tracking.downloads.first { $0.id == transfer.id }
        #expect(updated?.queuePosition == 7)
    }

    @Test("Case-mismatched filename still updates the queue position")
    func caseInsensitiveFilenameFallback() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\Song.MP3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)

        // Peer echoes back the filename lowercased.
        manager._handlePlaceInQueueReplyForTest(username: "alice", filename: "@@music\\song.mp3", position: 12)

        let updated = tracking.downloads.first { $0.id == transfer.id }
        #expect(updated?.queuePosition == 12, "case-insensitive fallback must update the row that's clearly the same file")
    }

    @Test("Case-mismatched username still updates the queue position")
    func caseInsensitiveUsernameFallback() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "Alice", filename: "@@music\\song.mp3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)

        manager._handlePlaceInQueueReplyForTest(username: "alice", filename: "@@music\\song.mp3", position: 3)

        let updated = tracking.downloads.first { $0.id == transfer.id }
        #expect(updated?.queuePosition == 3)
    }

    @Test("Pending-download fallback when transferState row is missing")
    func pendingFallback() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        manager._setTransferStateForTest(tracking)

        // Row exists in pendingDownloads but, e.g., transferState was
        // momentarily out of sync (race between ack and update). The
        // pending-fallback should still update the position via the
        // transferId stored in the pending entry.
        let transferId = UUID()
        let row = makeTransfer(username: "alice", filename: "@@music\\song.mp3", status: .connecting)
        var rowWithId = row
        rowWithId = Transfer(
            id: transferId,
            username: row.username,
            filename: row.filename,
            size: row.size,
            direction: row.direction,
            status: row.status
        )
        tracking.downloads.append(rowWithId)

        manager._seedPendingDownloadForTest(
            DownloadManager.PendingDownload(
                transferId: transferId,
                username: "alice",
                filename: "@@MUSIC\\Song.MP3",
                size: 1_000_000,
                peerIP: nil,
                peerPort: nil
            ),
            token: 88
        )

        // Peer reports position with peer-side normalised case.
        manager._handlePlaceInQueueReplyForTest(username: "alice", filename: "@@music\\song.mp3", position: 5)

        let updated = tracking.downloads.first { $0.id == transferId }
        #expect(updated?.queuePosition == 5)
    }

    @Test("Reply for an unknown user/file is ignored")
    func unknownReplyIsDropped() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\song.mp3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)

        manager._handlePlaceInQueueReplyForTest(username: "bob", filename: "@@other\\thing.mp3", position: 99)

        let updated = tracking.downloads.first { $0.id == transfer.id }
        #expect(updated?.queuePosition == nil, "unrelated replies must not mutate any row")
    }
}
