import Foundation
import os

/// Handles incoming server messages and dispatches to appropriate callbacks
@MainActor
public final class ServerMessageHandler {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ServerMessageHandler")
    private weak var client: NetworkClient?
    private let maxItemCount: UInt32 = 100_000

    public init(client: NetworkClient) {
        self.client = client
    }

    public func handle(_ data: Data) async {
        guard data.count >= 8 else {
            logger.warning("Received message too short: \(data.count) bytes")
            return
        }

        // Parse message length and code
        guard let messageLength = data.readUInt32(at: 0),
              let codeValue = data.readUInt32(at: 4) else {
            logger.warning("Failed to parse message header")
            return
        }

        let code = ServerMessageCode(rawValue: codeValue)
        logger.info("Received message: code=\(codeValue) (\(code?.description ?? "unknown")) length=\(messageLength)")

        // Extra logging for distributed network messages
        if codeValue == 102 || codeValue == 93 || codeValue == 83 || codeValue == 84 || codeValue == 71 {
            logger.debug("DISTRIBUTED MSG: code=\(codeValue) (\(code?.description ?? "unknown")) length=\(messageLength)")
        }

        guard let code = code else {
            logger.warning("Unknown message code: \(codeValue)")
            return
        }

        let payload = data.safeSubdata(in: 8..<(Int(messageLength) + 4)) ?? Data()

        switch code {
        case .login:
            handleLogin(payload)
        case .ignoreUser:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .unignoreUser:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .roomList:
            handleRoomList(payload)
        case .fileSearchRoom:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .joinRoom:
            handleJoinRoom(payload)
        case .leaveRoom:
            handleLeaveRoom(payload)
        case .sayInChatRoom:
            handleSayInRoom(payload)
        case .userJoinedRoom:
            handleUserJoinedRoom(payload)
        case .userLeftRoom:
            handleUserLeftRoom(payload)
        case .privateMessages:
            handlePrivateMessage(payload)
        case .getPeerAddress:
            handleGetUserAddress(payload)
        case .watchUser:
            handleWatchUser(payload)
        case .getUserStatus:
            handleGetUserStatus(payload)
        case .connectToPeer:
            handleConnectToPeer(payload)
        case .sendConnectToken:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .sendDownloadSpeed:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .possibleParents:
            handlePossibleParents(payload)
        case .embeddedMessage:
            handleEmbeddedMessage(payload)
        case .resetDistributed:
            handleResetDistributed()
        case .parentMinSpeed:
            handleParentMinSpeed(payload)
        case .parentSpeedRatio:
            handleParentSpeedRatio(payload)
        case .searchParent:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .searchInactivityTimeout:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .minParentsInCache:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .distribPingInterval:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .recommendations:
            handleRecommendations(payload)
        case .similarRecommendations:
            handleRecommendations(payload)
        case .myRecommendations:
            handleRecommendations(payload)
        case .globalRecommendations:
            handleGlobalRecommendations(payload)
        case .userInterests:
            handleUserInterests(payload)
        case .similarUsers:
            handleSimilarUsers(payload)
        case .itemRecommendations:
            handleItemRecommendations(payload)
        case .itemSimilarUsers:
            handleItemSimilarUsers(payload)
        case .getUserStats:
            handleGetUserStats(payload)
        case .checkPrivileges:
            handleCheckPrivileges(payload)
        case .userPrivileges:
            handleUserPrivileges(payload)
        case .privilegedUsers:
            handlePrivilegedUsers(payload)
        case .roomTickerState:
            handleRoomTickerState(payload)
        case .roomTickerAdd:
            handleRoomTickerAdd(payload)
        case .roomTickerRemove:
            handleRoomTickerRemove(payload)
        case .wishlistInterval:
            handleWishlistInterval(payload)
        case .privateRoomMembers:
            handlePrivateRoomMembers(payload)
        case .privateRoomAddMember:
            handlePrivateRoomAddMember(payload)
        case .privateRoomRemoveMember:
            handlePrivateRoomRemoveMember(payload)
        case .privateRoomOperatorGranted:
            handlePrivateRoomOperatorGranted(payload)
        case .privateRoomOperatorRevoked:
            handlePrivateRoomOperatorRevoked(payload)
        case .privateRoomOperators:
            handlePrivateRoomOperators(payload)
        case .notifyPrivileges:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .ackNotifyPrivileges:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .privateRoomUnknown138:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .cantConnectToPeer:
            handleCantConnectToPeer(payload)
        case .adminMessage:
            handleAdminMessage(payload)
        case .adminCommand:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .uploadSlotsFull:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .placeInLineRequest:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .placeInLineResponse:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .roomAdded:
            handleRoomAdded(payload)
        case .roomRemoved:
            handleRoomRemoved(payload)
        case .roomUnknown153:
            handleProtocolNotice(code: codeValue, payload: payload)
        case .relogged:
            handleRelogged()
        case .excludedSearchPhrases:
            handleExcludedSearchPhrases(payload)
        case .roomMembershipGranted:
            handleRoomMembershipGranted(payload)
        case .roomMembershipRevoked:
            handleRoomMembershipRevoked(payload)
        case .enableRoomInvitations:
            handleEnableRoomInvitations(payload)
        case .newPassword:
            handleNewPassword(payload)
        case .globalRoomMessage:
            handleGlobalRoomMessage(payload)
        case .cantCreateRoom:
            handleCantCreateRoom(payload)
        default:
            // Log unhandled message with more detail
            logger.info("Unhandled server message: \(code.description) (code=\(codeValue)) payload=\(payload.count) bytes")
        }
    }

