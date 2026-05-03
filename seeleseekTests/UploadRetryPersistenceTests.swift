import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Regression tests for `Transfer.nextRetryAt` persistence and
/// `UploadManager.rearmPersistedRetries`.
///
/// Before this work, `pendingRetries: [UUID: Task]` was in-memory only.
/// A user who quit the app during a 28-minute backoff would relaunch
/// and find the row stuck at `.failed` with a stale "Retrying in 28m..."
/// string forever — the Task that drove the retry died with the process.
/// The fix:
///   1. `nextRetryAt: Date?` on `Transfer` is persisted to the DB.
///   2. `scheduleUploadRetry` stamps the field; clearing it when the row
///      moves out of `.failed` (or when the retry fires).
///   3. `rearmPersistedRetries` walks `transferState.uploads` at startup
///      and re-creates the in-memory Task for each `.failed` row that
///      still has a pending `nextRetryAt`. Past-due rows fire
///      immediately (with a small per-row stagger so a launch with 50
///      pending retries doesn't slam the network); future rows
///      reschedule with the remaining delay.
@MainActor
@Suite("UploadManager retry persistence + rearm", .serialized)
struct UploadRetryPersistenceTests {

    private func makeFailed(retryCount: Int = 1, nextRetryAt: Date?) -> Transfer {
        Transfer(
            id: UUID(),
            username: "alice",
            filename: "@@music\\song.mp3",
            size: 1_000_000,
            direction: .upload,
            status: .failed,
            error: "Peer disconnected",
            retryCount: retryCount,
            nextRetryAt: nextRetryAt
        )
    }

    private func makeIndexedFile(for transfer: Transfer) -> ShareManager.IndexedFile {
        ShareManager.IndexedFile(
            localPath: "/tmp/song.mp3",
            sharedPath: transfer.filename,
            size: transfer.size,
            folderID: UUID()
        )
    }

    private func makeSetup(transfers: [Transfer], indexedFiles: [ShareManager.IndexedFile] = []) -> (UploadManager, MockTransferTracking, ShareManager) {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let shares = ShareManager()
        if !indexedFiles.isEmpty {
            shares._seedFileIndexForTest(indexedFiles)
        }
        manager._setTransferStateForTest(tracking)
        manager._setShareManagerForTest(shares)
        for t in transfers {
            tracking.uploads.append(t)
        }
        return (manager, tracking, shares)
    }

    // MARK: - Past-due rearm

    @Test("Past-due retry fires immediately on rearm and reuses the same row")
    func pastDueFiresImmediately() async {
        let pastDue = makeFailed(retryCount: 1, nextRetryAt: Date().addingTimeInterval(-60))
        let (manager, tracking, shares) = makeSetup(
            transfers: [pastDue],
            indexedFiles: [makeIndexedFile(for: pastDue)]
        )
        // shareManager is held weakly by UploadManager. Keep it alive.
        _ = shares

        manager.rearmPersistedRetries()

        // Deterministically wait for the rearm Task to finish its body
        // (Task.sleep(0) → MainActor.run → retryUploadInternal). Polling
        // a fixed window flaked on CI when other parallel @MainActor
        // suites were starving the rearm continuation past 5s. With the
        // task value awaited directly, we observe the proof rearm fired:
        //   1. The same transferId is preserved (no duplicate row).
        //   2. retryCount is at least 2 (retryUploadInternal bumped it
        //      from 1 → 2 before processQueue cascaded).
        // retryUploadInternal also kicks off a processQueue Task that
        // can asynchronously cascade through startUpload → failUpload →
        // scheduleUploadRetry, but retryCount is stamped synchronously
        // inside retryUploadInternal so it's stable by the time rearm's
        // task body completes.
        if let task = manager._pendingRetryTaskForTest(transferId: pastDue.id) {
            await task.value
        }

        #expect(tracking.uploads.count == 1, "rearm must reuse the existing transferId, not spawn a duplicate row")
        let row = tracking.uploads.first
        #expect(row?.id == pastDue.id)
        #expect((row?.retryCount ?? 0) >= 2, "rearm must drive retryUploadInternal which bumps retryCount")
    }

