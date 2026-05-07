import Testing
import Foundation
import Synchronization
@testable import SeeleseekCore

/// `Mutex`-backed counter so the API stays `nonisolated`/`Sendable`
/// regardless of the suite's actor isolation. `final class` because
/// `Mutex` is non-Copyable.
nonisolated private final class FireCounter: Sendable {
    private let state = Mutex(0)
    var value: Int { state.withLock { $0 } }
    func bump() { state.withLock { $0 += 1 } }
}

/// Regression tests for `ShareManager.countsChangesStream` — the hook
/// `NetworkClient` uses to re-broadcast `SharedFoldersFiles` after the
/// disk rescan completes (so peers stop seeing "0 shared files" when the
/// login broadcast loses the race against the disk walk).
@MainActor
@Suite("ShareManager count-change notifications")
struct ShareCountNotificationTests {

    /// Generous upper bound for waiting on the 200 ms debounce + a yield
    /// to propagate to the consumer Task. CI scheduling under contention
    /// can easily blow past 350 ms; polling against this ceiling lets the
    /// test return as soon as the expected value is reached without
    /// flaking when it isn't.
    private static let yieldTimeoutMillis = 2_000
    /// Quiescence window after a counter reaches its target — long enough
    /// for any rogue second yield to land. Needs to be > the 200 ms
    /// debounce so a second debounce-window-fire would have arrived.
    private static let quiescenceMillis = 400

    /// Subscribe to `countsChangesStream()` and feed each yield into the
    /// caller's `FireCounter`. Stream is allocated synchronously here so
    /// the continuation is registered before this function returns — the
    /// same pattern `NetworkClient.init` uses. Allocating the stream
    /// inside the Task body would expose tests to a Task-scheduling
    /// race against any subsequent publisher.
    ///
    /// Caller MUST `await primeConsumer(task)` (or `await Task.sleep(...)`)
    /// before the first publish, to give the Task body time to enter
    /// `for await stream`. On CI the AsyncStream buffer that's supposed
    /// to cover pre-iteration yields was not landing reliably — empirically
    /// the consume Task needed to be parked at its first `await
    /// iterator.next()` before yields would propagate.
    private func consume(_ shares: ShareManager, into counter: FireCounter) -> Task<Void, Never> {
        let stream = shares.countsChangesStream()
        return Task {
            for await _ in stream {
                counter.bump()
            }
        }
    }

    /// Hand the MainActor over long enough for a freshly-created consume
    /// Task to enter its `for await` loop. A bare `Task.yield()` is not
    /// sufficient on CI under load — the consume Task can lose multiple
    /// scheduling rounds to whatever else is queued. 50 ms is empirically
    /// well above what's needed locally and gives plenty of slack on CI.
    private func primeConsumer() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Poll until `counter` reaches `target` or `Self.yieldTimeoutMillis`
    /// elapses. Returns the observed value. Polling-with-timeout is what
    /// keeps these tests passing on CI under load — a fixed `Task.sleep`
    /// has to be sized for the worst-case scheduler delay or it flakes.
    private func waitForCounter(_ counter: FireCounter, toReach target: Int) async -> Int {
        let deadline = Date().addingTimeInterval(Double(Self.yieldTimeoutMillis) / 1_000)
        while counter.value < target && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return counter.value
    }

