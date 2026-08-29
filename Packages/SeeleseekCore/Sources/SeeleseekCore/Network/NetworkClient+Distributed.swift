import Foundation
import os

// MARK: - Distributed Search Network
//
// Branch/parent/child management for Soulseek's distributed search tree,
// plus the handlers for distributed frames (parent adoption, search relay,
// branch propagation) and the direct/indirect delivery race for search
// replies. Branch state (`distributedChildren` / level / root) is stored on
// the actor in NetworkClient.swift.
extension NetworkClient {
    // MARK: - Distributed Network

    /// Pre-connect preference set — records the flag without advertising
    /// to the server (the login sequence advertises it).
    public func setAcceptDistributedChildrenPreference(_ accept: Bool) {
        acceptDistributedChildren = accept
    }

    public func setAcceptDistributedChildren(_ accept: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        acceptDistributedChildren = accept
        let message = MessageBuilder.acceptChildren(accept)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set AcceptChildren(\(accept))")
    }

    /// Tell server whether we have a distributed parent
    public func sendHaveNoParent(_ haveNoParent: Bool) async throws {
        let message = MessageBuilder.haveNoParent(haveNoParent)
        try await requireConnectedServerConnection().send(message)
        logger.info("Sent HaveNoParent(\(haveNoParent))")
    }

    public func setDistributedBranchLevel(_ level: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchLevel = level
        let message = MessageBuilder.branchLevel(level)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchLevel(\(level))")
    }

    /// Update our branch root
    public func setDistributedBranchRoot(_ root: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchRoot = root
        let message = MessageBuilder.branchRoot(root)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchRoot(\(root))")
    }

    /// Update our child depth
    public func setDistributedChildDepth(_ depth: UInt32) async throws {
        let message = MessageBuilder.childDepth(depth)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ChildDepth(\(depth))")
    }

    /// Reset distributed network state (called when server sends code 130)
    public func resetDistributedNetwork() async {
        guard isConnected else { return }

        logger.info("Resetting distributed network state")

        await clearDistributedState()

        // Tell server we have no parent and need one
        do {
            let haveNoParentMessage = MessageBuilder.haveNoParent(true)
            try await requireConnectedServerConnection().send(haveNoParentMessage)

            let branchLevelMessage = MessageBuilder.branchLevel(0)
            try await requireConnectedServerConnection().send(branchLevelMessage)

            // See the login sequence: child support is unimplemented, so
            // always advertise honestly regardless of the (kept-for-future)
            // `acceptDistributedChildren` flag.
            let acceptChildrenMessage = MessageBuilder.acceptChildren(false)
            try await requireConnectedServerConnection().send(acceptChildrenMessage)

            logger.info("Distributed network reset complete, awaiting new parent assignment")
        } catch {
            logger.error("Failed to send distributed reset messages: \(error.localizedDescription)")
        }
    }

    /// Drop every distributed child socket and reset branch state. Shared
    /// between `resetDistributedNetwork` (server code 130) and
    /// `performDisconnect` — a reconnect must not inherit live child
    /// sockets from the previous session. Does not touch the server
    /// connection, so it's safe to call during teardown.
    func clearDistributedState() async {
        for child in distributedChildren {
            await child.disconnect()
        }
        distributedChildren.removeAll()
        distributedBranchLevel = 0
        distributedBranchRoot = ""
    }

    /// Add a distributed child connection
    public func addDistributedChild(_ connection: PeerConnection) {
        self.distributedChildren.append(connection)
        let count = self.distributedChildren.count
        self.logger.info("Added distributed child, total: \(count)")
    }

    /// Remove a distributed child connection
    public func removeDistributedChild(_ connection: PeerConnection) async {
        self.distributedChildren.removeAll { $0 === connection }
        let count = self.distributedChildren.count
        self.logger.info("Removed distributed child, total: \(count)")
    }

