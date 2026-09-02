import Foundation
import os

/// Maximum element count accepted from list-bearing server messages —
/// a corrupt or hostile frame must not make us allocate unbounded arrays.
private let maxItemCount: UInt32 = 100_000

// MARK: - Server Message Handling
//
// Same-isolation with the rest of the actor by construction: the receive
// loop awaits each message to completion before reading the next frame,
// so nothing here interleaves with other client work mid-message.
extension NetworkClient {
    func handleServerMessage(_ data: Data) async {
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
        // Per-message trace — .debug so it's visible when diagnosing
        // protocol issues but doesn't flood steady-state logs (fires
        // on every inbound server frame).
        logger.debug("Received message: code=\(codeValue) (\(code?.description ?? "unknown")) length=\(messageLength)")

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
            logger.info("Peers will connect to: \(ip):\(self.listenPort)")
            self.setLoggedIn(true, message: greeting)
            let currentUsername = username
            let server = serverHost ?? "unknown"
            Task { @MainActor in
                ActivityLogger.shared?.logConnectionSuccess(username: currentUsername, server: server)
            }

        case .failure(let reason):
            logger.error("Login failed: \(reason)")
            self.setLoggedIn(false, message: reason)
            Task { @MainActor in ActivityLogger.shared?.logConnectionFailed(reason: reason) }
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

        self.emit(.roomList(
            publicRooms: publicRooms,
            ownedPrivate: ownedPrivate,
            memberPrivate: memberPrivate,
            operated: info.operatedPrivate
        ))
    }

    /// ChatRoom only carries a name + users array; we surface user *count* by
    /// seeding empty placeholder strings (the full user list arrives on
    /// JoinRoom).
    private func chatRoom(from entry: MessageParser.RoomListEntry, isPrivate: Bool = false) -> ChatRoom {
        let placeholders = Array(repeating: "", count: Int(entry.userCount))
        return ChatRoom(name: entry.name, users: placeholders, isPrivate: isPrivate)
    }

    private func handleJoinRoom(_ data: Data) {
        guard let info = MessageParser.parseJoinRoom(data) else {
            logger.warning("Failed to parse JoinRoom")
            return
        }
        self.emit(.roomJoined(room: info.roomName, users: info.users, owner: info.owner, operators: info.operators))
        Task { @MainActor [roomName = info.roomName, userCount = info.users.count] in
            ActivityLogger.shared?.logRoomJoined(room: roomName, userCount: userCount)
        }
    }

