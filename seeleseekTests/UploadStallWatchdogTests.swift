import Testing
import Foundation
@testable import SeeleseekCore

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
        try await manager.sendChunkWithTimeout(1.0) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Throws UploadError.timeout when the send hangs past the threshold")
    func slowSendTimesOut() async {
        let manager = UploadManager()
        do {
            try await manager.sendChunkWithTimeout(0.1) {
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
            try await manager.sendChunkWithTimeout(1.0) {
                throw SendFailed()
            }
            Issue.record("Expected the inner error to propagate")
        } catch is SendFailed {
            // expected — the watchdog must not swallow real send errors
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
