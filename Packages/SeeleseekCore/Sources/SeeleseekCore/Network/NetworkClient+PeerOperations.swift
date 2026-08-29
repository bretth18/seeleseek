import Foundation

// MARK: - Outbound Peer Operations
//
// The client-initiated peer workflows: address/status lookups, browse,
// connection establishment (the ConnectToPeer + direct/indirect race),
// user-info fetch, artwork fetch, and folder-contents requests. All of the
// pending-continuation state these methods drive is stored on the actor in
// NetworkClient.swift (stored properties cannot live in extensions);
// `failAllPendingPeerOperations` at the bottom is the disconnect-time
// teardown that must cover every pending dict used here.
extension NetworkClient {
    // MARK: - Peer Address Response Handling

    /// Resumes pending `getPeerAddress` waiters and publishes the event.
    public func handlePeerAddressResponse(username: String, ip: String, port: Int, obfuscatedPort: Int = 0) {
        logger.debug("handlePeerAddressResponse: \(username) @ \(ip):\(port) obfuscatedPort=\(obfuscatedPort)")

        if let waiters = pendingPeerAddressRequests.removeValue(forKey: username) {
            logger.debug("Resuming \(waiters.count) pending getPeerAddress continuation(s) for \(username)")
            for waiter in waiters {
                waiter.continuation.resume(returning: (ip, port, obfuscatedPort))
            }
        }

        emit(.peerAddress(username: username, ip: ip, port: port))
    }

