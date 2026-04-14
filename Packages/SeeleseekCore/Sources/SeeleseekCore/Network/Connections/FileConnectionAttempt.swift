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
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard hasResumed.withLock({ old in
                        guard !old else { return false }
                        old = true
                        return true
                    }) else { return }
                    continuation.resume(returning: .ready(connection))
                case .failed(let error):
                    guard hasResumed.withLock({ old in
                        guard !old else { return false }
                        old = true
                        return true
                    }) else { return }
                    if PeerConnection.isBindFailure(error) {
                        continuation.resume(returning: .bindFailed(connection))
                    } else {
                        continuation.resume(returning: .failed(connection))
                    }
                case .cancelled:
                    guard hasResumed.withLock({ old in
                        guard !old else { return false }
                        old = true
                        return true
                    }) else { return }
                    continuation.resume(returning: .failed(connection))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(for: timeout)
                guard hasResumed.withLock({ old in
                    guard !old else { return false }
                    old = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(returning: .failed(connection))
            }
        }
    }
}