    /// Forward a distributed search to all children
    public func forwardDistributedSearch(unknown: UInt32, username: String, token: UInt32, query: String) async {
        guard !self.distributedChildren.isEmpty else { return }

        self.logger.info("Forwarding distributed search to \(self.distributedChildren.count) children")

        // Build the distributed search message once — identical for every child.
        var searchPayload = Data()
        searchPayload.appendUInt8(DistributedMessageCode.searchRequest.rawValue)
        searchPayload.appendUInt32(unknown)
        searchPayload.appendString(username)
        searchPayload.appendUInt32(token)
        searchPayload.appendString(query)

        var message = Data()
        message.appendUInt32(UInt32(searchPayload.count))
        message.append(searchPayload)

        for child in self.distributedChildren {
            do {
                try await child.send(message)
            } catch {
                logger.error("Failed to forward search to child: \(error.localizedDescription)")
            }
        }
    }

    /// Get number of distributed children
    public var distributedChildCount: Int { distributedChildren.count }

    // MARK: - Distributed Network Handlers

    func handlePossibleParents(_ data: Data) {
        guard let parsed = MessageParser.parsePossibleParents(data) else { return }

        logger.info("Received \(parsed.count) possible distributed parents")

        let parents: [(username: String, ip: String, port: Int)] = parsed.enumerated().map { i, p in
            logger.debug("Parent \(i+1): \(p.username) at \(p.ip):\(p.port)")
            return (username: p.username, ip: p.ip, port: Int(p.port))
        }

        // Skip if we already have a parent
        if distributedParentConnection != nil {
            logger.debug("Already have a distributed parent, ignoring PossibleParents")
            return
        }

        // Adoption runs in a task that can take up to 15s (3 × 5s connects);
        // a second PossibleParents in that window must not start a second
        // adoption loop (duplicate parents, inconsistent branch reports).
        if isConnectingToParent {
            logger.debug("Parent adoption already in progress, ignoring PossibleParents")
            return
        }
        isConnectingToParent = true

        // Try to connect to first few parents until one succeeds (limit to avoid resource exhaustion)
        Task {
            defer { isConnectingToParent = false }
            let maxAttempts = min(3, parents.count)
            for i in 0..<maxAttempts {
                let parent = parents[i]
                let success = await connectToDistributedParent(
                    username: parent.username,
                    ip: parent.ip,
                    port: parent.port
                )
                if success {
                    logger.info("Successfully connected to distributed parent \(parent.username)")
                    break
                }
            }
        }
    }

    /// Disconnect and drop the distributed-parent socket. Called from
    /// `NetworkClient.performDisconnect` so a reconnect doesn't inherit
    /// a live parent from the previous session — the old socket would
    /// otherwise keep feeding distributed search traffic into the new
    /// message handler (and would outlive the server connection that
    /// introduced it).
    public func tearDownDistributedParent() async {
        if let parent = distributedParentConnection {
            distributedParentConnection = nil
            await parent.disconnect()
        }
    }

    private func connectToDistributedParent(username: String, ip: String, port: Int) async -> Bool {
        logger.info("Connecting to distributed parent: \(username) at \(ip):\(port)")

        let token = UInt32.random(in: 0...UInt32.max)

        // Connect with "D" type for distributed network
        let peerInfo = PeerConnection.PeerInfo(username: username, ip: ip, port: port)
        let connection = PeerConnection(peerInfo: peerInfo, type: .distributed, token: token)

        do {
            // Use shorter timeout to free resources faster
            try await withTimeout(seconds: 5) {
                try await connection.connect()
            }

            // Send PeerInit with "D" type
            try await connection.sendPeerInit(username: self.username)

            logger.info("Connected to distributed parent: \(username)")

            // Store the new parent BEFORE disconnecting the old one so the
            // old parent's stream-end loss handler sees it was replaced and
            // doesn't trigger a spurious distributed-network reset.
            let oldParent = distributedParentConnection
            distributedParentConnection = connection
            if let oldParent {
                logger.info("Disconnecting old distributed parent")
                await oldParent.disconnect()
            }

            // Consume distributed messages from the connection's event stream
            let parentUsername = username
            Task { [weak self] in
                for await event in connection.events {
                    guard let self else { return }
                    if case .message(let code, let payload) = event {
                        await self.handleDistributedMessage(code: code, payload: payload, parentUsername: parentUsername)
                    }
                }
                // Stream ended: the parent dropped us (or we tore it down).
                await self?.handleDistributedParentLoss(connection)
            }

            // Tell server we have a parent now
            do {
                try await self.sendHaveNoParent(false)
            } catch {
                logger.error("Failed to send HaveNoParent(false): \(error.localizedDescription)")
            }

            return true
        } catch {
            logger.error("Failed to connect to distributed parent \(username): \(error.localizedDescription)")
            // Explicitly disconnect to free resources
            await connection.disconnect()
            return false
        }
    }

