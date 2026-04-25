import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Regression tests for two retry-flow bugs:
///   1. Retries used to spawn a brand-new Transfer row instead of reusing
///      the existing one — the original was stuck at `.queued` while a
///      duplicate row drove the actual upload, polluting persisted history.
///   2. The dedup guard inside `retryUploadInternal` ran AFTER mutating the
///      row to `.queued`. When dedup tripped, the function returned
///      without enqueueing — leaving the row stranded at `.queued` with
///      nothing driving it forward.
@MainActor
@Suite("Upload retry row-reuse + dedup")
struct UploadRetryRowReuseTests {

    private func makeIndexedFile(sharedPath: String, localPath: String, size: UInt64) -> ShareManager.IndexedFile {
        ShareManager.IndexedFile(
            localPath: localPath,
            sharedPath: sharedPath,
            size: size,
            folderID: UUID()
        )
    }

    private func makeFailedTransfer(retryCount: Int = 0, error: String = "Connection lost") -> Transfer {
        Transfer(
            id: UUID(),
            username: "alice",
            filename: "@@music\\song.mp3",
            size: 5_000_000,
            direction: .upload,
            status: .failed,
            error: error,
            retryCount: retryCount
        )
    }

    private func makeSetup(file: ShareManager.IndexedFile?) -> (UploadManager, MockTransferTracking, ShareManager) {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let shares = ShareManager()
        if let file {
            shares._seedFileIndexForTest([file])
        }
        manager._setTransferStateForTest(tracking)
        manager._setShareManagerForTest(shares)
        return (manager, tracking, shares)
    }

    // MARK: - Issue 1: row reuse

    @Test("Retry reuses the existing transferId — no duplicate row added")
    func retryReusesTransferRow() async {
        let original = makeFailedTransfer()
        let (manager, tracking, shares) = makeSetup(
            file: makeIndexedFile(sharedPath: original.filename, localPath: "/tmp/song.mp3", size: original.size)
        )
        tracking.uploads.append(original)

        // `shareManager` is held weakly by `UploadManager`. Keep it alive
        // for the duration of the test so the retry's file-lookup hits
        // the seeded fileIndex rather than going through a freed weak ref.
        _ = shares
        manager._retryUploadForTest(
            transferId: original.id,
            username: original.username,
            filename: original.filename,
            size: original.size,
            retryCount: 1
        )

        #expect(tracking.uploads.count == 1, "retry must not spawn a duplicate row")
        #expect(tracking.uploads.first?.id == original.id, "the existing transferId is preserved")
        #expect(tracking.uploads.first?.status == .queued)
        #expect(tracking.uploads.first?.retryCount == 1)
        // The QueuedUpload routed back to startUpload carries the original
        // transferId so startUpload's reuse branch fires.
        #expect(manager._uploadQueueForTest.count == 1)
        #expect(manager._uploadQueueForTest.first?.existingTransferId == original.id)
    }

    @Test("Retry without ShareManager match leaves the same row terminal — still no new row")
    func retryWithMissingFileLeavesRowTerminal() async {
        let original = makeFailedTransfer()
        // No file seeded — ShareManager.fileIndex is empty so the lookup
        // fails and the retry should mark the row terminal rather than
        // adding a duplicate.
        let (manager, tracking, shares) = makeSetup(file: nil)
        tracking.uploads.append(original)

        // `shareManager` is held weakly by `UploadManager`. Keep it alive
        // for the duration of the test so the retry's file-lookup hits
        // the seeded fileIndex rather than going through a freed weak ref.
        _ = shares
        manager._retryUploadForTest(
            transferId: original.id,
            username: original.username,
            filename: original.filename,
            size: original.size,
            retryCount: 1
        )

        #expect(tracking.uploads.count == 1)
        #expect(tracking.uploads.first?.status == .failed)
        #expect(tracking.uploads.first?.error == "File no longer shared")
        #expect(manager._uploadQueueForTest.isEmpty, "no enqueue when file no longer shared")
    }

    // MARK: - Issue 2: dedup must not strand the row

    @Test("Dedup short-circuits without mutating row state when transfer already in flight")
    func dedupPreservesInflightRow() async {
        let original = makeFailedTransfer(retryCount: 1, error: "Peer unreachable (firewall)")
        let (manager, tracking, shares) = makeSetup(
            file: makeIndexedFile(sharedPath: original.filename, localPath: "/tmp/song.mp3", size: original.size)
        )
        tracking.uploads.append(original)

        // Simulate an in-flight attempt for THIS transferId — e.g. a
        // scheduled retry that already fired moments ago.
        manager._seedPendingUploadForTest(
            UploadManager.PendingUpload(
                transferId: original.id,
                username: original.username,
                filename: original.filename,
                localPath: "/tmp/song.mp3",
                size: original.size,
                token: 42
            ),
            token: 42
        )

        // A racing manual click lands here.
        // `shareManager` is held weakly by `UploadManager`. Keep it alive
        // for the duration of the test so the retry's file-lookup hits
        // the seeded fileIndex rather than going through a freed weak ref.
        _ = shares
        manager._retryUploadForTest(
            transferId: original.id,
            username: original.username,
            filename: original.filename,
            size: original.size,
            retryCount: 2
        )

        // Pre-fix this would have stamped the row as `.queued`,
        // failed the dedup, and returned — stranding the row.
        // After the fix the row state is left untouched.
        #expect(tracking.uploads.count == 1)
        #expect(tracking.uploads.first?.status == .failed)
        #expect(tracking.uploads.first?.error == "Peer unreachable (firewall)")
        #expect(tracking.uploads.first?.retryCount == 1, "retryCount must not be incremented on a dedup short-circuit")
        #expect(manager._uploadQueueForTest.isEmpty, "no duplicate enqueue")
    }
}
