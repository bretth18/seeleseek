import Testing
import Foundation
import Synchronization
@testable import SeeleseekCore

/// Lock-protected counter for cross-actor handler-invocation accounting.
/// Built on `Mutex` so its API is `nonisolated`/`Sendable` regardless of
/// the surrounding suite's actor isolation. `final class` (not struct)
/// because `Mutex` is non-Copyable.
nonisolated private final class FireCounter: Sendable {
    private let state = Mutex(0)
    var value: Int { state.withLock { $0 } }
    func bump() { state.withLock { $0 += 1 } }
}

/// Regression tests for `ShareManager.countsChangesStream()` and the
/// debounce/fan-out behavior of `notifyCountsChanged`.
///
/// Background: at login, `NetworkClient` broadcasts `SharedFoldersFiles`
/// using `ShareManager.totalFiles`. The disk rescan that populates the
/// index runs concurrently with login and almost always loses the race —
/// the broadcast goes out as `(0, 0)` and the server keeps reporting
/// "0 shared files" to every peer until something forces a re-broadcast.
/// `NetworkClient` subscribes via `countsChangesStream()` so a freshly
/// completed rescan (or add/remove) triggers `updateShareCounts`. These
/// tests pin the contract: per-subscriber stream allocation, multi-
/// consumer fan-out, the 200 ms debounce that coalesces bulk operations,
/// and the AsyncStream buffering that fixes the subscribe-before-publish
/// race that the previous closure-dict version was vulnerable to.
///
/// The tests sleep just past the debounce window (350 ms) before
/// asserting fire counts — the contract is "trailing-edge yield after
/// the last event," so observation has to wait for that edge.
@MainActor
@Suite("ShareManager count-change notifications")
struct ShareCountNotificationTests {

    /// Slack on the 200 ms debounce so loaded CI machines don't flake.
    private static let debounceWaitMillis = 350

    /// Subscribe to `countsChangesStream()` and feed each yield into the
    /// caller's `FireCounter`. Returns the consumer Task so the test can
    /// cancel it on teardown — uncancelled streams keep the continuation
    /// (and hence the ShareManager) alive past the test's lifetime.
    private func consume(_ shares: ShareManager, into counter: FireCounter) -> Task<Void, Never> {
        Task {
            for await _ in shares.countsChangesStream() {
                counter.bump()
            }
        }
    }

    @Test("rescanAll fires each subscriber exactly once")
    func rescanAllFiresSubscribers() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "rescanAll must trigger one trailing-edge yield")
    }

    @Test("removeFolder fires subscribers")
    func removeFolderFiresSubscribers() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }

        // Synthetic folder — never added, so the removeAll calls are
        // no-ops, but the notification path is the same shape.
        let folder = ShareManager.SharedFolder(path: "/nonexistent/path")
        shares.removeFolder(folder)
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1)
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

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(a.value == 1, "first subscriber must fire")
        #expect(b.value == 1, "second subscriber must fire — vanilla AsyncStream is single-consumer; fan-out is implemented by ShareManager")
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
        try? await Task.sleep(for: .milliseconds(50))

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(cancelled.value == 0, "cancelled subscriber must not fire")
        #expect(kept.value == 1, "remaining subscriber must still fire")
    }

    @Test("Rapid changes coalesce into a single trailing-edge yield (debounce)")
    func rapidChangesDebounce() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }

        // Five rescans back-to-back. Each notifyCountsChanged cancels the
        // prior debounce Task and arms a fresh 200 ms timer; only the
        // last one survives to yield. Without the debounce we'd see 5
        // broadcasts to the server for what is logically one batch.
        for _ in 0..<5 {
            await shares.rescanAll()
        }
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "5 rapid changes must coalesce into 1 yield")
    }

    @Test("Subscriber created BEFORE rescan still observes the trailing yield")
    func subscribeBeforePublishObservesYield() async {
        // The whole point of switching to AsyncStream: the buffer covers
        // the case where the consumer Task is created but hasn't yet
        // entered `for await` when the yield fires. With the old
        // closure-dict, a yield before the handler was registered was
        // silently dropped; here, the continuation buffer holds it until
        // the loop drains. We approximate the race by spawning the
        // consumer Task and immediately publishing without yielding the
        // actor — the consumer can't possibly have started executing
        // its loop body yet.
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }

        // No `Task.yield()` between consume() and rescanAll() — we want
        // the publish to happen before the consumer's for-await loop is
        // running.
        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "buffered yield must reach the consumer once it starts iterating")
    }

    @Test("loadPersistedFolders does not yield on its own (no implicit rescan)")
    func loadPersistedFoldersIsSilent() async {
        let shares = ShareManager()
        let counter = FireCounter()
        let task = consume(shares, into: counter)
        defer { task.cancel() }

        // Pre-refactor `ShareManager.init` auto-spawned a rescan via load();
        // load is now an explicit, side-effect-free call. Calling it
        // alone must NOT fire the stream — only an actual count change
        // (rescan / add / remove) does.
        shares.loadPersistedFolders()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 0, "loadPersistedFolders must not yield — it doesn't change the file index")
    }
}
