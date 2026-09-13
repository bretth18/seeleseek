import Foundation

/// Backoff bookkeeping shared by `DownloadManager` and `UploadManager`.
/// Owned by one actor and never escapes it, so it carries no isolation of
/// its own.
final class TransferRetryScheduler {
    /// 10s, 30s, 2m, 10m, 30m. The length caps the retry count.
    static let delays: [TimeInterval] = [10, 30, 120, 600, 1800]
    static var maxRetries: Int { delays.count }

    private var pending: [UUID: Task<Void, Never>] = [:]

    /// Retry-by-default: with the count capped at `maxRetries` an over-eager
    /// retry is bounded, whereas an allowlist of transient substrings missed
    /// common reasons ("Not connected to server", "Operation canceled") and
    /// left rows dead until the next login. Only explicit peer-side
    /// decisions that re-asking won't change are terminal. The bare
    /// "cancel" stem must stay out: it also matches the client's own
    /// transient teardown strings.
    static func isRetriableError(_ error: String?) -> Bool {
        guard let lowered = error?.lowercased(), !lowered.isEmpty else {
            return false
        }
        let terminalPatterns = [
            "denied",
            "not shared",
            "not available",
            "file not found",
            "too many",
            "banned",
            "blocked",
            "disallowed",
            "pending shutdown",
        ]
        return !terminalPatterns.contains { lowered.contains($0) }
    }

    /// Format contract `TransferRow` parses for the "Retrying in 2m" badge.
    static func retryingErrorText(delay: TimeInterval) -> String {
        let seconds = Int(delay)
        let text = seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
        return "Retrying in \(text)..."
    }

    /// Delay before attempt number `retryCount + 1`, or nil once the ladder
    /// is exhausted.
    func delay(forRetryCount retryCount: Int) -> TimeInterval? {
        retryCount < Self.delays.count ? Self.delays[retryCount] : nil
    }

    func isPending(_ id: UUID) -> Bool { pending[id] != nil }

    func task(for id: UUID) -> Task<Void, Never>? { pending[id] }

    /// Sleep `delay`, then run `fire`. Any prior task for `id` is cancelled
    /// first: overwriting the slot alone leaves the orphan sleeping, and it
    /// could fire later.
    func schedule(_ id: UUID, after delay: TimeInterval, fire: @escaping @Sendable () async -> Void) {
        pending.removeValue(forKey: id)?.cancel()
        pending[id] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await fire()
        }
    }

    /// Forget the task for `id` without cancelling it. Called by the fired
    /// task itself.
    func clear(_ id: UUID) {
        pending.removeValue(forKey: id)
    }

    @discardableResult
    func cancel(_ id: UUID) -> Bool {
        guard let task = pending.removeValue(forKey: id) else { return false }
        task.cancel()
        return true
    }

    /// Re-arm rows that were mid-backoff when the app last quit. Past-due
    /// rows fire with a 0.5s per-row stagger so 50 pending retries don't
    /// flood the network on launch; future rows keep their original
    /// schedule. Returns the number of rows armed.
    func rearm(_ transfers: [Transfer], now: Date = Date(), fire: @escaping @Sendable (Transfer) async -> Void) -> Int {
        let candidates = transfers.filter {
            $0.status == .failed && $0.nextRetryAt != nil && $0.retryCount < Self.maxRetries
        }
        for (index, transfer) in candidates.enumerated() {
            guard let fireAt = transfer.nextRetryAt else { continue }
            let remaining = fireAt.timeIntervalSince(now)
            let stagger = remaining <= 0 ? Double(index) * 0.5 : 0
            schedule(transfer.id, after: max(0, remaining) + stagger) { await fire(transfer) }
        }
        return candidates.count
    }
}