    // MARK: - Message Handlers

    private func handleLogin(_ data: Data) {
        guard let result = MessageParser.parseLoginResponse(data) else {
            logger.error("Failed to parse login response")
            return
        }

        switch result {
        case .success(let greeting, let ip, _):
            logger.info("Login response: success")
            logger.info("Login greeting: \(greeting)")
            logger.info("Server reports our IP: \(ip)")
            logger.info("Peers will connect to: \(ip):\(self.client?.listenPort ?? 0)")
            client?.setLoggedIn(true, message: greeting)
            ActivityLogger.shared?.logConnectionSuccess(username: client?.username ?? "unknown", server: "server.slsknet.org")

        case .failure(let reason):
            logger.error("Login failed: \(reason)")
            client?.setLoggedIn(false, message: reason)
            ActivityLogger.shared?.logConnectionFailed(reason: reason)
        }
    }

    private func handleRoomList(_ data: Data) {
        guard let info = MessageParser.parseRoomList(data) else {
            logger.warning("Failed to parse RoomList")
            return
        }

        let publicRooms = info.publicRooms.map { chatRoom(from: $0) }
        let ownedPrivate = info.ownedPrivate.map { chatRoom(from: $0, isPrivate: true) }
        let memberPrivate = info.memberPrivate.map { chatRoom(from: $0, isPrivate: true) }

        if let fullHandler = client?.onRoomListFull {
            fullHandler(publicRooms, ownedPrivate, memberPrivate, info.operatedPrivate)
        } else {
            client?.onRoomList?(publicRooms)
        }
    }

    /// ChatRoom only carries a name + users array; we surface user *count* by
    /// seeding empty placeholder strings (the full user list arrives on
    /// JoinRoom). Matches the previous legacy behaviour.
    private func chatRoom(from entry: MessageParser.RoomListEntry, isPrivate: Bool = false) -> ChatRoom {
        let placeholders = Array(repeating: "", count: Int(entry.userCount))
        return ChatRoom(name: entry.name, users: placeholders, isPrivate: isPrivate)
    }

    private func handleJoinRoom(_ data: Data) {
        guard let info = MessageParser.parseJoinRoom(data) else {
            logger.warning("Failed to parse JoinRoom")
            return
        }
        client?.onRoomJoined?(info.roomName, info.users, info.owner, info.operators)
        ActivityLogger.shared?.logRoomJoined(room: info.roomName, userCount: info.users.count)
    }

