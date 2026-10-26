import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Every `.queued` upload row must be owned by the manager's queue (or a
/// scheduled retry). Rows persisted as queued used to come back with
/// nothing driving them and read "Queued" forever, fresh peer requests
/// waited in the queue with no row at all, and one slow start blocked
/// every entry behind it.
@MainActor
@Suite("Upload queue ownership", .timeLimit(.minutes(1)))
struct UploadQueueOwnershipTests {

    private let filename = "@@music\\song.mp3"

    private func makeFile() -> ShareManager.IndexedFile {
        ShareManager.IndexedFile(localPath: "/tmp/song.mp3", sharedPath: filename, size: 5_000_000, folderID: UUID())
    }

    private func makeSetup() async -> (UploadManager, MockTransferTracking, ShareManager) {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let shares = ShareManager(defaults: TestDefaults.isolated())
        await shares._seedFileIndexForTest([makeFile()])
        await manager._setTransferStateForTest(tracking)
        await manager._setShareManagerForTest(shares)
        return (manager, tracking, shares)
    }

    private func makeRow(status: Transfer.TransferStatus, nextRetryAt: Date? = nil, direction: Transfer.TransferDirection = .upload) -> Transfer {
        Transfer(
            id: UUID(),
            username: "alice",
            filename: filename,
            size: 5_000_000,
            direction: direction,
            status: status,
            retryCount: 3,
            nextRetryAt: nextRetryAt
        )
    }

    @Test("A fresh peer request gets a visible .queued row that the queue entry owns")
    func freshRequestCreatesRow() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares

        let queued = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())

        #expect(queued)
        #expect(tracking.uploads.count == 1)
        #expect(tracking.uploads.first?.status == .queued)
        #expect(await manager._uploadQueueForTest.first?.existingTransferId == tracking.uploads.first?.id)
    }

    @Test("A peer request adopts a stale .queued row instead of stacking a duplicate")
    func requestAdoptsStaleRow() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        let stale = makeRow(status: .queued)
        tracking.uploads.append(stale)

        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())

        #expect(tracking.uploads.count == 1, "no duplicate row next to the stale one")
        #expect(tracking.uploads.first?.retryCount == 0, "a fresh request gets a fresh retry budget")
        #expect(await manager._uploadQueueForTest.first?.existingTransferId == stale.id)
    }

    @Test("A second request for a file already queued is refused")
    func duplicateRequestRefused() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares

        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        let second = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())

        #expect(!second)
        #expect(tracking.uploads.count == 1)
        #expect(await manager._uploadQueueForTest.count == 1)
    }

    @Test("Interleaved requests for the same file create one row and one queue entry")
    func concurrentRequestsDeduplicated() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares

        async let first = manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        async let second = manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        let results = await [first, second]

        #expect(results.filter { $0 }.count == 1)
        #expect(tracking.uploads.count == 1)
        #expect(await manager._uploadQueueForTest.count == 1)
    }

    @Test("Completed rows are never adopted")
    func completedRowNotAdopted() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        let done = makeRow(status: .completed)
        tracking.uploads.append(done)

        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())

        #expect(tracking.uploads.count == 2)
        #expect(tracking.uploads.first { $0.id == done.id }?.status == .completed)
    }

    @Test("resumeUploadsOnConnect re-drives orphaned .queued rows")
    func resumeDrivesOrphanedQueuedRows() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        await manager._setMaxConcurrentUploadsForTest(1)
        // Occupy the only slot so the resumed row stays observable in the queue.
        await manager._seedPendingUploadForTest(
            UploadManager.PendingUpload(
                transferId: UUID(), username: "bob", filename: "@@m\\b.mp3",
                localPath: "/tmp/b.mp3", size: 1, token: 1
            ),
            token: 1
        )
        let orphan = makeRow(status: .queued)
        tracking.uploads.append(orphan)

        await manager.resumeUploadsOnConnect()

        let deadline = Date().addingTimeInterval(5)
        while await manager._uploadQueueForTest.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(await manager._uploadQueueForTest.first?.existingTransferId == orphan.id)
        #expect(tracking.uploads.first?.status == .queued)
    }

    @Test("processQueue reserves slots synchronously so a pass never over-commits")
    func processQueueReservesSlots() async {
        let (manager, _, shares) = await makeSetup()
        _ = shares
        let gate = StartGate()
        await manager.setUploadPolicies([gate])
        await manager._setMaxConcurrentUploadsForTest(1)
        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        _ = await manager._enqueuePeerRequestForTest(username: "bob", filename: filename, file: makeFile())

        await manager._processQueueForTest()

        #expect(await manager._inFlightTransferCountForTest == 1)
        #expect(await manager._uploadQueueForTest.map(\.username) == ["bob"])
        await gate.release()
    }

    @Test("A start stuck on one peer does not hold up the next slot")
    func noHeadOfLineBlocking() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        let gate = StartGate()
        await manager.setUploadPolicies([gate])
        await manager._setMaxConcurrentUploadsForTest(2)
        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        _ = await manager._enqueuePeerRequestForTest(username: "bob", filename: filename, file: makeFile())

        // Not awaited: a serial queue would block here on alice forever.
        Task { await manager._processQueueForTest() }

        let deadline = Date().addingTimeInterval(5)
        while tracking.uploads.first(where: { $0.username == "bob" })?.status == .queued, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(tracking.uploads.first { $0.username == "bob" }?.status != .queued, "bob started while alice is stuck")
        #expect(tracking.uploads.first { $0.username == "alice" }?.status == .queued, "alice is still held at the gate")
        await gate.release()
    }

    @Test("Cancelling while a start is in progress keeps the row cancelled and frees the slot")
    func cancelWhileStarting() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        let gate = StartGate()
        await manager.setUploadPolicies([gate])
        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        let id = tracking.uploads[0].id
        await manager._processQueueForTest()
        #expect(await manager._inFlightTransferCountForTest == 1)

        tracking.updateTransfer(id: id) { $0.status = .cancelled }
        await manager.cancelUpload(transferId: id)
        await gate.release()

        let deadline = Date().addingTimeInterval(5)
        while await manager._inFlightTransferCountForTest > 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(await manager._inFlightTransferCountForTest == 0)
        #expect(await manager._pendingTransferCountForTest == 0)
        #expect(tracking.uploads.first?.status == .cancelled)
    }

    @Test("Cancelling a queued row removes its queue entry")
    func cancelQueuedRow() async {
        let (manager, tracking, shares) = await makeSetup()
        _ = shares
        await manager._setMaxConcurrentUploadsForTest(1)
        await manager._seedPendingUploadForTest(
            UploadManager.PendingUpload(
                transferId: UUID(), username: "bob", filename: "@@m\\b.mp3",
                localPath: "/tmp/b.mp3", size: 1, token: 1
            ),
            token: 1
        )
        _ = await manager._enqueuePeerRequestForTest(username: "alice", filename: filename, file: makeFile())
        let id = tracking.uploads[0].id

        await manager.cancelUpload(transferId: id)

        #expect(await manager._uploadQueueForTest.isEmpty)
        #expect(tracking.uploads.first?.status == .cancelled)
    }

    @Test("Retry Now is offered only for queued uploads sleeping in a backoff")
    func canRetryQueuedUploadWithBackoff() {
        #expect(makeRow(status: .queued, nextRetryAt: Date()).canRetry)
        #expect(!makeRow(status: .queued).canRetry)
        #expect(!makeRow(status: .queued, nextRetryAt: Date(), direction: .download).canRetry)
    }
}

/// Holds alice's start-stage policy check until released.
private actor StartGate: UploadPolicy {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision {
        if request.stage == .start, request.username == "alice", !released {
            await withCheckedContinuation { waiters.append($0) }
        }
        return .allow
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