    // MARK: - Future-dated rearm

    @Test("Future retry stays .failed and is rescheduled, not fired")
    func futureRetryRearms() async {
        let future = makeFailed(retryCount: 1, nextRetryAt: Date().addingTimeInterval(120))
        let (manager, tracking, shares) = makeSetup(
            transfers: [future],
            indexedFiles: [makeIndexedFile(for: future)]
        )
        _ = shares

        manager.rearmPersistedRetries()

        try? await Task.sleep(for: .milliseconds(50))

        let row = tracking.uploads.first
        #expect(row?.status == .failed, "future retry must not fire yet")
        #expect(row?.nextRetryAt != nil, "future nextRetryAt must be preserved")
        #expect(manager._uploadQueueForTest.isEmpty, "future retry should not have enqueued")
    }

    // MARK: - Skip non-eligible rows

    @Test("Rearm skips rows that already exhausted retries")
    func skipExhaustedRetries() async {
        // maxRetries == retryDelays.count. With the 5-step ladder, a row
        // at retryCount 5 is fully exhausted and should not re-arm.
        let exhausted = makeFailed(retryCount: 5, nextRetryAt: Date().addingTimeInterval(-60))
        let (manager, tracking, shares) = makeSetup(
            transfers: [exhausted],
            indexedFiles: [makeIndexedFile(for: exhausted)]
        )
        _ = shares

        manager.rearmPersistedRetries()
        try? await Task.sleep(for: .milliseconds(100))

        let row = tracking.uploads.first
        #expect(row?.status == .failed, "exhausted retry must not be rearmed")
        #expect(manager._uploadQueueForTest.isEmpty)
    }

    @Test("Rearm skips rows without nextRetryAt")
    func skipMissingTimestamp() async {
        let noStamp = makeFailed(retryCount: 1, nextRetryAt: nil)
        let (manager, tracking, shares) = makeSetup(
            transfers: [noStamp],
            indexedFiles: [makeIndexedFile(for: noStamp)]
        )
        _ = shares

        manager.rearmPersistedRetries()
        try? await Task.sleep(for: .milliseconds(100))

        let row = tracking.uploads.first
        #expect(row?.status == .failed, "no nextRetryAt → no rearm")
        #expect(manager._uploadQueueForTest.isEmpty)
    }

    @Test("Rearm skips rows in non-failed state even if nextRetryAt is set")
    func skipNonFailedRows() async {
        // A stale nextRetryAt left over from a row that has since moved
        // to .completed must not resurrect a retry on launch.
        var completed = makeFailed(retryCount: 1, nextRetryAt: Date().addingTimeInterval(-60))
        completed.status = .completed
        let (manager, tracking, shares) = makeSetup(
            transfers: [completed],
            indexedFiles: [makeIndexedFile(for: completed)]
        )
        _ = shares

        manager.rearmPersistedRetries()
        try? await Task.sleep(for: .milliseconds(100))

        let row = tracking.uploads.first
        #expect(row?.status == .completed, ".completed row must remain untouched")
        #expect(manager._uploadQueueForTest.isEmpty)
    }

    // MARK: - cancelRetry clears the persisted timestamp

    @Test("cancelRetry clears persisted nextRetryAt so it can't resurrect on relaunch")
    func cancelRetryClears() async {
        let pending = makeFailed(retryCount: 1, nextRetryAt: Date().addingTimeInterval(120))
        let (manager, tracking, shares) = makeSetup(transfers: [pending])
        _ = shares

        manager.cancelRetry(transferId: pending.id)

        let row = tracking.uploads.first
        #expect(row?.nextRetryAt == nil, "cancelRetry must clear nextRetryAt")
    }
}