    @Test("rescanAll fires each subscriber exactly once")
    func rescanAllFiresSubscribers() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }
        await primeConsumer()

        await shares.rescanAll()
        let observed = await waitForCounter(counter, toReach: 1)

        #expect(observed == 1, "rescanAll must trigger one trailing-edge yield")
    }

    @Test("removeFolder fires subscribers")
    func removeFolderFiresSubscribers() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }
        await primeConsumer()

        // Synthetic folder — never added, so the removeAll calls are
        // no-ops, but the notification path is the same shape.
        let folder = ShareManager.SharedFolder(path: "/nonexistent/path")
        shares.removeFolder(folder)
        let observed = await waitForCounter(counter, toReach: 1)

        #expect(observed == 1)
    }

    @Test("Multiple subscribers all receive every yield (fan-out)")
    func multipleSubscribersFanOut() async {
        let shares = ShareManager()
        let a = FireCounter()
        let b = FireCounter()
        let taskA = consume(shares, into: a)
        let taskB = consume(shares, into: b)
        defer {
            taskA.cancel()
            taskB.cancel()
        }
        await primeConsumer()

        await shares.rescanAll()
        let observedA = await waitForCounter(a, toReach: 1)
        let observedB = await waitForCounter(b, toReach: 1)

        #expect(observedA == 1, "first subscriber must fire")
        #expect(observedB == 1, "second subscriber must fire — vanilla AsyncStream is single-consumer; fan-out is implemented by ShareManager")
    }

    @Test("Cancelling a consumer Task removes its continuation")
    func cancellingConsumerTearsDownContinuation() async {
        let shares = ShareManager()
        let cancelled = FireCounter()
        let kept = FireCounter()
        let cancelledTask = consume(shares, into: cancelled)
        let keptTask = consume(shares, into: kept)
        defer { keptTask.cancel() }

        cancelledTask.cancel()
        // `onTermination` hops to MainActor to remove the entry. Yield
        // the actor so the cleanup Task can run before we publish.
        try? await Task.sleep(for: .milliseconds(100))

        await shares.rescanAll()
        let observedKept = await waitForCounter(kept, toReach: 1)

        #expect(cancelled.value == 0, "cancelled subscriber must not fire")
        #expect(observedKept == 1, "remaining subscriber must still fire")
    }

    @Test("Rapid changes coalesce into a single trailing-edge yield (debounce)")
    func rapidChangesDebounce() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }
        await primeConsumer()

        for _ in 0..<5 {
            await shares.rescanAll()
        }
        // Wait for the trailing-edge yield to land, then settle long
        // enough for any rogue second yield to arrive too.
        _ = await waitForCounter(counter, toReach: 1)
        try? await Task.sleep(for: .milliseconds(Self.quiescenceMillis))

        #expect(counter.value == 1, "5 rapid changes must coalesce into 1 yield")
    }

    @Test("loadPersistedFolders does not yield on its own (no implicit rescan)")
    func loadPersistedFoldersIsSilent() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }
        await primeConsumer()

        // Pre-refactor `ShareManager.init` auto-spawned a rescan via load();
        // load is now an explicit, side-effect-free call. Calling it
        // alone must NOT yield — only an actual count change does.
        shares.loadPersistedFolders()
        // No target value to poll for (we expect 0); just sleep long
        // enough to confirm no spurious yield arrives.
        try? await Task.sleep(for: .milliseconds(Self.quiescenceMillis))

        #expect(counter.value == 0, "loadPersistedFolders must not yield — it doesn't change the file index")
    }

    @Test("rescanAll on empty sharedFolders does NOT wipe persisted data")
    func emptyRescanPreservesPersistedData() async {
        // Regression: `rescanAll` used to unconditionally `save()` at the
        // end. With sharedFolders empty (loadPersistedFolders skipped or
        // failed), that save serialized `[]` and overwrote the user's
        // persisted folder list — silently wiping their shares on next
        // open. Test runs against an isolated UserDefaults suite so it
        // doesn't race other tests over `.standard`.
        let suiteName = "ShareManagerTest-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let sentinel = Data("[\"sentinel\"]".utf8)
        suite.set(sentinel, forKey: "SeeleSeek.SharedFolders")

        // Construct ShareManager without calling loadPersistedFolders —
        // sharedFolders stays empty, exercising the wipe path.
        let shares = ShareManager(defaults: suite)
        await shares.rescanAll()

        let after = suite.data(forKey: "SeeleSeek.SharedFolders")
        #expect(after == sentinel, "rescanAll on empty sharedFolders must not overwrite persisted data")
    }
}
