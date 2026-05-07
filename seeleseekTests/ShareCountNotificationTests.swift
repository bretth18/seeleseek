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

/// Regression tests for the share-count notification hook on `ShareManager`.
///
/// Background: at login, `NetworkClient` broadcasts `SharedFoldersFiles`
/// using `ShareManager.totalFiles`. The disk rescan that populates the
/// index runs concurrently with login and almost always loses the race —
/// the broadcast goes out as `(0, 0)` and the server keeps reporting
/// "0 shared files" to every peer until something forces a re-broadcast.
/// `NetworkClient` subscribes via `addCountsChangedHandler` so a freshly
/// completed rescan (or add/remove) triggers `updateShareCounts`. These
/// tests pin the hook's contract: subscribe/unsubscribe semantics,
/// multi-handler dispatch, and the 200 ms debounce that coalesces bulk
/// operations into a single fire.
///
/// The tests sleep just past the debounce window (300 ms) before
/// asserting fire counts — the contract is "trailing-edge fire after the
/// last event," so observation has to wait for that edge.
@MainActor
@Suite("ShareManager count-change notifications")
struct ShareCountNotificationTests {

    /// Slack on the 200 ms debounce so loaded CI machines don't flake.
    private static let debounceWaitMillis = 350

    /// Build a `ShareManager` and absorb any notification fired by the
    /// implicit auto-rescan that `init` kicks off via `load()`. A previous
    /// test process can leave persisted folders in `UserDefaults`, in
    /// which case `load()` decodes them and spawns
    /// `Task { await rescanAll() }` — that rescan eventually calls
    /// `notifyCountsChanged()`. If we subscribed before that fire we'd
    /// double-count it. Subscribing AFTER the init-time debounce window
    /// has passed leaves the handler dictionary empty during the
    /// init-fire and gives every test a clean baseline.
    private func makeQuiescedManager() async -> ShareManager {
        let shares = ShareManager()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))
        return shares
    }

    @Test("rescanAll fires registered handlers exactly once")
    func rescanAllFiresHandlers() async {
        let shares = await makeQuiescedManager()
        let counter = FireCounter()
        _ = shares.addCountsChangedHandler { counter.bump() }

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "rescanAll must trigger one trailing-edge fire")
    }

    @Test("removeFolder fires registered handlers")
    func removeFolderFiresHandlers() async {
        let shares = await makeQuiescedManager()
        let counter = FireCounter()
        _ = shares.addCountsChangedHandler { counter.bump() }

        // Synthetic folder — never added, so the removeAll calls are
        // no-ops, but the notification path is the same shape.
        let folder = ShareManager.SharedFolder(path: "/nonexistent/path")
        shares.removeFolder(folder)
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1)
    }

    @Test("Multiple subscribers all fire on a single change")
    func multipleSubscribersFire() async {
        let shares = await makeQuiescedManager()
        let a = FireCounter()
        let b = FireCounter()
        _ = shares.addCountsChangedHandler { a.bump() }
        _ = shares.addCountsChangedHandler { b.bump() }

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(a.value == 1, "first subscriber must fire")
        #expect(b.value == 1, "second subscriber must fire — single-closure overwrite would leave this at 0")
    }

    @Test("removeCountsChangedHandler stops firing for that handler only")
    func removingHandlerStopsFiring() async {
        let shares = await makeQuiescedManager()
        let removed = FireCounter()
        let kept = FireCounter()
        let removedID = shares.addCountsChangedHandler { removed.bump() }
        _ = shares.addCountsChangedHandler { kept.bump() }

        shares.removeCountsChangedHandler(removedID)

        await shares.rescanAll()
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(removed.value == 0, "unsubscribed handler must not fire")
        #expect(kept.value == 1, "remaining handler must still fire")
    }

    @Test("Rapid changes coalesce into a single trailing-edge fire (debounce)")
    func rapidChangesDebounce() async {
        let shares = await makeQuiescedManager()
        let counter = FireCounter()
        _ = shares.addCountsChangedHandler { counter.bump() }

        // Five rescans back-to-back. Each notifyCountsChanged cancels the
        // prior debounce Task and arms a fresh 200 ms timer; only the
        // last one survives to fire. Without the debounce we'd see 5
        // broadcasts to the server for what is logically one batch.
        for _ in 0..<5 {
            await shares.rescanAll()
        }
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 1, "5 rapid changes must coalesce into 1 fire")
    }

    @Test("Late subscriber added after a fire does not retroactively run")
    func lateSubscriberSkipsPriorFire() async {
        let shares = await makeQuiescedManager()
        await shares.rescanAll()
        // Wait past the debounce so the prior trailing-edge fire (if any
        // unobserved subscribers existed) has already happened.
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        let counter = FireCounter()
        _ = shares.addCountsChangedHandler { counter.bump() }
        // No further changes; handler should sit idle.
        try? await Task.sleep(for: .milliseconds(Self.debounceWaitMillis))

        #expect(counter.value == 0, "subscribers only fire on changes after they're registered")
    }
}