    private func handleLeaveRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        client?.onRoomLeft?(roomName)
        ActivityLogger.shared?.logRoomLeft(room: roomName)
    }

    private func handleSayInRoom(_ data: Data) {
        guard let info = MessageParser.parseSayInChatRoom(data) else { return }
        let chatMessage = ChatMessage(
            username: info.username,
            content: info.message,
            isOwn: info.username == client?.username
        )
        client?.onRoomMessage?(info.roomName, chatMessage)
    }

    private func handleUserJoinedRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let (username, _) = data.readString(at: offset) else { return }

        client?.onUserJoinedRoom?(roomName, username)
    }

    private func handleUserLeftRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let (username, _) = data.readString(at: offset) else { return }

        client?.onUserLeftRoom?(roomName, username)
    }

    private func handlePrivateMessage(_ data: Data) {
        guard let info = MessageParser.parsePrivateMessage(data) else { return }

        let chatMessage = ChatMessage(
            id: UUID(),
            messageId: info.id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(info.timestamp)),
            username: info.username,
            content: info.message,
            isSystem: false,
            isOwn: false,
            isNewMessage: info.isNewMessage
        )

        client?.onPrivateMessage?(info.username, chatMessage)

        Task {
            await acknowledgePrivateMessage(info.id)
        }
    }

    private func acknowledgePrivateMessage(_ messageId: UInt32) async {
        await client?.acknowledgePrivateMessage(messageId: messageId)
    }

    private func handleGetUserAddress(_ data: Data) {
        var offset = 0

        guard let (username, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let ip = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let port = data.readUInt32(at: offset) else { return }

        let ipAddress = ipString(from: ip)

        // Cache IP for country lookup
        client?.userInfoCache.registerIP(ipAddress, for: username)

        // Use internal handler that dispatches to both pending requests AND external callback
        client?.handlePeerAddressResponse(username: username, ip: ipAddress, port: Int(port))
    }

    private func handleWatchUser(_ data: Data) {
        guard let info = MessageParser.parseWatchUser(data) else { return }

        guard info.exists else {
            Task { @MainActor in
                self.client?.handleUserStatusResponse(username: info.username, status: .offline, privileged: false)
            }
            return
        }

        let status = info.status ?? .offline
        let avgSpeed = info.avgSpeed ?? 0
        let uploadNum = info.uploadNum ?? 0
        let files = info.files ?? 0
        let dirs = info.dirs ?? 0

        Task { @MainActor in
            self.client?.handleUserStatusResponse(username: info.username, status: status, privileged: false)
            self.client?.dispatchUserStats(username: info.username, avgSpeed: avgSpeed, uploadNum: UInt64(uploadNum), files: files, dirs: dirs)
        }

        if let country = info.countryCode {
            logger.debug("WatchUser country for \(info.username): \(country)")
            // Seed the geoip cache so the flag lights up immediately instead of
            // round-tripping through an IP → country lookup.
            client?.userInfoCache.seedCountry(country, for: info.username)
        }
    }

    private func handleGetUserStatus(_ data: Data) {
        guard let info = MessageParser.parseGetUserStatus(data) else { return }
        logger.info("User \(info.username) status: \(info.status.description), privileged: \(info.privileged)")
        Task { @MainActor in
            self.client?.handleUserStatusResponse(username: info.username, status: info.status, privileged: info.privileged)
        }
    }

    // Track pending connections to avoid duplicates
    private var pendingConnections: Set<String> = []
    private var connectToPeerCount = 0
    private var hasWarnedAboutListener = false

    // Rate limiting for outbound connections
    private var lastConnectionAttempt = Date.distantPast
    private let connectionRateLimit: TimeInterval = 0.05  // Max 20 connections per second
    private var connectionQueue: [(username: String, type: String, ip: String, port: UInt32, token: UInt32)] = []
    private var isProcessingQueue = false

    private func handleConnectToPeer(_ data: Data) {
        guard let info = MessageParser.parseConnectToPeer(data) else { return }

        let username = info.username
        let ipAddress = info.ip
        let port = info.port
        let token = info.token
        let connectionType = info.connectionType

        connectToPeerCount += 1

        // Update the pool's counter for diagnostics UI
        client?.peerConnectionPool.incrementConnectToPeerCount()

        // Log sparingly to reduce noise
        if connectToPeerCount <= 5 || connectToPeerCount % 100 == 0 {
            logger.info("ConnectToPeer #\(self.connectToPeerCount): \(username) type=\(connectionType)")
        }

        // If we're getting tons of ConnectToPeer, our listener isn't reachable
        if connectToPeerCount == 100 && !hasWarnedAboutListener {
            hasWarnedAboutListener = true
            logger.warning("Received 100+ ConnectToPeer requests - your listen port may not be reachable!")
        }

        // Skip invalid addresses (peer behind NAT without reachable port)
        if port == 0 || ipAddress == "0.0.0.0" {
            return
        }

        // Limit queue size to prevent unbounded memory growth
        if connectionQueue.count >= 100 {
            return // Queue is full
        }

        let connectionKey = "\(username)-\(token)"
        if pendingConnections.contains(connectionKey) {
            return
        }

        // Queue the connection with rate limiting instead of firing immediately
        connectionQueue.append((username, connectionType, ipAddress, port, token))
        processConnectionQueue()
    }

    private func processConnectionQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        Task {
            while !connectionQueue.isEmpty {
                // Rate limit: wait if we connected too recently
                let timeSinceLastConnection = Date().timeIntervalSince(lastConnectionAttempt)
                if timeSinceLastConnection < connectionRateLimit {
                    let waitTime = connectionRateLimit - timeSinceLastConnection
                    try? await Task.sleep(for: .milliseconds(Int(waitTime * 1000)))
                }

                guard !connectionQueue.isEmpty else { break }

                let next = connectionQueue.removeFirst()
                lastConnectionAttempt = Date()

                let connectionKey = "\(next.username)-\(next.token)"
                if pendingConnections.contains(connectionKey) {
                    continue
                }
                pendingConnections.insert(connectionKey)

                await connectToPeerThrottled(
                    username: next.username,
                    connectionType: next.type,
                    ip: next.ip,
                    port: next.port,
                    token: next.token
                )

                pendingConnections.remove(connectionKey)
            }
            isProcessingQueue = false
        }
    }

    private func connectToPeerThrottled(username: String, connectionType: String, ip: String, port: UInt32, token: UInt32) async {
        logger.debug("connectToPeerThrottled START: \(username) at \(ip):\(port)")
        do {
            guard let pool = client?.peerConnectionPool else {
                logger.error("connectToPeerThrottled: pool is nil")
                return
            }

            // For ConnectToPeer responses, use isIndirect=true to skip PeerInit
            // We'll send PierceFirewall instead (correct protocol for indirect connections)
            logger.debug("connectToPeerThrottled: calling pool.connect with 10s timeout...")
            let connection = try await withTimeout(seconds: 10) {
                let conn = try await pool.connect(
                    to: username,
                    ip: ip,
                    port: Int(port),
                    token: token,
                    isIndirect: true
                )
                return conn
            }
            logger.debug("connectToPeerThrottled: connection established, sending PierceFirewall...")

            try await connection.sendPierceFirewall()
            // Announce ourselves as a SeeleSeek client on P-type sockets only.
            // F-type flips to raw file-transfer bytes after PierceFirewall and
            // would misinterpret an extra 13-byte message as file data.
            if connectionType == "P" {
                try? await connection.sendSeeleSeekHandshake()
            }
            logger.info("connectToPeerThrottled SUCCESS: \(username)")

        } catch {
            logger.error("connectToPeerThrottled FAILED: \(username) - \(error)")
            await client?.sendCantConnectToPeer(token: token, username: username)
        }
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                do {
                    let result = try await operation()
                    return result
                } catch {
                    throw error
                }
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

    // MARK: - Distributed Network Handlers

    private func handlePossibleParents(_ data: Data) {
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

        // Try to connect to first few parents until one succeeds (limit to avoid resource exhaustion)
        Task {
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

    private var distributedParentConnection: PeerConnection?

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
            if let myUsername = client?.username {
                try await connection.sendPeerInit(username: myUsername)
            }

            logger.info("Connected to distributed parent: \(username)")

            // Disconnect old parent before storing new one
            if let oldParent = distributedParentConnection {
                logger.info("Disconnecting old distributed parent")
                await oldParent.disconnect()
            }

            // Store the connection to keep it alive
            distributedParentConnection = connection

            // Consume distributed messages from the connection's event stream
            let parentUsername = username
            Task { [weak self] in
                for await event in connection.events {
                    guard let self else { return }
                    if case .message(let code, let payload) = event {
                        await self.handleDistributedMessage(code: code, payload: payload, parentUsername: parentUsername)
                    }
                }
            }

            // Tell server we have a parent now
            do {
                try await client?.sendHaveNoParent(false)
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

    private func handleDistributedMessage(code: UInt32, payload: Data, parentUsername: String = "") async {
        logger.debug("Distributed message received: code=\(code) size=\(payload.count)")

        // Distributed messages use the same codes as DistributedMessageCode
        switch code {
        case UInt32(DistributedMessageCode.branchLevel.rawValue):
            // uint32 branch level from parent
            if let parentLevel = payload.readUInt32(at: 0) {
                let ourLevel = parentLevel + 1
                logger.info("Parent branch level: \(parentLevel), our level: \(ourLevel)")

                // Report our level to server and propagate to children
                Task {
                    try? await client?.setDistributedBranchLevel(ourLevel)

                    // If parent is level 0, they ARE the branch root
                    if parentLevel == 0 {
                        logger.info("Parent is branch root: \(parentUsername)")
                        try? await client?.setDistributedBranchRoot(parentUsername)

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
                    try? await client?.setDistributedBranchRoot(rootUsername)

                    let ourLevel = client?.distributedBranchLevel ?? 0
                    await sendBranchInfoToChildren(level: ourLevel, root: rootUsername)
                }
            }

        case UInt32(DistributedMessageCode.searchRequest.rawValue):
            // This is a search request from the distributed network
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
        guard let children = client?.distributedChildren, !children.isEmpty else { return }

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

    private func handleEmbeddedMessage(_ data: Data) {
        // Server sends us an embedded distributed message (when we're a branch root)
        // Format: uint8 distrib_code + message payload
        guard let distribCode = data.readByte(at: 0) else { return }

        let payload = data.safeSubdata(in: 1..<data.count) ?? Data()

        logger.debug("Received embedded distributed message: code=\(distribCode) size=\(payload.count)")

        if distribCode == DistributedMessageCode.searchRequest.rawValue {
            // This is a distributed search - we should check our files and respond
            handleDistributedSearch(payload)
        }
    }

    private func handleDistributedSearch(_ data: Data) {
        guard let info = MessageParser.parseDistributedSearch(data) else { return }
        let unknown = info.unknown
        let username = info.username
        let token = info.token
        let query = info.query

        logger.debug("Distributed search from \(username): '\(query)' token=\(token)")

        // Forward to children
        Task {
            await client?.forwardDistributedSearch(unknown: unknown, username: username, token: token, query: query)
        }

        // Don't respond to our own searches
        guard username != client?.username else { return }

        // Apply search response filters
        let filter = client?.searchResponseFilter?() ?? (enabled: true, minQueryLength: 3, maxResults: 50)

        guard filter.enabled else {
            return
        }

        // Filter short queries (they match too broadly and waste bandwidth)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard trimmedQuery.count >= filter.minQueryLength else {
            return
        }

        // Search our shared files. The search itself hops off the main
        // actor (see ShareManager.search), so the remaining work after
        // the scan can stay on whatever actor this handler already runs
        // on — we just need a Task boundary to await the async call.
        guard let shareManager = client?.shareManager else {
            logger.debug("No share manager available for distributed search")
            return
        }
        let maxResults = filter.maxResults

        Task {
            var matchingFiles = await shareManager.search(query: query)
            guard !matchingFiles.isEmpty else { return }

            if maxResults > 0 && matchingFiles.count > maxResults {
                matchingFiles = Array(matchingFiles.prefix(maxResults))
            }

            logger.info("Distributed search '\(query)' from \(username): \(matchingFiles.count) matches")
            ActivityLogger.shared?.logDistributedSearch(query: query, matchCount: matchingFiles.count)

            await sendDistributedSearchResponse(
                to: username,
                token: token,
                files: matchingFiles
            )
        }
    }

    private func sendDistributedSearchResponse(
        to username: String,
        token: UInt32,
        files: [ShareManager.IndexedFile]
    ) async {
        guard let client else { return }

        // Build results once (shared by direct and indirect paths)
        let results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] = files.map { file in
            var attributes: [(UInt32, UInt32)] = []
            if let bitrate = file.bitrate {
                attributes.append((0, bitrate))
            }
            if let duration = file.duration {
                attributes.append((1, duration))
            }
            return (
                filename: file.sharedPath,
                size: file.size,
                extension_: file.fileExtension,
                attributes: attributes
            )
        }

        // Race direct and indirect connections simultaneously for faster delivery
        let indirectToken = UInt32.random(in: 0...UInt32.max)

        // Register pending indirect BEFORE starting anything (to catch early PierceFirewall)
        client.registerPendingBrowse(token: indirectToken, username: username, timeout: 15)
        await client.sendConnectToPeer(token: indirectToken, username: username, connectionType: "P")

        do {
            let connection: PeerConnection = try await withThrowingTaskGroup(of: PeerConnection.self) { group in
                // Direct path: get address + connect + handshake
                group.addTask {
                    let address = try await client.getPeerAddress(for: username, timeout: .seconds(5))
                    let connectionToken = UInt32.random(in: 0...UInt32.max)
                    let conn = try await client.peerConnectionPool.connect(
                        to: username,
                        ip: address.ip,
                        port: address.port,
                        token: connectionToken
                    )
                    try await conn.waitForPeerHandshake(timeout: .seconds(8))
                    return conn
                }

                // Indirect path: wait for PierceFirewall
                group.addTask {
                    let conn = try await client.waitForPendingBrowse(token: indirectToken)
                    await conn.resumeReceivingForPeerConnection()
                    // PierceFirewall IS the handshake for indirect connections -- do NOT send PeerInit
                    return conn
                }

                // Timeout: give up after 12s
                group.addTask {
                    try await Task.sleep(for: .seconds(12))
                    throw NetworkError.timeout
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            // Cancel the pending indirect if we got direct
            client.cancelPendingBrowse(token: indirectToken)

            try await connection.sendSearchReply(
                username: client.username,
                token: token,
                results: results
            )
            logger.info("Sent \(files.count) search results to \(username) for token \(token)")
        } catch {
            client.cancelPendingBrowse(token: indirectToken)
            logger.debug("Search result delivery to \(username) failed: \(error.localizedDescription)")
        }
    }

    private func handleResetDistributed() {
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
            await client?.resetDistributedNetwork()
        }
    }

    private func handleParentMinSpeed(_ data: Data) {
        guard let speed = data.readUInt32(at: 0) else { return }
        logger.debug("Parent minimum speed: \(speed)")
    }

    private func handleParentSpeedRatio(_ data: Data) {
        guard let ratio = data.readUInt32(at: 0) else { return }
        logger.debug("Parent speed ratio: \(ratio)")
    }

    // MARK: - Excluded Search Phrases

    private func handleExcludedSearchPhrases(_ data: Data) {
        guard let phrases = MessageParser.parseExcludedSearchPhrases(data) else { return }
        logger.info("Received \(phrases.count) excluded search phrases")
        client?.onExcludedSearchPhrases?(phrases)
    }

    // MARK: - Room Membership & Invitations

    private func handleRoomMembershipGranted(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Room membership granted: \(room)")
        client?.onRoomMembershipGranted?(room)
    }

    private func handleRoomMembershipRevoked(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Room membership revoked: \(room)")
        client?.onRoomMembershipRevoked?(room)
    }

    private func handleEnableRoomInvitations(_ data: Data) {
        guard let enabled = data.readBool(at: 0) else { return }
        logger.info("Room invitations enabled: \(enabled)")
        client?.onRoomInvitationsEnabled?(enabled)
    }

    private func handleNewPassword(_ data: Data) {
        guard let (password, _) = data.readString(at: 0) else { return }
        logger.info("Password changed confirmation received")
        client?.onPasswordChanged?(password)
    }

    // MARK: - Global Room Messages

    private func handleGlobalRoomMessage(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let (message, _) = data.readString(at: offset) else { return }

        logger.info("Global room message in \(room) from \(username): \(message)")
        client?.onGlobalRoomMessage?(room, username, message)
    }

    // MARK: - User Interests & Recommendations

    private func handleRecommendations(_ data: Data) {
        guard let info = MessageParser.parseRecommendations(data) else { return }
        let recommendations = info.recommendations.map { (item: $0.item, score: $0.score) }
        let unrecommendations = info.unrecommendations.map { (item: $0.item, score: $0.score) }
        logger.info("Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        client?.onRecommendations?(recommendations, unrecommendations)
    }

    private func handleGlobalRecommendations(_ data: Data) {
        guard let info = MessageParser.parseRecommendations(data) else { return }
        let recommendations = info.recommendations.map { (item: $0.item, score: $0.score) }
        let unrecommendations = info.unrecommendations.map { (item: $0.item, score: $0.score) }
        logger.info("Global Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        client?.onGlobalRecommendations?(recommendations, unrecommendations)
    }

    private func handleUserInterests(_ data: Data) {
        guard let info = MessageParser.parseUserInterests(data) else { return }
        logger.info("User \(info.username) interests - likes: \(info.likes.count), hates: \(info.hates.count)")
        client?.onUserInterests?(info.username, info.likes, info.hates)
    }

    private func handleSimilarUsers(_ data: Data) {
        guard let parsed = MessageParser.parseSimilarUsers(data) else { return }
        let users = parsed.map { (username: $0.username, rating: $0.rating) }
        logger.info("Similar users: \(users.count)")
        client?.onSimilarUsers?(users)
    }

    private func handleItemRecommendations(_ data: Data) {
        var offset = 0

        guard let (item, itemLen) = data.readString(at: offset) else { return }
        offset += itemLen

        guard let recCount = data.readUInt32(at: offset) else { return }
        guard recCount <= maxItemCount else { return }
        offset += 4

        var recommendations: [(item: String, score: Int32)] = []
        for _ in 0..<recCount {
            guard let (recItem, recLen) = data.readString(at: offset) else { break }
            offset += recLen
            guard let score = data.readInt32(at: offset) else { break }
            offset += 4
            recommendations.append((recItem, score))
        }

        logger.info("Item recommendations for '\(item)': \(recommendations.count)")
        client?.onItemRecommendations?(item, recommendations)
    }

    private func handleItemSimilarUsers(_ data: Data) {
        var offset = 0

        guard let (item, itemLen) = data.readString(at: offset) else { return }
        offset += itemLen

        guard let userCount = data.readUInt32(at: offset) else { return }
        guard userCount <= maxItemCount else { return }
        offset += 4

        var users: [String] = []
        for _ in 0..<userCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            users.append(username)
            offset += usernameLen
        }

        logger.info("Similar users for '\(item)': \(users.count)")
        client?.onItemSimilarUsers?(item, users)
    }

    // MARK: - User Stats & Privileges

    private func handleGetUserStats(_ data: Data) {
        guard let info = MessageParser.parseGetUserStats(data) else { return }
        logger.info("User stats for \(info.username): speed=\(info.avgSpeed), uploads=\(info.uploadNum), files=\(info.files), dirs=\(info.dirs)")
        client?.dispatchUserStats(username: info.username, avgSpeed: info.avgSpeed, uploadNum: UInt64(info.uploadNum), files: info.files, dirs: info.dirs)
    }

    private func handleCheckPrivileges(_ data: Data) {
        guard let timeLeft = data.readUInt32(at: 0) else { return }
        logger.info("Privileges time remaining: \(timeLeft) seconds")
        client?.onPrivilegesChecked?(timeLeft)
    }

    private func handleUserPrivileges(_ data: Data) {
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let privileged = data.readBool(at: offset) else { return }

        logger.info("User \(username) privileged: \(privileged)")
        client?.onUserPrivileges?(username, privileged)
    }

    private func handlePrivilegedUsers(_ data: Data) {
        var offset = 0

        guard let userCount = data.readUInt32(at: offset) else { return }
        guard userCount <= maxItemCount else { return }
        offset += 4

        var users: [String] = []
        for _ in 0..<userCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            users.append(username)
            offset += usernameLen
        }

        logger.info("Privileged users: \(users.count)")
        client?.onPrivilegedUsers?(users)
    }

    // MARK: - Room Tickers

    private func handleRoomTickerState(_ data: Data) {
        guard let info = MessageParser.parseRoomTickerState(data) else { return }
        let tickers = info.tickers.map { (username: $0.username, ticker: $0.ticker) }
        logger.info("Room ticker state for \(info.room): \(tickers.count) tickers")
        client?.onRoomTickerState?(info.room, tickers)
    }

    private func handleRoomTickerAdd(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let (ticker, _) = data.readString(at: offset) else { return }

        logger.info("Room ticker added in \(room): \(username) = '\(ticker)'")
        client?.onRoomTickerAdd?(room, username, ticker)
    }

    private func handleRoomTickerRemove(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Room ticker removed in \(room): \(username)")
        client?.onRoomTickerRemove?(room, username)
    }

    // MARK: - Wishlist

    private func handleWishlistInterval(_ data: Data) {
        guard let interval = data.readUInt32(at: 0) else { return }
        logger.info("Wishlist interval: \(interval) seconds")
        client?.onWishlistInterval?(interval)
    }

    // MARK: - Private Rooms

    private func handlePrivateRoomMembers(_ data: Data) {
        guard let info = MessageParser.parseRoomMembers(data) else { return }
        logger.info("Private room \(info.room) members: \(info.members.count)")
        client?.onPrivateRoomMembers?(info.room, info.members)
    }

    private func handlePrivateRoomAddMember(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Private room \(room) member added: \(username)")
        client?.onPrivateRoomMemberAdded?(room, username)
    }

    private func handlePrivateRoomRemoveMember(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Private room \(room) member removed: \(username)")
        client?.onPrivateRoomMemberRemoved?(room, username)
    }

    private func handlePrivateRoomOperatorGranted(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Granted operator in room: \(room)")
        client?.onPrivateRoomOperatorGranted?(room)
    }

    private func handlePrivateRoomOperatorRevoked(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Revoked operator in room: \(room)")
        client?.onPrivateRoomOperatorRevoked?(room)
    }

    private func handlePrivateRoomOperators(_ data: Data) {
        guard let info = MessageParser.parseRoomMembers(data) else { return }
        logger.info("Private room \(info.room) operators: \(info.members.count)")
        client?.onPrivateRoomOperators?(info.room, info.members)
    }

    private func handleCantConnectToPeer(_ data: Data) {
        // Server tells us the peer couldn't connect to us
        // Format: uint32 token
        guard let token = data.readUInt32(at: 0) else {
            logger.warning("Failed to parse CantConnectToPeer token")
            return
        }

        logger.warning("CantConnectToPeer token=\(token) — peer couldn't reach our listen port")
        client?.onCantConnectToPeer?(token)
    }

    private func handleAdminMessage(_ data: Data) {
        // Server Code 66 - Global/Admin Message
        // A global message from the server admin has arrived
        let offset = 0
        guard let (message, _) = data.readString(at: offset) else {
            logger.warning("Failed to parse AdminMessage")
            return
        }

        logger.info("Admin message from server: \(message)")

        // Notify the client about the admin message
        client?.onAdminMessage?(message)
    }

    // MARK: - Relogged

    private func handleRelogged() {
        logger.warning("Relogged: kicked from server because another client logged in with the same credentials")
        ActivityLogger.shared?.logRelogged()
        client?.handleReloggedDisconnect()
    }

    // MARK: - Can't Create Room

    private func handleCantCreateRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        logger.warning("Can't create room: \(roomName)")
        client?.onCantCreateRoom?(roomName)
    }

    private func handleRoomAdded(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else {
            handleProtocolNotice(code: ServerMessageCode.roomAdded.rawValue, payload: data)
            return
        }
        logger.info("Room added: \(roomName)")
        client?.onRoomAdded?(roomName)
    }

    private func handleRoomRemoved(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else {
            handleProtocolNotice(code: ServerMessageCode.roomRemoved.rawValue, payload: data)
            return
        }
        logger.info("Room removed: \(roomName)")
        client?.onRoomRemoved?(roomName)
    }

    private func handleProtocolNotice(code: UInt32, payload: Data) {
        // Centralized handling for protocol codes that are recognized but not yet fully modeled.
        // Keeps parity explicit and provides a single callback surface for future feature wiring.
        let preview = payload.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.info("Protocol notice: code=\(code) payload=\(payload.count) bytes preview=\(preview)")
        client?.onProtocolNotice?(code, payload)
    }

    // MARK: - Helpers

    private func ipString(from value: UInt32) -> String {
        // Soulseek sends IP addresses in network byte order (big-endian)
        // High byte is the first octet
        let b1 = (value >> 24) & 0xFF
        let b2 = (value >> 16) & 0xFF
        let b3 = (value >> 8) & 0xFF
        let b4 = value & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}