    /// Called when a distributed parent's event stream ends. Without this
    /// the stale `distributedParentConnection` blocks all future parent
    /// offers and the client silently leaves the distributed network (our
    /// shares stop appearing in other users' searches) until reconnect.
    private func handleDistributedParentLoss(_ connection: PeerConnection) async {
        // A newer parent may already have replaced this one, and teardown
        // paths (tearDownDistributedParent) clear the reference themselves.
        guard distributedParentConnection === connection else { return }
        distributedParentConnection = nil
        logger.warning("Distributed parent disconnected; requesting a new parent")
        await self.resetDistributedNetwork()
    }

    private func handleDistributedMessage(code: UInt32, payload: Data, parentUsername: String = "") async {
        // No per-message log here: this fires 5-50x/sec in steady state.
        switch code {
        case UInt32(DistributedMessageCode.branchLevel.rawValue):
            // uint32 branch level from parent
            if let parentLevel = payload.readUInt32(at: 0) {
                let ourLevel = parentLevel + 1
                logger.info("Parent branch level: \(parentLevel), our level: \(ourLevel)")

                // Report our level to server and propagate to children
                Task {
                    try? await self.setDistributedBranchLevel(ourLevel)

                    // If parent is level 0, they ARE the branch root
                    if parentLevel == 0 {
                        logger.info("Parent is branch root: \(parentUsername)")
                        try? await self.setDistributedBranchRoot(parentUsername)

                        // Propagate to children
                        await sendBranchInfoToChildren(level: ourLevel, root: parentUsername)
                    }
                }
            }

        case UInt32(DistributedMessageCode.branchRoot.rawValue):
            // string branch root username from parent
            if let (rootUsername, _) = payload.readString(at: 0) {
                logger.info("Branch root: \(rootUsername)")

                // Report to server and propagate to children
                Task {
                    try? await self.setDistributedBranchRoot(rootUsername)

                    let ourLevel = distributedBranchLevel
                    await sendBranchInfoToChildren(level: ourLevel, root: rootUsername)
                }
            }

        case UInt32(DistributedMessageCode.searchRequest.rawValue):
            handleDistributedSearch(payload)

        case UInt32(DistributedMessageCode.childDepth.rawValue):
            logger.debug("Distributed child depth update received")

        case UInt32(DistributedMessageCode.embeddedMessage.rawValue):
            handleEmbeddedMessage(payload)

        default:
            logger.warning("Unknown distributed message code: \(code)")
        }
    }

    private func sendBranchInfoToChildren(level: UInt32, root: String) async {
        let children = self.distributedChildren
        guard !children.isEmpty else { return }

        // Build DistribBranchLevel message: [length][uint8 code=4][uint32 level]
        var levelPayload = Data()
        levelPayload.appendUInt8(DistributedMessageCode.branchLevel.rawValue)
        levelPayload.appendUInt32(level)
        var levelMessage = Data()
        levelMessage.appendUInt32(UInt32(levelPayload.count))
        levelMessage.append(levelPayload)

        // Build DistribBranchRoot message: [length][uint8 code=5][string root]
        var rootPayload = Data()
        rootPayload.appendUInt8(DistributedMessageCode.branchRoot.rawValue)
        rootPayload.appendString(root)
        var rootMessage = Data()
        rootMessage.appendUInt32(UInt32(rootPayload.count))
        rootMessage.append(rootPayload)

        for child in children {
            do {
                try await child.send(levelMessage)
                try await child.send(rootMessage)
            } catch {
                logger.error("Failed to send branch info to child: \(error.localizedDescription)")
            }
        }

        logger.info("Propagated branch info (level=\(level), root=\(root)) to \(children.count) children")
    }

