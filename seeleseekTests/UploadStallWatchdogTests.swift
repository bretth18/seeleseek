import Testing
import Foundation
import Synchronization
@testable import SeeleseekCore

/// Lock-protected boolean for cross-actor signalling. Built on
/// `Mutex` so its API is `nonisolated`/`Sendable` regardless of the
/// surrounding suite's actor isolation. `final class` (not struct)
/// because `Mutex` is non-Copyable.
nonisolated private final class StallTestFlag: Sendable {
    private let state = Mutex(false)
    var fired: Bool { state.withLock { $0 } }
    func markFired() { state.withLock { $0 = true } }
}

/// Regression tests for `UploadManager.sendChunkWithTimeout` — the
/// per-chunk stall watchdog that wraps every `connection.send` in the
/// upload loop. Without it, a TCP-wedged peer could leave a transfer
/// frozen at e.g. 30% indefinitely because `NWConnection.send` waits
/// forever for a callback that never fires. The helper races the send
/// against a `Task.sleep` and throws `UploadError.timeout` if the send
/// hasn't completed by the deadline. The error string ("Transfer timed
/// out") is retriable per the classifier — see UploadRetryClassifierTests.
@MainActor
@Suite("UploadManager send-chunk stall watchdog")
struct UploadStallWatchdogTests {

    @Test("Returns normally when the send finishes within the threshold")
    func fastSendCompletes() async throws {
        let manager = UploadManager()
        try await manager.sendChunkWithTimeout(1.0, onTimeout: {}) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Throws UploadError.timeout when the send hangs past the threshold")
    func slowSendTimesOut() async {
        let manager = UploadManager()
        do {
            try await manager.sendChunkWithTimeout(0.1, onTimeout: {}) {
                try await Task.sleep(for: .seconds(2))
            }
            Issue.record("Expected timeout to throw")
        } catch UploadManager.UploadError.timeout {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Inner send error propagates instead of being masked by the timeout")
    func sendErrorPropagates() async {
        struct SendFailed: Error {}
        let manager = UploadManager()
        do {
            try await manager.sendChunkWithTimeout(1.0, onTimeout: {}) {
                throw SendFailed()
            }
            Issue.record("Expected the inner error to propagate")
        } catch is SendFailed {
            // expected — the watchdog must not swallow real send errors
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("onTimeout fires when the send hangs past the threshold")
    func onTimeoutFires() async {
        let manager = UploadManager()
        let flag = StallTestFlag()
        do {
            try await manager.sendChunkWithTimeout(0.1, onTimeout: { flag.markFired() }) {
                try await Task.sleep(for: .seconds(2))
            }
            Issue.record("Expected timeout to throw")
        } catch UploadManager.UploadError.timeout {
            // `withTaskCancellationHandler`'s onCancel runs asynchronously
            // when cancellation is signalled — it isn't guaranteed to have
            // completed by the time the parent throw propagates back here.
            // Locally the race usually goes our way; on a contended CI
            // runner it doesn't, which produced an intermittent failure
            // on the first PR push. Poll for up to ~1 s so the assertion
            // tests the *contract* (handler eventually fires), not a
            // particular scheduler ordering.
            for _ in 0..<100 {
                if flag.fired { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(flag.fired, "onTimeout must fire so the underlying connection is dropped")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
