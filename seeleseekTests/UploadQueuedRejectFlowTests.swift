import Foundation
import Testing
@testable import SeeleseekCore

/// Regression tests for the audit's claim that an upload row landing on
/// `.queued` (peer accepted but is queueing us) becomes inert. Without
/// the round-3 fix, `handleTransferResponse` set the row to `.queued`
/// but neither re-inserted into `uploadQueue` nor scheduled a retry, so
/// nothing drove the transfer forward unless the peer happened to send
/// a follow-up TransferRequest. The fix routes `.queued` rejects through
/// `scheduleUploadRetry`, which sleeps the backoff ladder and re-attempts
/// via `retryUploadInternal`.
@MainActor
@Suite("Upload \"Queued\" reject flow")
struct UploadQueuedRejectFlowTests {

    private func seededManager(reason: String) -> (UploadManager, MockTransferTracking, UUID, UInt32) {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let transferId = UUID()
        let token: UInt32 = 42

        let upload = Transfer(
            id: transferId,
            username: "alice",
            filename: "@@music\\song.mp3",
            size: 1_000_000,
            direction: .upload,
            status: .connecting
        )
        tracking.uploads.append(upload)
        manager._setTransferStateForTest(tracking)

        let pending = UploadManager.PendingUpload(
            transferId: transferId,
            username: "alice",
            filename: "@@music\\song.mp3",
            localPath: "/tmp/song.mp3",
            size: 1_000_000,
            token: token
        )
        manager._seedPendingUploadForTest(pending, token: token)
        return (manager, tracking, transferId, token)
    }

    @Test("Queued reject sets row to .queued and arms a retry")
    func queuedRejectSchedulesRetry() async {
        let (manager, tracking, transferId, _) = seededManager(reason: "Queued")

        await manager._handleTransferRejectionForTest(token: 42, reason: "Queued")

        let row = tracking.uploads.first { $0.id == transferId }
        #expect(row?.status == .queued, "Queued reject must keep the row at .queued (not .failed)")
        // Note: the error string is rewritten by `scheduleUploadRetry`
        // to the "Retrying in Xs..." badge format that the UI parses
        // for the countdown — so we assert the *retry* was scheduled
        // rather than the literal "Queued" text.
        #expect(row?.error?.contains("Retrying in") == true,
                "scheduleUploadRetry must rewrite the error to the countdown badge format")
        #expect(row?.nextRetryAt != nil, "scheduleUploadRetry must persist nextRetryAt")
        // Pre-fix: pendingRetries was empty for `.queued`. Post-fix: a
        // retry Task should be sleeping the backoff.
        #expect(manager._pendingRetryTaskForTest(transferId: transferId) != nil,
                "Queued reject must schedule a retry so the row doesn't sit inert forever")
    }

    @Test("Hard-failed reject still routes through failUpload (no .queued retry path interference)")
    func failedRejectStillFails() async {
        let (manager, tracking, transferId, token) = seededManager(reason: "Banned")

        await manager._handleTransferRejectionForTest(token: token, reason: "Banned")

        let row = tracking.uploads.first { $0.id == transferId }
        // "Banned" hits the terminal-pattern list in `isRetriableError`,
        // so failUpload sets `.failed` and does NOT schedule a retry.
        #expect(row?.status == .failed)
        #expect(manager._pendingRetryTaskForTest(transferId: transferId) == nil)
    }

    @Test("Cancelled reject is terminal (no retry, status .cancelled)")
    func cancelledRejectIsTerminal() async {
        let (manager, tracking, transferId, token) = seededManager(reason: "Cancelled")

        await manager._handleTransferRejectionForTest(token: token, reason: "Cancelled")

        let row = tracking.uploads.first { $0.id == transferId }
        #expect(row?.status == .cancelled)
        #expect(manager._pendingRetryTaskForTest(transferId: transferId) == nil)
    }
}
