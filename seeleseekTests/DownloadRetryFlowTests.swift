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
}