    private func handleLeaveRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        self.emit(.roomLeft(room: roomName))
        Task { @MainActor in ActivityLogger.shared?.logRoomLeft(room: roomName) }
    }

    private func handleSayInRoom(_ data: Data) {
        guard let info = MessageParser.parseSayInChatRoom(data) else { return }
        let chatMessage = ChatMessage(
            username: info.username,
            content: info.message,
            isOwn: info.username == self.username
        )
        self.emit(.roomMessage(room: info.roomName, message: chatMessage))
    }

    private func handleUserJoinedRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let (username, _) = data.readString(at: offset) else { return }

        self.emit(.userJoinedRoom(room: roomName, username: username))
    }

    private func handleUserLeftRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let (username, _) = data.readString(at: offset) else { return }

        self.emit(.userLeftRoom(room: roomName, username: username))
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

        self.emit(.privateMessage(username: info.username, message: chatMessage))

        Task {
            await acknowledgePrivateMessage(messageId: info.id)
        }
    }

    private func handleGetUserAddress(_ data: Data) {
        var offset = 0

        guard let (username, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let ip = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let port = data.readUInt32(at: offset) else { return }
        offset += 4

        // Optional obfuscation block per the server protocol:
        //   uint32 obfuscation_type  (0 = none, 1 = rotated)
        //   uint16 obfuscated_port
        // Note the asymmetry with SetWaitPort, which uses uint32 for the
        // obfuscated port. Only treat the advertised port as real when the
        // type is rotated — a `none` type with a non-zero port would be a
        // malformed reply.
        var obfuscatedPort: Int = 0
        if let obfType = data.readUInt32(at: offset), obfType == ObfuscationType.rotated.rawValue,
           let obfPort = data.readUInt16(at: offset + 4) {
            obfuscatedPort = Int(obfPort)
        }

        let ipAddress = ipString(from: ip)

        // Cache IP for country lookup
        Task { @MainActor [cache = userInfoCache] in
            cache.registerIP(ipAddress, for: username)
        }

        self.handlePeerAddressResponse(username: username, ip: ipAddress, port: Int(port), obfuscatedPort: obfuscatedPort)
    }

    private func handleWatchUser(_ data: Data) {
        guard let info = MessageParser.parseWatchUser(data) else { return }

        guard info.exists else {
            self.handleUserStatusResponse(username: info.username, status: .offline, privileged: nil)
            return
        }

        let status = info.status ?? .offline
        let avgSpeed = info.avgSpeed ?? 0
        let uploadNum = info.uploadNum ?? 0
        let files = info.files ?? 0
        let dirs = info.dirs ?? 0

        // WatchUser replies don't carry privileged — nil keeps the
        // last server-reported value instead of fabricating false.
        // Direct call: a Task hop here would allow reordering against
        // later messages.
        self.handleUserStatusResponse(username: info.username, status: status, privileged: nil)
        self.emit(.userStats(username: info.username, avgSpeed: avgSpeed, uploadNum: UInt64(uploadNum), files: files, dirs: dirs))

        if let country = info.countryCode {
            logger.debug("WatchUser country for \(info.username): \(country)")
            // Seed the geoip cache so the flag lights up immediately instead of
            // round-tripping through an IP → country lookup.
            Task { @MainActor [cache = userInfoCache, username = info.username] in
                cache.seedCountry(country, for: username)
            }
        }
    }

    private func handleGetUserStatus(_ data: Data) {
        guard let info = MessageParser.parseGetUserStatus(data) else { return }
        logger.info("User \(info.username) status: \(info.status.description), privileged: \(info.privileged)")
        // Direct call — a Task hop would allow reordering.
        self.handleUserStatusResponse(username: info.username, status: info.status, privileged: info.privileged)
    }

    private func handleConnectToPeer(_ data: Data) {
        guard let info = MessageParser.parseConnectToPeer(data) else { return }

        let username = info.username
        let ipAddress = info.ip
        let port = info.port
        let token = info.token
        let connectionType = info.connectionType

        serverConnectToPeerCount += 1

        // Update the pool's counter for diagnostics UI
        Task { [pool = peerConnectionPool] in
            await pool.incrementConnectToPeerCount()
        }

        // Log sparingly to reduce noise
        if serverConnectToPeerCount <= 5 || serverConnectToPeerCount % 100 == 0 {
            logger.info("ConnectToPeer #\(self.serverConnectToPeerCount): \(username) type=\(connectionType)")
        }

        // If we're getting tons of ConnectToPeer, our listener isn't reachable
        if serverConnectToPeerCount == 100 && !hasWarnedAboutListener {
            hasWarnedAboutListener = true
            logger.warning("Received 100+ ConnectToPeer requests - your listen port may not be reachable!")
        }

        // Skip invalid addresses (peer behind NAT without reachable port)
        if port == 0 || ipAddress == "0.0.0.0" {
            return
        }

        // Limit queue size to prevent unbounded memory growth. Don't drop
        // silently — a full queue means peers waiting on us won't get
        // their PierceFirewall. Throttled so a storm can't flood the log.
        if connectionQueue.count >= 100 {
            droppedConnectToPeerCount += 1
            if droppedConnectToPeerCount == 1 || droppedConnectToPeerCount % 100 == 0 {
                logger.warning("ConnectToPeer queue full — dropped \(self.droppedConnectToPeerCount) request(s) so far (latest: \(username))")
            }
            return
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

        Task { [weak self] in
            await self?.drainConnectionQueue()
        }
    }

    private func drainConnectionQueue() async {
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

            // Fire-and-forget: dispatch each throttled connect to its
            // own Task so one stuck `pool.connect` (e.g. NWConnection
            // sitting in `.preparing` against a half-dead peer)
            // can't block the entire queue. Each connect attempt's
            // 10s `withTimeout` still bounds its own runtime; the
            // queue stays responsive regardless.
            Task { [weak self] in
                guard let self else { return }
                await self.connectToPeerThrottled(
                    username: next.username,
                    connectionType: next.type,
                    ip: next.ip,
                    port: next.port,
                    token: next.token
                )
                await self.clearPendingConnection(connectionKey)
            }
        }
        isProcessingQueue = false
    }

    private func clearPendingConnection(_ key: String) {
        pendingConnections.remove(key)
    }

    private func connectToPeerThrottled(username: String, connectionType: String, ip: String, port: UInt32, token: UInt32) async {
        logger.debug("connectToPeerThrottled START: \(username) at \(ip):\(port)")
        do {
            let pool = self.peerConnectionPool

            // For ConnectToPeer responses, use isIndirect=true to skip PeerInit
            // We'll send PierceFirewall instead (correct protocol for indirect connections)
            logger.debug("connectToPeerThrottled: calling pool.connect with 10s timeout...")
            let peerConnectionType: PeerConnection.ConnectionType = switch connectionType {
            case "F": .file
            case "D": .distributed
            default: .peer
            }
            let connection = try await withTimeout(seconds: 10) {
                let conn = try await pool.connect(
                    to: username,
                    ip: ip,
                    port: Int(port),
                    token: token,
                    isIndirect: true,
                    connectionType: peerConnectionType
                )
                return conn
            }
            logger.debug("connectToPeerThrottled: connection established, sending PierceFirewall...")

            try await connection.sendPierceFirewall()
            if connectionType == "F" {
                // This is the downloader side of an indirect F connection.
                // The uploader will now send the raw 4-byte FileTransferInit
                // token, so remove the socket from the framed peer pool and
                // hand it to DownloadManager before any bytes are consumed.
                await pool.handoffOutgoingFileTransfer(
                    username: username,
                    token: token,
                    connection: connection
                )
            }
            logger.info("connectToPeerThrottled SUCCESS: \(username)")

        } catch {
            logger.error("connectToPeerThrottled FAILED: \(username) - \(error)")
            await self.sendCantConnectToPeer(token: token, username: username)
        }
    }

    // MARK: - Excluded Search Phrases

    private func handleExcludedSearchPhrases(_ data: Data) {
        guard let phrases = MessageParser.parseExcludedSearchPhrases(data) else { return }
        logger.info("Received \(phrases.count) excluded search phrases")
        self.emit(.excludedPhrases(phrases))
    }

    // MARK: - Room Membership & Invitations

    private func handleRoomMembershipGranted(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Room membership granted: \(room)")
        self.emit(.roomMembershipGranted(room: room))
    }

    private func handleRoomMembershipRevoked(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Room membership revoked: \(room)")
        self.emit(.roomMembershipRevoked(room: room))
    }

    private func handleEnableRoomInvitations(_ data: Data) {
        guard let enabled = data.readBool(at: 0) else { return }
        logger.info("Room invitations enabled: \(enabled)")
        self.emit(.roomInvitationsEnabled(enabled))
    }

    private func handleNewPassword(_ data: Data) {
        guard let (password, _) = data.readString(at: 0) else { return }
        logger.info("Password changed confirmation received")
        self.emit(.passwordChanged(password))
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
        self.emit(.globalRoomMessage(room: room, username: username, message: message))
    }

    // MARK: - User Interests & Recommendations

    private func handleRecommendations(_ data: Data) {
        guard let info = MessageParser.parseRecommendations(data) else { return }
        let recommendations = info.recommendations.map { (item: $0.item, score: $0.score) }
        let unrecommendations = info.unrecommendations.map { (item: $0.item, score: $0.score) }
        logger.info("Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        self.emit(.recommendations(recommendations: recommendations, unrecommendations: unrecommendations))
    }

    private func handleGlobalRecommendations(_ data: Data) {
        guard let info = MessageParser.parseRecommendations(data) else { return }
        let recommendations = info.recommendations.map { (item: $0.item, score: $0.score) }
        let unrecommendations = info.unrecommendations.map { (item: $0.item, score: $0.score) }
        logger.info("Global Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        self.emit(.globalRecommendations(recommendations: recommendations, unrecommendations: unrecommendations))
    }

    private func handleUserInterests(_ data: Data) {
        guard let info = MessageParser.parseUserInterests(data) else { return }
        logger.info("User \(info.username) interests - likes: \(info.likes.count), hates: \(info.hates.count)")
        self.emit(.userInterests(username: info.username, likes: info.likes, hates: info.hates))
    }

    private func handleSimilarUsers(_ data: Data) {
        guard let parsed = MessageParser.parseSimilarUsers(data) else { return }
        let users = parsed.map { (username: $0.username, rating: $0.rating) }
        logger.info("Similar users: \(users.count)")
        self.emit(.similarUsers(users))
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
        self.emit(.itemRecommendations(item: item, recommendations: recommendations))
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
        self.emit(.itemSimilarUsers(item: item, users: users))
    }

    // MARK: - User Stats & Privileges

    private func handleGetUserStats(_ data: Data) {
        guard let info = MessageParser.parseGetUserStats(data) else { return }
        logger.info("User stats for \(info.username): speed=\(info.avgSpeed), uploads=\(info.uploadNum), files=\(info.files), dirs=\(info.dirs)")
        self.emit(.userStats(username: info.username, avgSpeed: info.avgSpeed, uploadNum: UInt64(info.uploadNum), files: info.files, dirs: info.dirs))
    }

    private func handleCheckPrivileges(_ data: Data) {
        guard let timeLeft = data.readUInt32(at: 0) else { return }
        logger.info("Privileges time remaining: \(timeLeft) seconds")
        self.emit(.privilegesChecked(secondsLeft: timeLeft))
    }

    private func handleUserPrivileges(_ data: Data) {
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let privileged = data.readBool(at: offset) else { return }

        logger.info("User \(username) privileged: \(privileged)")
        self.emit(.userPrivileges(username: username, privileged: privileged))
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
        self.emit(.privilegedUsers(users))
    }

    // MARK: - Room Tickers

    private func handleRoomTickerState(_ data: Data) {
        guard let info = MessageParser.parseRoomTickerState(data) else { return }
        let tickers = info.tickers.map { (username: $0.username, ticker: $0.ticker) }
        logger.info("Room ticker state for \(info.room): \(tickers.count) tickers")
        self.emit(.roomTickerState(room: info.room, tickers: tickers))
    }

    private func handleRoomTickerAdd(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let (ticker, _) = data.readString(at: offset) else { return }

        logger.info("Room ticker added in \(room): \(username) = '\(ticker)'")
        self.emit(.roomTickerAdd(room: room, username: username, ticker: ticker))
    }

    private func handleRoomTickerRemove(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Room ticker removed in \(room): \(username)")
        self.emit(.roomTickerRemove(room: room, username: username))
    }

    // MARK: - Wishlist

    private func handleWishlistInterval(_ data: Data) {
        guard let interval = data.readUInt32(at: 0) else { return }
        logger.info("Wishlist interval: \(interval) seconds")
        self.emit(.wishlistInterval(seconds: interval))
    }

    // MARK: - Private Rooms

    private func handlePrivateRoomMembers(_ data: Data) {
        guard let info = MessageParser.parseRoomMembers(data) else { return }
        logger.info("Private room \(info.room) members: \(info.members.count)")
        self.emit(.privateRoomMembers(room: info.room, members: info.members))
    }

    private func handlePrivateRoomAddMember(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Private room \(room) member added: \(username)")
        self.emit(.privateRoomMemberAdded(room: room, username: username))
    }

    private func handlePrivateRoomRemoveMember(_ data: Data) {
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let (username, _) = data.readString(at: offset) else { return }

        logger.info("Private room \(room) member removed: \(username)")
        self.emit(.privateRoomMemberRemoved(room: room, username: username))
    }

    private func handlePrivateRoomOperatorGranted(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Granted operator in room: \(room)")
        self.emit(.privateRoomOperatorGranted(room: room))
    }

    private func handlePrivateRoomOperatorRevoked(_ data: Data) {
        guard let (room, _) = data.readString(at: 0) else { return }
        logger.info("Revoked operator in room: \(room)")
        self.emit(.privateRoomOperatorRevoked(room: room))
    }

    private func handlePrivateRoomOperators(_ data: Data) {
        guard let info = MessageParser.parseRoomMembers(data) else { return }
        logger.info("Private room \(info.room) operators: \(info.members.count)")
        self.emit(.privateRoomOperators(room: info.room, operators: info.members))
    }

    private func handleCantConnectToPeer(_ data: Data) {
        // Server tells us the peer couldn't connect to us
        // Format: uint32 token
        guard let token = data.readUInt32(at: 0) else {
            logger.warning("Failed to parse CantConnectToPeer token")
            return
        }

        logger.warning("CantConnectToPeer token=\(token) — peer couldn't reach our listen port")
        // Fail the pending browse directly (idempotent) — waiting out the
        // full registration timeout instead would hang every failed
        // indirect connection.
        self.failPendingBrowse(token: token, reason: "peer could not connect to us (CantConnectToPeer)")
        self.emit(.cantConnectToPeer(token: token))
    }

    private func handleAdminMessage(_ data: Data) {
        guard let (message, _) = data.readString(at: 0) else {
            logger.warning("Failed to parse AdminMessage")
            return
        }
        logger.info("Admin message from server: \(message)")
        self.emit(.adminMessage(message))
    }

    // MARK: - Relogged

    private func handleRelogged() {
        logger.warning("Relogged: kicked from server because another client logged in with the same credentials")
        Task { @MainActor in ActivityLogger.shared?.logRelogged() }
        self.handleReloggedDisconnect()
    }

    // MARK: - Can't Create Room

    private func handleCantCreateRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        logger.warning("Can't create room: \(roomName)")
        self.emit(.cantCreateRoom(room: roomName))
    }

    private func handleRoomAdded(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else {
            handleProtocolNotice(code: ServerMessageCode.roomAdded.rawValue, payload: data)
            return
        }
        logger.info("Room added: \(roomName)")
        self.emit(.roomAdded(room: roomName))
    }

    private func handleRoomRemoved(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else {
            handleProtocolNotice(code: ServerMessageCode.roomRemoved.rawValue, payload: data)
            return
        }
        logger.info("Room removed: \(roomName)")
        self.emit(.roomRemoved(room: roomName))
    }

    private func handleProtocolNotice(code: UInt32, payload: Data) {
        // Centralized handling for protocol codes that are recognized but not yet fully modeled.
        // Keeps parity explicit and provides a single callback surface for future feature wiring.
        let preview = payload.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.info("Protocol notice: code=\(code) payload=\(payload.count) bytes preview=\(preview)")
        self.emit(.protocolNotice(code: code, payload: payload))
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