    /// Request peer address and wait for response (concurrent-safe)
    /// Can be called from multiple places concurrently - each request gets its own continuation
    public func getPeerAddress(for username: String, timeout: Duration = .seconds(10)) async throws -> (ip: String, port: Int, obfuscatedPort: Int) {
        let requestID = UUID()
        let alreadyInFlight = (pendingPeerAddressRequests[username]?.isEmpty == false)

        return try await withCheckedThrowingContinuation { continuation in
            pendingPeerAddressRequests[username, default: []].append(
                (continuation: continuation, requestID: requestID)
            )

            if !alreadyInFlight {
                Task {
                    do {
                        try await self.getUserAddress(username)
                    } catch {
                        if let waiters = self.pendingPeerAddressRequests.removeValue(forKey: username) {
                            for waiter in waiters {
                                waiter.continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }

            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expirePeerAddressRequest(username: username, requestID: requestID)
            }
        }
    }

    /// Timeout path for `getPeerAddress` — fail a still-pending waiter.
    private func expirePeerAddressRequest(username: String, requestID: UUID) {
        guard var waiters = pendingPeerAddressRequests[username] else { return }
        guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
        let waiter = waiters.remove(at: idx)
        if waiters.isEmpty {
            pendingPeerAddressRequests.removeValue(forKey: username)
        } else {
            pendingPeerAddressRequests[username] = waiters
        }
        waiter.continuation.resume(throwing: NetworkError.timeout)
    }

    /// Check if a user is online before attempting to connect.
    /// Returns the user's status (offline, away, online) with a timeout.
    /// Concurrent callers for the same username are coalesced onto one
    /// server round-trip — all attach continuations to the same pending
    /// entry and receive the same reply.
    public func checkUserOnlineStatus(_ username: String, timeout: TimeInterval = 5.0) async throws -> (status: UserStatus, privileged: Bool) {
        guard isConnected else { throw NetworkError.notConnected }
        let connection = try requireConnectedServerConnection()

        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            // Check-and-register in one synchronous block (no await in
            // between): computing the in-flight flag before an await let a
            // concurrent caller slip in and trigger a duplicate
            // GetUserStatus send.
            let alreadyInFlight = (pendingStatusRequests[username]?.isEmpty == false)
            pendingStatusRequests[username, default: []]
                .append((continuation: continuation, requestID: requestID))

            if alreadyInFlight {
                logger.debug("Coalescing status check for \(username) onto in-flight request")
            } else {
                logger.info("Checking online status for: \(username)")
                Task {
                    do {
                        let message = MessageBuilder.getUserStatusMessage(username: username)
                        try await connection.send(message)
                    } catch {
                        // The continuation is non-throwing; a failed send
                        // degrades to the per-caller timeout below, which
                        // resolves as .offline.
                        self.logger.warning("GetUserStatus send failed for \(username): \(error.localizedDescription)")
                    }
                }
            }

            // Per-caller timeout — removes exactly this waiter by requestID.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.logger.warning("Status check timeout for \(username), assuming offline")
                await self?.expireStatusRequest(username: username, requestID: requestID)
            }
        }
    }

    /// Handle status response - resumes every pending status check for this user
    public func handleUserStatusResponse(username: String, status: UserStatus, privileged: Bool?) {
        let resolvedPrivileged: Bool
        if let privileged {
            lastKnownPrivileged[username] = privileged
            resolvedPrivileged = privileged
        } else {
            resolvedPrivileged = lastKnownPrivileged[username] ?? false
        }

        if let waiters = pendingStatusRequests.removeValue(forKey: username) {
            for waiter in waiters {
                waiter.continuation.resume(returning: (status: status, privileged: resolvedPrivileged))
            }
        }

        emit(.userStatus(username: username, status: status, privileged: resolvedPrivileged))
    }

    /// Timeout path for `checkUserOnlineStatus` — resolve a still-pending
    /// waiter as offline.
    func expireStatusRequest(username: String, requestID: UUID) {
        guard var waiters = pendingStatusRequests[username] else { return }
        guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
        let waiter = waiters.remove(at: idx)
        if waiters.isEmpty {
            pendingStatusRequests.removeValue(forKey: username)
        } else {
            pendingStatusRequests[username] = waiters
        }
        waiter.continuation.resume(returning: (status: .offline, privileged: false))
    }

    // MARK: - Peer Connections

    /// Browse a user's shared files. Concurrent callers for the same `username`
    /// are coalesced into a single establishment + a single `requestShares`
    /// roundtrip, and all receive the same `[SharedFile]` result.
    ///
    /// Two layers of coalescing happen here:
    ///   1. `pendingBrowseUserCalls` dedups the *whole operation* (connection
    ///      + request + reply wait) so we don't issue N requestShares to
    ///      the same peer on N concurrent browses.
    ///   2. `establishPeerConnection` (called inside) dedups just the
    ///      connection establishment, which also benefits non-browse
    ///      consumers like fetchUserInfo running in parallel.
    public func browseUser(_ username: String) async throws -> [SharedFile] {
        if let inFlight = pendingBrowseUserCalls[username] {
            return try await inFlight.value
        }

        let task = Task<[SharedFile], Error> { [weak self] in
            guard let self else { throw NetworkError.notConnected }
            do {
                let result = try await self._performBrowseUser(username)
                await self.clearPendingBrowseUserCall(username)
                return result
            } catch {
                await self.clearPendingBrowseUserCall(username)
                throw error
            }
        }
        pendingBrowseUserCalls[username] = task
        return try await task.value
    }

    private func clearPendingBrowseUserCall(_ username: String) {
        pendingBrowseUserCalls.removeValue(forKey: username)
    }

    /// Timeout path for the browse-shares wait — idempotent via
    /// `removeValue`: a reply that arrived first already consumed the
    /// continuation, so this wakes to a no-op.
    private func expireBrowseSharesContinuation(username: String) {
        if let cont = pendingBrowseSharesContinuations.removeValue(forKey: username) {
            cont.resume(throwing: NetworkError.timeout)
        }
    }

    private func _performBrowseUser(_ username: String) async throws -> [SharedFile] {
        logger.debug("Browse: START browseUser(\(username))")
        // Deliberately reuses an existing connection — no known failure mode
        // requires a fresh one. If browse ever returns stale data or blocks
        // other messages, force a fresh connection and document why.
        let connection = try await establishPeerConnection(for: username)

        logger.debug("Browse: Requesting shares from \(username)...")
        try await connection.requestShares()

        // Wait for sharesReceived event via pool stream (arrives in handlePoolEvent)
        let files = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SharedFile], Error>) in
            // The connection dance above can outlive the session: if a
            // disconnect ran `failAllPendingPeerOperations` in the interim,
            // registering a fresh continuation now would orphan it until
            // the 30s timeout. Fail fast instead.
            guard isConnected else {
                continuation.resume(throwing: NetworkError.notConnected)
                return
            }
            pendingBrowseSharesContinuations[username] = continuation