    func handleEmbeddedMessage(_ data: Data) {
        // Server sends us an embedded distributed message (when we're a branch root)
        // Format: uint8 distrib_code + message payload
        guard let distribCode = data.readByte(at: 0) else { return }

        let payload = data.safeSubdata(in: 1..<data.count) ?? Data()

        if distribCode == DistributedMessageCode.searchRequest.rawValue {
            handleDistributedSearch(payload)
        }
    }

    private func handleDistributedSearch(_ data: Data) {
        guard let info = MessageParser.parseDistributedSearch(data) else { return }
        let unknown = info.unknown
        let username = info.username
        let token = info.token
        let query = info.query

        // Forward to children
        Task {
            await self.forwardDistributedSearch(unknown: unknown, username: username, token: token, query: query)
        }

        // Don't respond to our own searches
        guard username != self.username else { return }

        // Apply search response policy (pushed down from app settings)
        let filter = searchResponsePolicy

        guard filter.enabled else {
            return
        }

        // Filter short queries (they match too broadly and waste bandwidth)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard trimmedQuery.count >= filter.minQueryLength else {
            return
        }

        // Resolve buddy status here, on the actor, before the off-actor
        // search scan. Passing the bool in keeps ShareManager decoupled
        // from SocialState.
        let isBuddy = self.isBuddy(username)

