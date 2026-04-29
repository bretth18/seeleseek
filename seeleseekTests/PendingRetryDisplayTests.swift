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

    private func makeFailed(error: String? = nil, nextRetryAt: Date? = nil) -> Transfer {
        Transfer(
            username: "alice",
            filename: "song.mp3",
            size: 1024,
            direction: .download,
            status: .failed,
            error: error,
            nextRetryAt: nextRetryAt
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

    // MARK: - Live countdown from nextRetryAt

    @Test("nextRetryAt drives a live countdown that ticks down")
    func nextRetryAtDrivesLiveCountdown() {
        let now = Date()
        let t = makeFailed(nextRetryAt: now.addingTimeInterval(125))
        // 125s from `now` → "2m 5s"
        #expect(t.retryCountdownString(now: now) == "2m 5s")
        // 60s later → "1m 5s"
        #expect(t.retryCountdownString(now: now.addingTimeInterval(60)) == "1m 5s")
        // Past the deadline → "now"
        #expect(t.retryCountdownString(now: now.addingTimeInterval(200)) == "now")
    }

    @Test("hasScheduledRetry only true when both .failed and nextRetryAt is set")
    func hasScheduledRetryGate() {
        let now = Date()
        let stamped = makeFailed(nextRetryAt: now.addingTimeInterval(60))
        #expect(stamped.hasScheduledRetry == true)
        #expect(stamped.isPendingRetry == true)

        let unstamped = makeFailed()
        #expect(unstamped.hasScheduledRetry == false)

        var queued = makeFailed(nextRetryAt: now.addingTimeInterval(60))
        queued.status = .queued
        #expect(queued.hasScheduledRetry == false, "non-failed status invalidates the schedule")
    }

    @Test("retryCountdownString falls back to legacy pendingRetryDelay when nextRetryAt is nil")
    func legacyFallback() {
        let t = makeFailed(error: "Retrying in 30s...")
        // No nextRetryAt: falls back to the static format-string delay
        // for pre-v8 rows that haven't been re-scheduled yet.
        #expect(t.retryCountdownString() == "30s")
    }

    @Test("formatRetryCountdown produces the same units the manager stamps",
          arguments: [
            (5.0, "5s"),
            (30.0, "30s"),
            (59.0, "59s"),
            (60.0, "1m"),
            (90.0, "1m 30s"),
            (120.0, "2m"),
            (3600.0, "1h"),
            (3660.0, "1h 1m"),
          ] as [(TimeInterval, String)])
    func formatCountdownUnits(seconds: TimeInterval, expected: String) {
        #expect(Transfer.formatRetryCountdown(seconds) == expected)
    }
}
