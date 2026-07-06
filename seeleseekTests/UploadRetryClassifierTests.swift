import Testing
import Foundation
@testable import SeeleseekCore

/// Regression tests for `UploadManager.isRetriableError`.
///
/// Same shape as `DownloadRetryClassifierTests` — the upload classifier
/// mirrors the download one so both halves of the transfer system use the
/// same backoff and the same set of terminal patterns. If you add a
/// terminal pattern to either, add the matching test to both files.
@Suite("UploadManager retry classifier")
struct UploadRetryClassifierTests {

    // MARK: - Retriable

    @Test("Connection / network errors retry",
          arguments: [
            "Peer disconnected",
            "Failed to connect to peer",
            "Peer connection timeout (firewall)",
            "Peer unreachable (firewall)",
            "Timeout waiting for peer response",
            "Failed to initiate file transfer",
            "Failed to start file transfer",
            "Connection reset by peer",
            // Stall watchdog produces this when a per-chunk send hangs
            // longer than the threshold. Must be retriable so the row
            // doesn't get stuck after a wedged TCP write.
            "Transfer timed out",
          ])
    func networkErrorsRetry(message: String) {
        #expect(UploadManager.isRetriableError(message) == true)
    }

    @Test("Unknown reason text retries by default")
    func unknownRetries() {
        #expect(UploadManager.isRetriableError("Out of disk space") == true)
        #expect(UploadManager.isRetriableError("Unexpected error") == true)
    }

    // The bare "cancel" stem was removed from the upload classifier (same
    // fix as the download side): NWError/POSIX teardown surfaces as
    // "Operation canceled" / "Connection was cancelled", i.e. transient
    // failures. Genuine cancels never reach the classifier —
    // `cancelledTransferIds` + the `.cancelled` status guard in
    // `failUpload` short-circuit user cancels, and peer "Cancelled"
    // rejections map to `.cancelled` via `status(forReject:)`.
    @Test("Canceled strings are transient teardown, not user cancel",
          arguments: [
            "Operation canceled",
            "The operation couldn’t be completed. (Network.NWError error 89 - Operation canceled)",
            "Connection was cancelled",
          ])
    func canceledIsRetriable(message: String) {
        #expect(UploadManager.isRetriableError(message) == true)
    }

    // MARK: - Terminal

    @Test("Peer-side stop reasons are not retried",
          arguments: [
            "Access denied",
            "File not shared",
            "File not found",
            "File not available",
            "Too many queued uploads",
            // Closed in the second-pass classifier audit. Retrying these
            // wastes the full ladder for a transfer that has zero chance
            // of succeeding.
            "Banned by uploader",
            "Banned",
            "Blocked country",
            "Disallowed extension",
            "Pending shutdown.",
        ])
    func peerStopReasonsAreTerminal(message: String) {
        #expect(UploadManager.isRetriableError(message) == false)
    }

    @Test("Nil or empty errors don't retry")
    func nilOrEmptyIsNonRetriable() {
        #expect(UploadManager.isRetriableError(nil) == false)
        #expect(UploadManager.isRetriableError("") == false)
    }
}