        // Fire-and-forget by design: the relay stream must not wait for
        // the scan+delivery of one query (5-50 queries/sec in steady
        // state). The scan itself runs off-actor — see the responder.
        Task { [self] in
            await respondToDistributedSearch(
                query: query,
                from: username,
                token: token,
                isBuddy: isBuddy,
                maxResults: filter.maxResults
            )
        }
    }

    /// `@concurrent`, so the share-index scan runs on the global executor —
    /// `ShareManager.search` is nonisolated over an immutable snapshot, and
    /// running it actor-isolated would burn the client actor at relay rates.
    @concurrent
    private nonisolated func respondToDistributedSearch(
        query: String,
        from username: String,
        token: UInt32,
        isBuddy: Bool,
        maxResults: Int
    ) async {
        var matchingFiles = shareManager.search(query: query, includeBuddyOnly: isBuddy)
        guard !matchingFiles.isEmpty else { return }

        if maxResults > 0 && matchingFiles.count > maxResults {
            matchingFiles = Array(matchingFiles.prefix(maxResults))
        }

        logger.debug("Distributed search '\(query)' from \(username) (buddy=\(isBuddy)): \(matchingFiles.count) matches")
        await ActivityLogger.shared?.logDistributedSearch(query: query, matchCount: matchingFiles.count)

        await self.sendDistributedSearchResponse(
            to: username,
            token: token,
            files: matchingFiles
        )
    }

    private func sendDistributedSearchResponse(
        to username: String,
        token: UInt32,
        files: [ShareManager.IndexedFile]
    ) async {
        // Build results once (shared by direct and indirect paths).
        // Split by visibility so buddy-only matches land in the
        // protocol's "privately shared results" section — the receiver
        // uses that split to decorate them as private on their side.
        typealias SearchResultTuple = (filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])
        func toTuple(_ file: ShareManager.IndexedFile) -> SearchResultTuple {
            var attributes: [(UInt32, UInt32)] = []
            if let bitrate = file.bitrate { attributes.append((0, bitrate)) }
            if let duration = file.duration { attributes.append((1, duration)) }
            return (
                filename: file.sharedPath,
                size: file.size,
                extension_: file.fileExtension,
                attributes: attributes
            )
        }
        let publicResults: [SearchResultTuple] = files.filter { $0.visibility == .public }.map(toTuple)
        let privateResults: [SearchResultTuple] = files.filter { $0.visibility == .buddies }.map(toTuple)

        // Race direct and indirect connections simultaneously for faster delivery
        let indirectToken = UInt32.random(in: 0...UInt32.max)

        // Register pending indirect BEFORE starting anything (to catch early PierceFirewall)
        await self.registerPendingBrowse(token: indirectToken, username: username, timeout: 15)
        await self.sendConnectToPeer(token: indirectToken, username: username, connectionType: "P")

        // Tolerate individual path failures: a fast direct refusal must not
        // kill the still-viable indirect (PierceFirewall) path — rethrowing
        // the first child's error + cancelAll did exactly that, so search
        // results were never delivered to firewalled peers. Each child
        // reports its own outcome; we only give up when both paths failed
        // or the overall deadline passes.
        let connection: PeerConnection? = await withTaskGroup(of: SearchDeliveryOutcome.self) { group in
            // Direct path: get address + connect
            group.addTask {
                do {
                    let address = try await self.getPeerAddress(for: username, timeout: .seconds(5))
                    let connectionToken = UInt32.random(in: 0...UInt32.max)
                    let useObf = address.obfuscatedPort > 0
                    let conn = try await self.peerConnectionPool.connect(
                        to: username,
                        ip: address.ip,
                        port: useObf ? address.obfuscatedPort : address.port,
                        token: connectionToken,
                        obfuscated: useObf
                    )
                    // Direct PeerInit is one-way — never wait for a
                    // reciprocal (most clients don't send one).
                    return .connected(conn)
                } catch {
                    return .pathFailed
                }
            }

            // Indirect path: wait for PierceFirewall
            group.addTask {
                do {
                    let conn = try await self.waitForPendingBrowse(token: indirectToken)
                    await conn.resumeReceivingForPeerConnection()
                    // PierceFirewall IS the handshake for indirect connections -- do NOT send PeerInit
                    return .connected(conn)
                } catch {
                    return .pathFailed
                }
            }

            // Overall deadline: give up after 12s
            group.addTask {
                try? await Task.sleep(for: .seconds(12))
                return .deadline
            }

            var failedPaths = 0
            for await outcome in group {
                switch outcome {
                case .connected(let conn):
                    group.cancelAll()
                    return conn
                case .deadline:
                    group.cancelAll()
                    return nil
                case .pathFailed:
                    failedPaths += 1
                    if failedPaths == 2 {
                        // Both real paths failed — no point waiting out
                        // the deadline child.
                        group.cancelAll()
                        return nil
                    }
                }
            }
            return nil
        }

        // Always clear the indirect registration — on success (the direct
        // path may have won) and on failure alike.
        self.cancelPendingBrowse(token: indirectToken)

        guard let connection else {
            logger.debug("Search result delivery to \(username) failed: direct + indirect both failed or timed out")
            return
        }

        do {
            try await connection.sendSearchReply(
                username: self.username,
                token: token,
                results: publicResults,
                privateResults: privateResults
            )
            logger.debug("Sent \(publicResults.count) public + \(privateResults.count) private search results to \(username) for token \(token)")
        } catch {
            logger.debug("Search result delivery to \(username) failed: \(error.localizedDescription)")
        }
    }

    /// Outcome of one leg of the direct/indirect race in
    /// `sendDistributedSearchResponse`.
    private enum SearchDeliveryOutcome: Sendable {
        case connected(PeerConnection)
        case pathFailed
        case deadline
    }

    func handleResetDistributed() {
        logger.info("Server requested distributed network reset")

        // Disconnect from current distributed parent
        if let parentConnection = distributedParentConnection {
            Task {
                await parentConnection.disconnect()
            }
            distributedParentConnection = nil
        }

        // Reset distributed state on client and re-register with server
        Task {
            await self.resetDistributedNetwork()
        }
    }

    func handleParentMinSpeed(_ data: Data) {
        guard let speed = data.readUInt32(at: 0) else { return }
        logger.debug("Parent minimum speed: \(speed)")
    }

    func handleParentSpeedRatio(_ data: Data) {
        guard let ratio = data.readUInt32(at: 0) else { return }
        logger.debug("Parent speed ratio: \(ratio)")
    }
}
