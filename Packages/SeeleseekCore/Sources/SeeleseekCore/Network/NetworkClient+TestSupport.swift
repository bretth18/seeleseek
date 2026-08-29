import Foundation

// MARK: - Test Support
//
// `internal` seams for seeleseekTests: register waiters, seed
// establishment/distributed fixtures, and drive teardown paths without a
// live server. Nothing here runs in production flows.
extension NetworkClient {
    /// Test-only: register a waiter without kicking off a server round-trip.
    /// Used to exercise the multi-waiter / timeout path independently of a
    /// live connection.
    internal func _awaitPeerAddressWaiter(
        for username: String,
        timeout: Duration
    ) async throws -> (ip: String, port: Int, obfuscatedPort: Int) {
        let requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pendingPeerAddressRequests[username, default: []].append(
                (continuation: continuation, requestID: requestID)
            )
            Task {
                try? await Task.sleep(for: timeout)
                guard var waiters = self.pendingPeerAddressRequests[username] else { return }
                guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
                let waiter = waiters.remove(at: idx)
                if waiters.isEmpty {
                    self.pendingPeerAddressRequests.removeValue(forKey: username)
                } else {
                    self.pendingPeerAddressRequests[username] = waiters
                }
                waiter.continuation.resume(throwing: NetworkError.timeout)
            }
        }
    }

    /// Test-only: attach a waiter to `pendingStatusRequests` without
    /// sending a server round-trip. Used to exercise the multi-waiter
    /// coalescing and teardown paths independently of a live connection.
    internal func _awaitStatusWaiter(
        for username: String,
        timeout: Duration
    ) async -> (status: UserStatus, privileged: Bool) {
        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            pendingStatusRequests[username, default: []]
                .append((continuation: continuation, requestID: requestID))
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expireStatusRequest(username: username, requestID: requestID)
            }
        }
    }

    /// Test-only: run the full disconnect peer-operation teardown without
    /// needing a live server connection. Returns when every pending waiter
    /// has been resolved (either thrown or resumed with `.offline`).
    internal func _failAllPendingPeerOperationsForTest(reason: String = "test") {
        failAllPendingPeerOperations(reason: reason)
    }

    /// Test-only: register a sentinel establishment task and return its
    /// handle. The task is a never-returning `await` — the test can
    /// confirm that disconnect-driven cancellation propagates into a
    /// real in-flight handshake by checking that the handle throws
    /// CancellationError afterwards.
    internal func _seedSentinelEstablishmentForTest(username: String) -> Task<PeerConnection, Error> {
        let task = Task<PeerConnection, Error> {
            // Sleep essentially forever until cancelled.
            try await Task.sleep(for: .seconds(3600))
            throw NetworkError.timeout
        }
        pendingEstablishments[username] = task
        return task
    }

    /// Test-only: attach a distributed child socket placeholder so tests
    /// can confirm `clearDistributedState` wipes it on teardown. We store
    /// a real idle PeerConnection so the disconnect call is exercised.
    internal func _seedDistributedChildForTest() -> PeerConnection {
        let info = PeerConnection.PeerInfo(username: "child", ip: "127.0.0.1", port: 1)
        let child = PeerConnection(peerInfo: info, type: .distributed, token: 0)
        distributedChildren.append(child)
        distributedBranchLevel = 5
        distributedBranchRoot = "root"
        return child
    }

    internal func _distributedChildCountForTest() -> Int {
        distributedChildren.count
    }

    internal func _distributedBranchLevelForTest() -> UInt32 {
        distributedBranchLevel
    }

    /// Test-only: run the peer-teardown half of `performDisconnect`
    /// (disconnectAll + distributed clear) without touching the server
    /// connection or listener. Matches what the real teardown Task does.
    internal func _runDisconnectTeardownForTest() async {
        await peerConnectionPool.disconnectAll()
        await clearDistributedState()
    }

    /// Test-only: shorten the real reconnect scheduler without replacing it.
    internal func _setReconnectDelayForTest(_ delay: TimeInterval?) {
        reconnectDelayOverrideForTesting = delay
    }

    /// Test-only: keep loopback reconnect tests off the real LAN/WAN.
    internal func _setSkipNATSetupForTest(_ skip: Bool) {
        skipNATSetupForTesting = skip
    }

    /// Test-only: expose the production backoff calculation.
    internal static func _reconnectDelayForTest(failedAttempts: Int) -> TimeInterval {
        reconnectDelay(afterFailedAttempts: failedAttempts)
    }

    /// Test-only: register an artwork waiter directly without a peer
    /// connection. Returns the key used internally so tests can drive
    /// `_deliverArtworkForTest`.
    internal func _registerArtworkWaiterForTest(
        username: String,
        filePath: String,
        completion: @Sendable @escaping (Data?) -> Void
    ) -> String {
        let key = Self.artworkKey(username: username, filePath: filePath)
        if pendingArtworkRequests[key] != nil {
            pendingArtworkRequests[key]?.waiters.append(completion)
        } else {
            pendingArtworkRequests[key] = PendingArtworkRequest(
                token: UInt32.random(in: 1..<0x8000_0000),
                waiters: [completion]
            )
        }
        return key
    }

    internal func _deliverArtworkForTest(key: String, data: Data?) {
        deliverArtwork(key: key, data: data)
    }

    internal func _pendingArtworkWaiterCount(key: String) -> Int {
        pendingArtworkRequests[key]?.waiters.count ?? 0
    }
}
