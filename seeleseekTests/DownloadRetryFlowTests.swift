import Foundation
import Testing
@testable import SeeleseekCore

@MainActor
@Suite("Download retry flow")
struct DownloadRetryFlowTests {
    private func makeTransfer(username: String, filename: String, status: Transfer.TransferStatus = .connecting) -> Transfer {
        Transfer(
            id: UUID(),
            username: username,
            filename: filename,
            size: 1_000_000,
            direction: .download,
            status: status
        )
    }

    private func makePending(_ transfer: Transfer) -> DownloadManager.PendingDownload {
        DownloadManager.PendingDownload(
            transferId: transfer.id,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size,
            peerIP: nil,
            peerPort: nil
        )
    }

    @Test("UploadFailed schedules automatic retry instead of terminal failure")
    func uploadFailedSchedulesRetry() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\same.mp3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(transfer), token: 10)

        manager.handleUploadFailed(username: "alice", filename: transfer.filename)

        let row = tracking.downloads.first
        #expect(row?.status == .failed)
        #expect(row?.error == "Retrying in 10s...")
        #expect(row?.nextRetryAt != nil)
        #expect(manager._pendingDownloadCount == 0)
    }

    @Test("UploadFailed matches pending download by username and filename")
    func uploadFailedMatchesUsernameAndFilename() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let filename = "@@music\\same.mp3"
        let alice = makeTransfer(username: "alice", filename: filename)
        let bob = makeTransfer(username: "bob", filename: filename)
        tracking.downloads.append(alice)
        tracking.downloads.append(bob)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(alice), token: 10)
        manager._seedPendingDownloadForTest(makePending(bob), token: 11)

        manager.handleUploadFailed(username: "bob", filename: filename)

        let aliceRow = tracking.downloads.first { $0.id == alice.id }
        let bobRow = tracking.downloads.first { $0.id == bob.id }
        #expect(aliceRow?.status == .connecting)
        #expect(aliceRow?.nextRetryAt == nil)
        #expect(bobRow?.status == .failed)
        #expect(bobRow?.error == "Retrying in 10s...")
        #expect(manager._pendingDownloadCount == 1)
    }

    /// Regression: an empty `username` previously fell back to a
    /// filename-only match, which could fail the wrong row when the
    /// same file was queued from several peers. The fallback is gone —
    /// an empty username drops the message.
    @Test("UploadFailed with empty username drops the message")
    func uploadFailedEmptyUsernameDrops() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\same.mp3")
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(transfer), token: 10)

        manager.handleUploadFailed(username: "", filename: transfer.filename)

        let row = tracking.downloads.first
        #expect(row?.status == .connecting, "empty username must not mutate any row")
        #expect(row?.nextRetryAt == nil)
        #expect(manager._pendingDownloadCount == 1, "pending entry must survive a dropped message")
    }

    /// While bytes are flowing the F-connection receive loop owns the
    /// success/failure path. A peer-protocol UploadFailed arriving here
    /// is either stale (for an earlier attempt) or redundant with a
    /// connection close that's about to throw out of the receive loop.
    /// Drop it so we don't briefly flicker the row to `.failed` and
    /// then back to `.completed` when the bytes actually finish.
    @Test("UploadFailed during .transferring is dropped and pending entry survives")
    func uploadFailedDuringTransferringIsDropped() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\same.mp3", status: .transferring)
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(transfer), token: 10)

        manager.handleUploadFailed(username: "alice", filename: transfer.filename)

        let row = tracking.downloads.first
        #expect(row?.status == .transferring, "live transfer must not be torn down by an Upload* message")
        #expect(row?.error == nil)
        #expect(row?.nextRetryAt == nil)
        #expect(manager._pendingDownloadCount == 1, "receive loop is still using this entry")
    }

    /// Same guard for UploadDenied as for UploadFailed: an inbound
    /// `Denied` while we're already receiving bytes is meaningless,
    /// and processing it would mark the row `.failed` mid-transfer.
    @Test("UploadDenied during .transferring is dropped and pending entry survives")
    func uploadDeniedDuringTransferringIsDropped() {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let transfer = makeTransfer(username: "alice", filename: "@@music\\same.mp3", status: .transferring)
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(transfer), token: 10)

        manager.handleUploadDenied(username: "alice", filename: transfer.filename, reason: "Queue full")

        let row = tracking.downloads.first
        #expect(row?.status == .transferring)
        #expect(row?.error == nil)
        #expect(manager._pendingDownloadCount == 1)
    }

    /// `handleUploadFailed` has a "saw a partial file" branch that
    /// deletes the partial and re-queues the row from scratch — used
    /// when a peer that didn't support resume aborted our resume
    /// attempt. Verify the synchronous side-effects (status, error,
    /// bytes, partial deletion, pending cleanup). The branch also
    /// spawns a 2-second-delayed retry Task; we don't await it
    /// (networkClient is nil in tests, so it would log an error and
    /// return), and the assertions below run before it wakes.
    @Test("UploadFailed after a partial file deletes it and re-queues from scratch")
    func uploadFailedAfterPartialDeletesAndRequeues() throws {
        let manager = DownloadManager()
        let tracking = MockTransferTracking()
        let filename = "@@music\\Artist\\Album\\song.mp3"
        var transfer = makeTransfer(username: "alice", filename: filename, status: .connecting)
        transfer.bytesTransferred = 256
        tracking.downloads.append(transfer)
        manager._setTransferStateForTest(tracking)
        manager._seedPendingDownloadForTest(makePending(transfer), token: 10)

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seeleseek-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        manager._setDownloadDirectoryOverrideForTest(tempRoot)

        let partialPath = tempRoot
            .appendingPathComponent("Incomplete")
            .appendingPathComponent(manager._incompleteBasenameForTest(soulseekPath: filename, username: "alice"))
        try FileManager.default.createDirectory(
            at: partialPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: 256).write(to: partialPath)
        #expect(FileManager.default.fileExists(atPath: partialPath.path))

        manager.handleUploadFailed(username: "alice", filename: filename)

        let row = tracking.downloads.first
        #expect(row?.status == .queued, "partial-file branch must re-queue from scratch")
        #expect(row?.error == nil)
        #expect(row?.bytesTransferred == 0, "delete-and-restart must reset bytes to zero")
        #expect(!FileManager.default.fileExists(atPath: partialPath.path), "partial file must be deleted")
        #expect(manager._pendingDownloadCount == 0, "old pending entry is consumed by re-queue")
    }
}
