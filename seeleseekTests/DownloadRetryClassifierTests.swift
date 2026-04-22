import Testing
import Foundation
@testable import SeeleseekCore

/// Regression tests for `DownloadManager.isRetriableError`.
///
/// The old implementation used a narrow allowlist of substrings
/// ("timeout", "connection", "network", "unreachable", "firewall",
/// "incomplete") and returned false on the default path, so any
/// `NWError` / `NetworkError` string that didn't happen to contain one
/// of those tokens silently became non-retriable. The new implementation
/// retries by default and only rejects known user/peer-stop reasons.
@Suite("DownloadManager retry classifier")
struct DownloadRetryClassifierTests {

    // MARK: - Regressions: errors that the old classifier missed

    @Test("NetworkError.notConnected's description retries",
          arguments: ["Not connected to server"])
    func notConnectedRetries(message: String) {
        #expect(DownloadManager.isRetriableError(message) == true)
    }

    @Test("NWError canceled (American spelling) is treated as user cancel",
          arguments: [
            "Operation canceled",
            "The operation couldn’t be completed. (Network.NWError error 89 - Operation canceled)",
          ])
    func canceledIsTerminal(message: String) {
        #expect(DownloadManager.isRetriableError(message) == false)
    }

    @Test("British 'cancelled' is still treated as terminal")
    func cancelledIsTerminal() {
        #expect(DownloadManager.isRetriableError("Cancelled by user") == false)
    }

    @Test("Timed-out phrasing retries even without the 'timeout' token",
          arguments: [
            "The request timed out",
            "Connection timed out",
          ])
    func timedOutRetries(message: String) {
        #expect(DownloadManager.isRetriableError(message) == true)
    }

    @Test("Host-level failures retry",
          arguments: [
            "Host is down",
            "No route to host",
          ])
    func hostFailuresRetry(message: String) {
        #expect(DownloadManager.isRetriableError(message) == true)
    }

    // MARK: - Terminal reasons

    @Test("Peer-driven stop reasons are not retried",
          arguments: [
            "Access denied",
            "File not shared",
            "File not found",
            "File not available",
            "Too many queued uploads",
          ])
    func peerStopReasonsAreTerminal(message: String) {
        #expect(DownloadManager.isRetriableError(message) == false)
    }

    // MARK: - Edge cases

    @Test("Nil or empty errors don't retry")
    func nilOrEmptyIsNonRetriable() {
        #expect(DownloadManager.isRetriableError(nil) == false)
        #expect(DownloadManager.isRetriableError("") == false)
    }

    @Test("Unknown error messages retry by default")
    func unknownRetries() {
        #expect(DownloadManager.isRetriableError("Something went wrong") == true)
        #expect(DownloadManager.isRetriableError("EOFException at byte 1024") == true)
    }
}
