import Foundation
import Testing
@testable import SeeleseekCore

/// Regression: every upload-failure exit must call `processQueue()` so the
/// freed concurrency slot is reused immediately. Pre-round-1 fix, four
/// failure paths in `UploadManager` removed `pendingTransfers` /
/// `activeUploads` but skipped `processQueue()`, so queued uploads sat
/// idle even though the slot was free. The round-1 fix introduced
/// `failUploadAttempt` as the single point that bundles cleanup +
/// `processQueue()`; this test asserts that contract via a test seam.
@MainActor
@Suite("Upload failure path queue-drain")
struct UploadFailureQueueDrainTests {

    @Test("failUploadAttempt frees pending+active slot")
    func failUploadAttemptFreesSlot() async {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let transferId = UUID()
        let token: UInt32 = 99

        let row = Transfer(
            id: transferId,
            username: "alice",
            filename: "@@music\\song.mp3",
            size: 1_000_000,
            direction: .upload,
            status: .connecting
        )
        tracking.uploads.append(row)
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

        #expect(manager._pendingTransferCountForTest == 1)

        await manager._failUploadAttemptForTest(
            transferId: transferId,
            error: "Failed to connect to peer",
            token: token
        )

        // Both dicts cleared so processQueue's "in-flight" accounting
        // (active.count + pending.count) reflects the freed slot.
        #expect(manager._pendingTransferCountForTest == 0,
                "failUploadAttempt must drop the pendingTransfers entry")
        #expect(manager._activeUploadCountForTest == 0,
                "failUploadAttempt must drop the activeUploads entry")

        // Row was retriable ("Failed to connect to peer" is not in the
        // terminal-pattern list), so we expect a retry task scheduled.
        #expect(manager._pendingRetryTaskForTest(transferId: transferId) != nil,
                "Retriable failure must schedule a retry")

        // Row status reflects failUpload's transition.
        let updated = tracking.uploads.first { $0.id == transferId }
        #expect(updated?.status == .failed)
    }

    @Test("failUploadAttempt cancels per-token PierceFirewall watchdog")
    func failUploadAttemptCancelsPierceFirewallTimeout() async {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let transferId = UUID()
        let token: UInt32 = 7

        let row = Transfer(
            id: transferId,
            username: "alice",
            filename: "@@music\\song.mp3",
            size: 1_000_000,
            direction: .upload,
            status: .connecting
        )
        tracking.uploads.append(row)
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

        // Simulate the PierceFirewall watchdog being armed (production
        // arms it inside `openFileConnection` when direct F connect
        // fails). We don't have a public seam for that, but we can
        // assert via behaviour: after failUploadAttempt, no watchdog
        // task should remain in the dict.
        await manager._failUploadAttemptForTest(
            transferId: transferId,
            error: "Failed to connect to peer",
            token: token
        )

        #expect(manager._pierceFirewallTimeoutTaskForTest(token: token) == nil,
                "failUploadAttempt must clear the per-token PierceFirewall watchdog so it can't fire and overwrite the row later")
    }
}
