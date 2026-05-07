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

        for _ in 0..<5 {
            await shares.rescanAll()
        }
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "5 rapid changes must coalesce into 1 yield")
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
