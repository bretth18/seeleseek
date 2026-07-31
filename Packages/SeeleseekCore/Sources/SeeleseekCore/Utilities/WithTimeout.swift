import Foundation

/// Race `operation` against a `seconds` deadline.
///
/// The group awaits both children before returning, so this only bounds the
/// caller's wait if `operation` responds to cancellation. An operation that
/// ignores it silently un-bounds every caller of this function.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw NetworkError.timeout
        }
        guard let result = try await group.next() else {
            throw NetworkError.timeout
        }
        group.cancelAll()
        return result
    }
}
