import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Locks in the format contract between the retry schedulers and the row.
/// `DownloadManager.scheduleRetry` and `UploadManager.scheduleUploadRetry`
/// stamp `transfer.error` as `"Retrying in <delay>..."`, and the row's
/// pending-retry display parses that string back. If either side drifts
/// these tests fail loudly instead of the row silently falling back to
/// red "Failed".
@MainActor
@Suite("Transfer pending-retry display helpers")
struct PendingRetryDisplayTests {

    private func makeFailed(error: String?) -> Transfer {
        Transfer(
            username: "alice",
            filename: "song.mp3",
            size: 1024,
            direction: .download,
            status: .failed,
            error: error
        )
    }

    @Test("Manager-stamped 'Retrying in 2m...' is detected as pending")
    func detectsManagerString() {
        let t = makeFailed(error: "Retrying in 2m...")
        #expect(t.isPendingRetry == true)
        #expect(t.pendingRetryDelay == "2m")
    }

    @Test("Seconds-scale delays parse",
          arguments: ["Retrying in 30s...", "Retrying in 30s"])
    func parsesSecondsDelay(message: String) {
        let t = makeFailed(error: message)
        #expect(t.isPendingRetry == true)
        #expect(t.pendingRetryDelay == "30s")
    }

    @Test("A plain failure is not pending-retry")
    func plainFailureNotPending() {
        let t = makeFailed(error: "Peer unreachable (firewall)")
        #expect(t.isPendingRetry == false)
        #expect(t.pendingRetryDelay == nil)
    }

    @Test("nil and empty errors are not pending-retry")
    func nilOrEmptyNotPending() {
        #expect(makeFailed(error: nil).isPendingRetry == false)
        #expect(makeFailed(error: "").isPendingRetry == false)
    }

    @Test("Non-failed status is never pending-retry, even with the prefix")
    func nonFailedStatusNotPending() {
        // Defensive: scheduler only stamps the string while in .failed,
        // but the helper still gates on status so a stale string on a
        // re-queued row doesn't light up the badge.
        var t = makeFailed(error: "Retrying in 1m...")
        t.status = .queued
        #expect(t.isPendingRetry == false)
    }
}
