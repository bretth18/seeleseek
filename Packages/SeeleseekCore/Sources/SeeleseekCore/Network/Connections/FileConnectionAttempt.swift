import Foundation
import Network
import Synchronization

enum FileConnectAttempt {
    case ready(NWConnection)
    case failed(NWConnection)
    case bindFailed(NWConnection)
}

extension UploadManager {
    static func attemptFileConnect(
        to endpoint: NWEndpoint,
        bindTo localPort: UInt16?,
        timeout: Duration = .seconds(30)
    ) async -> FileConnectAttempt {
        let params = PeerConnection.makeOutboundParameters(bindTo: localPort, remoteEndpoint: endpoint)
        let connection = NWConnection(to: endpoint, using: params)

        let hasResumed = Mutex(false)
        let timeoutTask = Mutex<Task<Void, Never>?>(nil)
        // First claimant wins; everyone else's events are ignored.
        let claimResume: @Sendable () -> Bool = {
            hasResumed.withLock { old in
                guard !old else { return false }
                old = true
                return true
            }
        }
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard claimResume() else { return }
                    timeoutTask.withLock { $0?.cancel() }
                    continuation.resume(returning: .ready(connection))
                case .failed(let error):
                    guard claimResume() else { return }
                    timeoutTask.withLock { $0?.cancel() }
                    // No caller uses the socket from failure outcomes;
                    // cancel it here so it doesn't leak.
                    connection.cancel()
                    if PeerConnection.isBindFailure(error) {
                        continuation.resume(returning: .bindFailed(connection))
                    } else {
                        continuation.resume(returning: .failed(connection))
                    }
                case .cancelled:
                    guard claimResume() else { return }
                    timeoutTask.withLock { $0?.cancel() }
                    continuation.resume(returning: .failed(connection))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            let task = Task {
                try? await Task.sleep(for: timeout)
                guard claimResume() else { return }
                connection.cancel()
                continuation.resume(returning: .failed(connection))
            }
            timeoutTask.withLock { $0 = task }
        }
    }
}