            // Timeout after 30 seconds. Fire-and-forget: idempotent via
            // `removeValue` — if the reply arrives first the continuation
            // is already gone, so this wakes to a no-op. Not worth tracking
            // per-call; outer `browseUser` is coalesced and itself owned.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                await self?.expireBrowseSharesContinuation(username: username)
            }
        }

        logger.debug("Browse: Got \(files.count) files from \(username)")
        return files
    }

    // Pending browse state - tracks both waiting and received connections
    struct PendingBrowseState {
        let username: String
        var continuation: CheckedContinuation<PeerConnection, Error>?
        var receivedConnection: PeerConnection?  // Set if PierceFirewall arrives before we start waiting
        var timeoutTask: Task<Void, Never>?
        var timedOut = false
        var failureReason: String?  // Set by CantConnectToPeer to fail the wait fast
    }

    /// Register a pending browse BEFORE sending ConnectToPeer (to avoid race condition)
    public func registerPendingBrowse(token: UInt32, username: String, timeout: TimeInterval) async {
        var state = PendingBrowseState(username: username)

        // Set up timeout
        state.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.expirePendingBrowse(token: token)
        }

        pendingBrowseStates[token] = state
        // Pre-register the username the pool should stamp on whatever indirect
        // connection arrives bearing this token. Awaited (not fire-and-forget)
        // so it's set BEFORE we send ConnectToPeer (next call from the
        // caller). See `pierceFirewallExpectedUsernames` for the rationale.
        await peerConnectionPool.registerExpectedPierceFirewallUsername(token: token, username: username)
    }

    /// Timeout path for `registerPendingBrowse`. If still pending without a
    /// connection, fail the waiter and drop the entry — nothing consumes it
    /// after this point, and leaving it in the dict leaked one entry per
    /// failed browse (and let a late PierceFirewall park an orphaned socket
    /// in it).
    private func expirePendingBrowse(token: UInt32) async {
        if var pending = pendingBrowseStates[token] {
            if pending.receivedConnection == nil {
                logger.warning("Browse: Timeout waiting for PierceFirewall from \(pending.username) (token=\(token))")
                if let continuation = pending.continuation {
                    pending.continuation = nil
                    continuation.resume(throwing: NetworkError.timeout)
                }
                pendingBrowseStates.removeValue(forKey: token)
            }
        }
        // Clear any leftover username pre-registration.
        await peerConnectionPool.clearExpectedPierceFirewallUsername(token: token)
    }

    /// Wait for a previously registered pending browse to receive PierceFirewall
    public func waitForPendingBrowse(token: UInt32) async throws -> PeerConnection {
        // Check if connection already arrived (or failed)
        if let state = pendingBrowseStates[token] {
            if let connection = state.receivedConnection {
                logger.debug("Browse: PierceFirewall already received for token=\(token)")
                pendingBrowseStates.removeValue(forKey: token)
                return connection
            }
            if state.timedOut {
                pendingBrowseStates.removeValue(forKey: token)
                throw NetworkError.timeout
            }
            if let reason = state.failureReason {
                pendingBrowseStates.removeValue(forKey: token)
                throw NetworkError.connectionFailed(reason)
            }
        }

        // Wait for connection. Cancellation-aware: callers race this waiter
        // against a direct connect inside task groups — without the handler,
        // group.cancelAll() can't unwind the waiter and the group blocks at
        // scope exit until the registration timeout fires.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if var state = pendingBrowseStates[token] {
                    // Check again if connection arrived while we were setting up
                    if let connection = state.receivedConnection {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(returning: connection)
                        return
                    }
                    if state.timedOut {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(throwing: NetworkError.timeout)
                        return
                    }
                    if let reason = state.failureReason {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(throwing: NetworkError.connectionFailed(reason))
                        return
                    }
                    state.continuation = continuation
                    pendingBrowseStates[token] = state
                } else {
                    // Token was already removed (cancelled or error)
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaitForPendingBrowse(token: token)
            }
        }
    }

    /// Unblock a cancelled `waitForPendingBrowse` waiter. The entry itself
    /// stays registered (minus the waiter) so a late PierceFirewall is still
    /// matched and cleaned up rather than falling through unhandled.
    private func cancelWaitForPendingBrowse(token: UInt32) {
        guard var state = pendingBrowseStates[token],
              let continuation = state.continuation else { return }
        state.continuation = nil
        pendingBrowseStates[token] = state
        continuation.resume(throwing: CancellationError())
    }

    /// Mark a pending browse as failed (e.g. server sent CantConnectToPeer).
    /// The waiter, if any, fails fast instead of sitting on the 30s timeout.
    public func failPendingBrowse(token: UInt32, reason: String) {
        guard var state = pendingBrowseStates[token] else { return }
        state.timeoutTask?.cancel()
        state.failureReason = reason
        Task { [pool = peerConnectionPool] in
            await pool.clearExpectedPierceFirewallUsername(token: token)
        }
        if let continuation = state.continuation {
            state.continuation = nil
            pendingBrowseStates.removeValue(forKey: token)
            continuation.resume(throwing: NetworkError.connectionFailed(reason))
            return
        }
        pendingBrowseStates[token] = state
    }

    /// Cancel a pending browse (used when direct connection succeeds or search delivery completes)
    public func cancelPendingBrowse(token: UInt32) {
        if let state = pendingBrowseStates.removeValue(forKey: token) {
            state.timeoutTask?.cancel()
            // Don't resume continuation - caller will handle the success case
            // A PierceFirewall that arrived but was never consumed (direct
            // path won the race) is an orphaned live socket — close it.
            if let connection = state.receivedConnection {
                Task { await connection.disconnect() }
            }
        }
        Task { [pool = peerConnectionPool] in
            await pool.clearExpectedPierceFirewallUsername(token: token)
        }
    }

    /// Called when PierceFirewall is received - check if it matches a pending browse request
    /// Returns true if it was handled as a browse request.
    ///
    /// Async because we await `setPeerUsername` before resuming the browse
    /// waiter — by the time the waiter gets the connection back, the
    /// username is already stamped (the pool also stamps it pre-yield, so
    /// in practice this is defense in depth: the local stamp guarantees
    /// it even if the pool's pre-registration map was cleared).
    public func handlePierceFirewallForBrowse(token: UInt32, connection: PeerConnection) async -> Bool {
        guard let initial = pendingBrowseStates[token] else { return false }

        // A browse that already failed (CantConnectToPeer) has no waiter
        // left; storing the connection would orphan a live socket.
        if initial.timedOut || initial.failureReason != nil {
            logger.debug("Browse: late PierceFirewall token=\(token) for dead browse; closing")
            pendingBrowseStates.removeValue(forKey: token)
            await connection.disconnect()
            return true
        }
        logger.debug("Browse: PierceFirewall token=\(token) matched pending browse for \(initial.username)")

        // Stamp username — must complete BEFORE we resume any waiter so
        // callers always see a connection whose `peerInfo.username` matches
        // the user they asked for.
        await connection.setPeerUsername(initial.username)

        // RE-FETCH after the await: that suspension lets the 30s timeout,
        // CantConnectToPeer, or a cancelled waiter run on the main actor and
        // consume the entry — resuming a stale copy's continuation here was
        // a CheckedContinuation double-resume (fatal trap; field crash on
        // build 15 whenever a PierceFirewall raced the timeout).
        guard var state = pendingBrowseStates[token] else {
            logger.debug("Browse: token=\(token) consumed while stamping username; closing connection")
            await connection.disconnect()
            return true
        }
        if state.timedOut || state.failureReason != nil {
            pendingBrowseStates.removeValue(forKey: token)
            await connection.disconnect()
            return true
        }

        // Store the connection
        state.receivedConnection = connection
        state.timeoutTask?.cancel()

        // If there's a continuation waiting, claim it and resume exactly once
        if let continuation = state.continuation {
            state.continuation = nil
            pendingBrowseStates.removeValue(forKey: token)
            continuation.resume(returning: connection)
        } else {
            // No one waiting yet - store for later
            pendingBrowseStates[token] = state
        }
        return true
    }

    // MARK: - User Info Fetching (outbound)

    /// Fetch user info (description, picture, upload stats) from a peer.
    /// Establishes a P connection if one isn't already open, sends UserInfoRequest,
    /// and awaits the reply. Results are cached for the session and concurrent
    /// callers for the same user are coalesced into one round-trip.
    @discardableResult
    public func fetchUserInfo(from username: String) async throws -> MessageParser.UserInfoReplyInfo {
        if let cached = userInfoReplyCache[username] {
            return cached
        }
        if let inFlight = userInfoInFlight[username] {
            return try await inFlight.value
        }
        let task = Task<MessageParser.UserInfoReplyInfo, Error> { [weak self] in
            guard let self else { throw NetworkError.notConnected }
            do {
                let info = try await self.performFetchUserInfo(from: username)
                await self.clearUserInfoInFlight(username)
                return info
            } catch {
                await self.clearUserInfoInFlight(username)
                throw error
            }
        }
        userInfoInFlight[username] = task
        let info = try await task.value
        cacheUserInfoReply(username: username, info)
        return info
    }

    private func clearUserInfoInFlight(_ username: String) {
        userInfoInFlight[username] = nil
    }

    private func performFetchUserInfo(from username: String) async throws -> MessageParser.UserInfoReplyInfo {
        let connection = try await establishPeerConnection(for: username)
        try await connection.requestUserInfo()

        // Wait for the reply via a per-user continuation, with a hard timeout.
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MessageParser.UserInfoReplyInfo, Error>) in
            userInfoReplyContinuations[username] = cont
            // Fire-and-forget 15s timeout. Idempotent via `removeValue`:
            // if the reply arrives first the continuation is already
            // resumed and removed, so this wake is a no-op. Outer task
            // is owned by `userInfoInFlight`.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                await self?.expireUserInfoReply(username: username)
            }
        }
    }

    private func expireUserInfoReply(username: String) {
        if let waiter = userInfoReplyContinuations.removeValue(forKey: username) {
            waiter.resume(throwing: NetworkError.timeout)
        }
    }

    /// Invalidate the cached user info for a user (next fetch will re-request).
    public func invalidateUserInfoCache(for username: String) {
        userInfoReplyCache.removeValue(forKey: username)
    }

    private func cacheUserInfoReply(username: String, _ info: MessageParser.UserInfoReplyInfo) {
        if userInfoReplyCache.count >= maxUserInfoCacheEntries,
           userInfoReplyCache[username] == nil {
            // Simple pressure valve: drop half. LRU bookkeeping isn't worth
            // it for a cache whose hits are user-driven profile views.
            for key in userInfoReplyCache.keys.prefix(maxUserInfoCacheEntries / 2) {
                userInfoReplyCache.removeValue(forKey: key)
            }
        }
        userInfoReplyCache[username] = info
    }

    func handleUserInfoReplyEvent(username: String, info: MessageParser.UserInfoReplyInfo) {
        // Unsolicited replies (no waiter) get cached without the picture —
        // hostile or chatty peers shouldn't be able to park image bytes.
        if userInfoReplyContinuations[username] == nil {
            var stripped = info
            stripped.pictureData = nil
            cacheUserInfoReply(username: username, stripped)
        } else {
            cacheUserInfoReply(username: username, info)
        }
        if let cont = userInfoReplyContinuations.removeValue(forKey: username) {
            cont.resume(returning: info)
        }
        emit(.userInfoReply(username: username, info: info))
    }

    // MARK: - Peer Connection Establishment

    /// Opens (or reuses) a P-type peer connection, completing the handshake.
    /// The single home of the ConnectToPeer + direct/indirect-race dance —
    /// used by browse, folder-contents, user-info, and downloads. Anyone
    /// reaching out to a peer for the first time should go through here so
    /// the firewall-traversal logic isn't reinvented per consumer.
    ///
    /// Concurrent calls for the same `username` are coalesced via
    /// `pendingEstablishments`, so N parallel downloads to one peer share
    /// one connection establishment instead of racing each other.
    public func establishPeerConnection(for username: String) async throws -> PeerConnection {
        guard isConnected else {
            throw NetworkError.notConnected
        }

        if let existing = await peerConnectionPool.getConnectionForUser(username) {
            return existing
        }

        if let inFlight = pendingEstablishments[username] {
            return try await inFlight.value
        }

        let task = Task { [weak self] in
            guard let self else { throw NetworkError.notConnected }
            do {
                let connection = try await self.performEstablishPeerConnection(for: username)
                await self.clearPendingEstablishment(username)
                return connection
            } catch {
                await self.clearPendingEstablishment(username)
                throw error
            }
        }
        pendingEstablishments[username] = task
        return try await task.value
    }

    private func clearPendingEstablishment(_ username: String) {
        pendingEstablishments.removeValue(forKey: username)
    }

    private func performEstablishPeerConnection(for username: String) async throws -> PeerConnection {
        // Resolve the address BEFORE registering the browse and sending
        // ConnectToPeer: the server answers GetPeerAddress for an offline/
        // unknown user with 0.0.0.0:0, and bailing here saves a wasted
        // ConnectToPeer + 30s browse window per attempt — at retry-storm
        // rates that was hundreds of pointless server messages per minute.
        // A PierceFirewall can't arrive before ConnectToPeer is sent, so
        // registering after the lookup loses nothing.
        let (ip, port, obfuscatedPort) = try await getPeerAddress(for: username)

        guard ip != "0.0.0.0", port > 0 || obfuscatedPort > 0 else {
            throw NetworkError.connectionFailed("\(username) is offline (no address)")
        }

        let token = UInt32.random(in: 0...UInt32.max)
        await registerPendingBrowse(token: token, username: username, timeout: 30)
        await sendConnectToPeer(token: token, username: username, connectionType: "P")

        // Prefer the peer's obfuscated port whenever they advertise one.
        // Peers always advertise the plain port too, so falling back to plain
        // is safe when a peer doesn't advertise obfuscation.
        let useObfuscated = obfuscatedPort > 0
        let dialPort = useObfuscated ? obfuscatedPort : port

        // Both legs run together: a firewalled peer cannot accept the
        // direct dial, and its pierce often arrives in under a second.
        let (connection, isIndirect) = try await withThrowingTaskGroup(of: (PeerConnection, Bool).self) { group in
            group.addTask {
                // Cap the direct leg: a raw TCP dial can hang for 60 s.
                // Most clients send no reciprocal PeerInit, and pool.connect
                // already sent ours. Do not wait.
                let direct = try await withTimeout(seconds: 10) {
                    try await self.peerConnectionPool.connect(
                        to: username, ip: ip, port: dialPort, token: token, obfuscated: useObfuscated
                    )
                }
                return (direct, false)
            }
            group.addTask {
                (try await self.waitForPendingBrowse(token: token), true)
            }
            // nextResult, not next: one leg's failure must not abort
            // the other. Drain every child: a pierce that was consumed by
            // the waiter but lost the race is not in the pool and not in
            // `pendingBrowseStates`, so nothing else can close it. A losing
            // direct connection stays pool-tracked and reusable.
            var winner: (PeerConnection, Bool)?
            var lastError: Error = NetworkError.timeout
            while let result = await group.nextResult() {
                switch result {
                case .success(let value):
                    if winner == nil {
                        winner = value
                        group.cancelAll()
                    } else if value.1 {
                        await value.0.disconnect()
                    }
                case .failure(let error):
                    if !(error is CancellationError) { lastError = error }
                }
            }
            if let winner { return winner }
            // Both legs report CancellationError when the establishment
            // itself was cancelled (disconnect) — do not dress that up as
            // a timeout.
            try Task.checkCancellation()
            throw lastError
        }
        if isIndirect {
            try await connection.finalizeIndirectPeerConnection()
        } else {
            cancelPendingBrowse(token: token)
        }
        return connection
    }

    struct PendingArtworkRequest {
        var token: UInt32
        var waiters: [@Sendable (Data?) -> Void]
    }

    static func artworkKey(username: String, filePath: String) -> String {
        "\(username)|\(filePath)"
    }

    /// Request artwork from a SeeleSeek peer.
    /// The completion handler is called with image data, or nil if the peer doesn't respond / isn't SeeleSeek.
    /// Only works if we already have a connection to the peer (e.g., from search results).
    public func requestArtwork(from username: String, filePath: String) async -> Data? {
        await withCheckedContinuation { continuation in
            requestArtwork(from: username, filePath: filePath) { data in
                continuation.resume(returning: data)
            }
        }
    }

    public func requestArtwork(from username: String, filePath: String, completion: @Sendable @escaping (Data?) -> Void) {
        guard isConnected else {
            completion(nil)
            return
        }

        let key = Self.artworkKey(username: username, filePath: filePath)

        // Coalesce: if a request for the same (peer, file) is in flight,
        // attach as an additional waiter and return — peer is asked once.
        if pendingArtworkRequests[key] != nil {
            pendingArtworkRequests[key]?.waiters.append(completion)
            return
        }

        let token = UInt32.random(in: 1..<0x8000_0000)
        pendingArtworkRequests[key] = PendingArtworkRequest(token: token, waiters: [completion])
        // Bridge token → key for the artworkReply event handler.
        artworkCallbacks[token] = { [weak self] data in
            Task { await self?.deliverArtwork(key: key, data: data) }
        }

        Task { [self] in
            guard let connection = await peerConnectionPool.getConnectionForUser(username) else {
                logger.debug("No existing connection to \(username) for artwork request")
                deliverArtwork(key: key, data: nil)
                return
            }

            // Throws `capabilityNotAdvertised` for peers that never advertised
            // it, which lands in the same nil delivery as a send failure.
            let request = MessageBuilder.artworkRequestMessage(token: token, filePath: filePath)
            do {
                try await connection.send(extension: .artworkRequest, request)
            } catch {
                logger.debug("Artwork request to \(username) not sent: \(error.localizedDescription)")
                deliverArtwork(key: key, data: nil)
                return
            }

            // Fire-and-forget 10s timeout. `deliverArtwork` is idempotent —
            // if the real reply arrived first the entry is already gone, so
            // the nil-delivery no-ops. Not worth tracking per-call.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                await self?.deliverArtwork(key: key, data: nil)
            }
        }
    }

    /// Deliver an artwork result to every waiter for `(peer, file)` and
    /// clean up the coalesced entry. Idempotent — late timeout firing after
    /// the real reply already delivered finds no entry and no-ops.
    func deliverArtwork(key: String, data: Data?) {
        guard let pending = pendingArtworkRequests.removeValue(forKey: key) else { return }
        artworkCallbacks.removeValue(forKey: pending.token)
        for waiter in pending.waiters {
            waiter(data)
        }
    }

    /// Request folder contents from a peer. Returns the token used so the
    /// caller can correlate the eventual `folderContentsResponse` event
    /// back to the originating request (multiple concurrent folder requests
    /// otherwise race on `(folder, peer)` alone).
    ///
    /// Routes through `establishPeerConnection`, which races a direct TCP
    /// connect against a server-mediated PierceFirewall indirect connection
    /// (10 s budget) — essential for firewalled peers whose listen port is
    /// unreachable. A bare `peerConnectionPool.connect(...)` here would hang
    /// on TCP SYN for ~75 s with no fallback, which is the entire failure
    /// mode this helper exists to solve. Do not bypass it.
    @discardableResult
    public func requestFolderContents(from username: String, folder: String) async throws -> UInt32 {
        guard isConnected else { throw NetworkError.notConnected }

        let token = UInt32.random(in: 0...UInt32.max)
        let connection = try await establishPeerConnection(for: username)
        try await connection.requestFolderContents(token: token, folder: folder)
        return token
    }

    /// Resume every peer-operation continuation with an error so no caller
    /// stays blocked across a disconnect. Covers every pending-dict used in
    /// `establishPeerConnection` / browse / status / artwork paths.
    func failAllPendingPeerOperations(reason: String) {
        let error = NetworkError.connectionFailed(reason)

        for (_, waiters) in pendingPeerAddressRequests {
            for waiter in waiters {
                waiter.continuation.resume(throwing: error)
            }
        }
        pendingPeerAddressRequests.removeAll()

        for (_, waiters) in pendingStatusRequests {
            for waiter in waiters {
                waiter.continuation.resume(returning: (status: .offline, privileged: false))
            }
        }
        pendingStatusRequests.removeAll()

        for (_, continuation) in pendingBrowseSharesContinuations {
            continuation.resume(throwing: error)
        }
        pendingBrowseSharesContinuations.removeAll()

        for (token, state) in pendingBrowseStates {
            state.timeoutTask?.cancel()
            state.continuation?.resume(throwing: error)
            // The cancelled timeout task was the one path that would have
            // cleared the pool's expected-username entry — clear it here or
            // it leaks one entry per in-flight establishment per disconnect
            // (and risks stamping a stale username on a token collision in
            // a later session).
            Task { [pool = peerConnectionPool] in
                await pool.clearExpectedPierceFirewallUsername(token: token)
            }
        }
        pendingBrowseStates.removeAll()

        // Cancel each in-flight establishment task. `removeAll()` alone
        // just drops our handle to the task — it keeps running, can
        // complete after disconnect, and hands a live PeerConnection
        // back to a caller whose session is already dead. Cancelling
        // propagates cooperative cancellation into the direct-dial /
        // PierceFirewall race so the awaiter sees CancellationError
        // instead of a zombie connection.
        for (_, task) in pendingEstablishments {
            task.cancel()
        }
        pendingEstablishments.removeAll()

        for (_, continuation) in userInfoReplyContinuations {
            continuation.resume(throwing: error)
        }
        userInfoReplyContinuations.removeAll()
        // Same story as pendingEstablishments: the inner task could be
        // mid-handshake with a peer. Cancel before dropping so the
        // `try await task.value` caller unwinds.
        for (_, task) in userInfoInFlight {
            task.cancel()
        }
        userInfoInFlight.removeAll()
        // Leave `userInfoReplyCache` intact — cached peer metadata isn't
        // invalidated by a server reconnect; users can still be looked up
        // by the next session without a fresh round-trip.

        for (_, pending) in pendingArtworkRequests {
            artworkCallbacks.removeValue(forKey: pending.token)
            for waiter in pending.waiters {
                waiter(nil)
            }
        }
        pendingArtworkRequests.removeAll()
        // Any dangling artwork callbacks whose pending entry was already
        // torn down earlier — drop them too so the next session starts clean.
        artworkCallbacks.removeAll()
    }
}
