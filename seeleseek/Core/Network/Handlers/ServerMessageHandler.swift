import Foundation
import os

/// Handles incoming server messages and dispatches to appropriate callbacks
@MainActor
final class ServerMessageHandler {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ServerMessageHandler")
    private weak var client: NetworkClient?
    private let maxItemCount: UInt32 = 100_000

    init(client: NetworkClient) {
        self.client = client
    }

    func handle(_ data: Data) async {
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

        let payload = data.safeSubdata(in: 8..<Int(messageLength + 4)) ?? Data()

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
        var offset = 0

        // Success byte
        guard let success = data.readByte(at: offset) else {
            logger.error("Failed to read login success byte")
            return
        }
        offset += 1

        logger.info("Login response: success=\(success)")

        if success == 1 {
            // Login successful
            // Read greeting message
            var greeting = ""
            if let (greetingStr, bytesConsumed) = data.readString(at: offset) {
                offset += bytesConsumed
                greeting = greetingStr
                logger.info("Login greeting: \(greeting)")
            }

            // Read IP address - this is critical for debugging
            if let ip = data.readUInt32(at: offset) {
                offset += 4
                let ipStr = self.ipString(from: ip)
                logger.info("Server reports our IP: \(ipStr)")
                logger.info("Peers will connect to: \(ipStr):\(self.client?.listenPort ?? 0)")
                logger.info("Server reports IP: \(ipStr)")
            }

            client?.setLoggedIn(true, message: greeting)
            ActivityLog.shared.logConnectionSuccess(username: client?.username ?? "unknown", server: "server.slsknet.org")
        } else {
            // Login failed - read reason
            if let (reason, _) = data.readString(at: offset) {
                logger.error("Login failed: \(reason)")
                client?.setLoggedIn(false, message: reason)
                ActivityLog.shared.logConnectionFailed(reason: reason)
            } else {
                logger.error("Login failed: Unknown error")
                client?.setLoggedIn(false, message: "Unknown error")
                ActivityLog.shared.logConnectionFailed(reason: "Unknown error")
            }
        }
    }

    private func handleRoomList(_ data: Data) {
        var offset = 0

        // Parse public rooms: names then counts
        let publicRooms = parseRoomNamesAndCounts(data: data, offset: &offset)

        // Parse owned private rooms: names then counts
        let ownedPrivateRooms = parseRoomNamesAndCounts(data: data, offset: &offset)
            .map { ChatRoom(name: $0.name, users: $0.users, isPrivate: true) }

        // Parse member-of private rooms: names then counts
        let memberPrivateRooms = parseRoomNamesAndCounts(data: data, offset: &offset)
            .map { ChatRoom(name: $0.name, users: $0.users, isPrivate: true) }

        // Parse operated private room names (just names, no counts)
        var operatedNames: [String] = []
        if let opCount = data.readUInt32(at: offset) {
            guard opCount <= maxItemCount else { return }
            offset += 4
            for _ in 0..<opCount {
                guard let (name, bytesConsumed) = data.readString(at: offset) else { break }
                operatedNames.append(name)
                offset += bytesConsumed
            }
        }

        // Send full room list if handler exists, otherwise fall back to legacy
        if let fullHandler = client?.onRoomListFull {
            fullHandler(publicRooms, ownedPrivateRooms, memberPrivateRooms, operatedNames)
        } else {
            client?.onRoomList?(publicRooms)
        }
    }

    /// Parse a sequence of room names followed by their user counts
    private func parseRoomNamesAndCounts(data: Data, offset: inout Int) -> [ChatRoom] {
        guard let roomCount = data.readUInt32(at: offset) else { return [] }
        guard roomCount <= maxItemCount else { return [] }
        offset += 4

        var roomNames: [String] = []
        for _ in 0..<roomCount {
            guard let (name, bytesConsumed) = data.readString(at: offset) else { break }
            roomNames.append(name)
            offset += bytesConsumed
        }

        guard let countCount = data.readUInt32(at: offset) else { return roomNames.map { ChatRoom(name: $0) } }
        guard countCount <= maxItemCount else { return roomNames.map { ChatRoom(name: $0) } }
        offset += 4

        var userCounts: [UInt32] = []
        for _ in 0..<countCount {
            guard let count = data.readUInt32(at: offset) else { break }
            userCounts.append(count)
            offset += 4
        }

        return roomNames.enumerated().map { (index, name) in
            let userCount = index < userCounts.count ? Int(userCounts[index]) : 0
            let placeholderUsers = Array(repeating: "", count: userCount)
            return ChatRoom(name: name, users: placeholderUsers)
        }
    }

    private func handleJoinRoom(_ data: Data) {
        var offset = 0

        // Room name
        guard let (roomName, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        // Number of users
        guard let userCount = data.readUInt32(at: offset) else { return }
        guard userCount <= maxItemCount else { return }
        offset += 4

        // User names
        var users: [String] = []
        for _ in 0..<userCount {
            guard let (username, userBytesConsumed) = data.readString(at: offset) else { break }
            users.append(username)
            offset += userBytesConsumed
        }

        // Skip statuses (uint32 per user)
        if let statusCount = data.readUInt32(at: offset) {
            guard statusCount <= maxItemCount else { return }
            offset += 4
            let bytesToSkip = Int(statusCount) * 4
            guard offset + bytesToSkip <= data.count else { return }
            offset += bytesToSkip
        }

        // Skip user stats (avgspeed uint32, uploadnum uint64, files uint32, dirs uint32 = 20 bytes per user)
        if let statsCount = data.readUInt32(at: offset) {
            guard statsCount <= maxItemCount else { return }
            offset += 4
            let bytesToSkip = Int(statsCount) * 20
            guard offset + bytesToSkip <= data.count else { return }
            offset += bytesToSkip
        }

        // Skip slotsfull (uint32 per user)
        if let slotsCount = data.readUInt32(at: offset) {
            guard slotsCount <= maxItemCount else { return }
            offset += 4
            let bytesToSkip = Int(slotsCount) * 4
            guard offset + bytesToSkip <= data.count else { return }
            offset += bytesToSkip
        }

        // Skip countries (string per user)
        if let countryCount = data.readUInt32(at: offset) {
            guard countryCount <= maxItemCount else { return }
            offset += 4
            for _ in 0..<countryCount {
                guard let (_, countryLen) = data.readString(at: offset) else { break }
                offset += countryLen
            }
        }

        // Private room data (if present at end)
        var owner: String? = nil
        var operators: [String] = []

        if offset < data.count {
            if let (ownerName, ownerLen) = data.readString(at: offset) {
                owner = ownerName.isEmpty ? nil : ownerName
                offset += ownerLen

                // Operator count + names
                if let opCount = data.readUInt32(at: offset) {
                    guard opCount <= maxItemCount else { return }
                    offset += 4
                    for _ in 0..<opCount {
                        guard let (opName, opLen) = data.readString(at: offset) else { break }
                        operators.append(opName)
                        offset += opLen
                    }
                }
            }
        }

        client?.onRoomJoined?(roomName, users, owner, operators)
        ActivityLog.shared.logRoomJoined(room: roomName, userCount: users.count)
    }

    private func handleLeaveRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        client?.onRoomLeft?(roomName)
        ActivityLog.shared.logRoomLeft(room: roomName)
    }

    private func handleSayInRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, roomBytes) = data.readString(at: offset) else { return }
        offset += roomBytes

        guard let (username, userBytes) = data.readString(at: offset) else { return }
        offset += userBytes

        guard let (message, _) = data.readString(at: offset) else { return }

        let chatMessage = ChatMessage(
            username: username,
            content: message,
            isOwn: username == client?.username
        )

        client?.onRoomMessage?(roomName, chatMessage)
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
        var offset = 0

        // Message ID
        guard let messageId = data.readUInt32(at: offset) else { return }
        offset += 4

        // Timestamp
        guard let timestamp = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let (username, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let (message, messageLen) = data.readString(at: offset) else { return }
        offset += messageLen

        // isNewMessage: true = real-time message, false = offline/buffered message
        let isNewMessage = data.readBool(at: offset) ?? true

        let chatMessage = ChatMessage(
            id: UUID(),
            messageId: messageId,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            username: username,
            content: message,
            isSystem: false,
            isOwn: false,
            isNewMessage: isNewMessage
        )

        client?.onPrivateMessage?(username, chatMessage)

        // Send acknowledgment
        Task {
            await acknowledgePrivateMessage(messageId)
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
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let exists = data.readBool(at: offset) else { return }
        offset += 1

        guard exists else {
            // User does not exist; treat as offline and not privileged.
            Task { @MainActor in
                self.client?.handleUserStatusResponse(username: username, status: .offline, privileged: false)
            }
            return
        }

        guard let statusRaw = data.readUInt32(at: offset) else { return }
        offset += 4
        guard let avgSpeed = data.readUInt32(at: offset) else { return }
        offset += 4
        guard let uploadNum = data.readUInt32(at: offset) else { return }
        offset += 4
        guard data.readUInt32(at: offset) != nil else { return }  // Unknown field per protocol
        offset += 4
        guard let files = data.readUInt32(at: offset) else { return }
        offset += 4
        guard let dirs = data.readUInt32(at: offset) else { return }
        offset += 4

        let status = UserStatus(rawValue: statusRaw) ?? .offline

        // Initial watch response includes status + stats; status updates continue via code 7.
        Task { @MainActor in
            self.client?.handleUserStatusResponse(username: username, status: status, privileged: false)
            self.client?.dispatchUserStats(username: username, avgSpeed: avgSpeed, uploadNum: UInt64(uploadNum), files: files, dirs: dirs)
        }

        if status == .away || status == .online, let (countryCode, _) = data.readString(at: offset) {
            logger.debug("WatchUser country for \(username): \(countryCode)")
        }
    }

    private func handleGetUserStatus(_ data: Data) {
        var offset = 0

        guard let (username, bytesConsumed) = data.readString(at: offset) else { return }
        offset += bytesConsumed

        guard let statusRaw = data.readUInt32(at: offset) else { return }
        offset += 4

        // Read privileged flag if present
        let privileged = data.readUInt8(at: offset).map { $0 != 0 } ?? false

        let status = UserStatus(rawValue: statusRaw) ?? .offline

        logger.info("User \(username) status: \(status.description), privileged: \(privileged)")

        // Dispatch to handler (handles both pending status checks and external callback)
        Task { @MainActor in
            self.client?.handleUserStatusResponse(username: username, status: status, privileged: privileged)
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
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else {
            return
        }
        offset += usernameLen

        guard let (connectionType, typeLen) = data.readString(at: offset) else {
            return
        }
        offset += typeLen

        guard let ip = data.readUInt32(at: offset) else {
            return
        }
        offset += 4

        guard let port = data.readUInt32(at: offset) else {
            return
        }
        offset += 4

        guard let token = data.readUInt32(at: offset) else {
            return
        }

        connectToPeerCount += 1
        let ipAddress = ipString(from: ip)

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
            logger.info("connectToPeerThrottled SUCCESS: \(username)")

        } catch {
            logger.error("connectToPeerThrottled FAILED: \(username) - \(error)")
            await client?.sendCantConnectToPeer(token: token, username: username)
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
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
        var offset = 0

        guard let parentCount = data.readUInt32(at: offset) else { return }
        offset += 4

        logger.info("Received \(parentCount) possible distributed parents")

        var parents: [(username: String, ip: String, port: Int)] = []

        for i in 0..<parentCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            offset += usernameLen

            guard let ip = data.readUInt32(at: offset) else { break }
            offset += 4

            guard let port = data.readUInt32(at: offset) else { break }
            offset += 4

            let ipStr = ipString(from: ip)
            parents.append((username: username, ip: ipStr, port: Int(port)))
            logger.debug("Parent \(i+1): \(username) at \(ipStr):\(port)")
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

            // Set up message handling for distributed messages
            let parentUsername = username
            await connection.setOnMessage { [weak self] code, payload in
                await self?.handleDistributedMessage(code: code, payload: payload, parentUsername: parentUsername)
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
        var offset = 0

        // uint32 unknown
        guard let unknown = data.readUInt32(at: offset) else { return }
        offset += 4

        // string username (who is searching)
        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        // uint32 token
        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        // string query
        guard let (query, _) = data.readString(at: offset) else { return }

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

        // Search our shared files
        guard let shareManager = client?.shareManager else {
            logger.debug("No share manager available for distributed search")
            return
        }

        var matchingFiles = shareManager.search(query: query)
        guard !matchingFiles.isEmpty else {
            return
        }

        // Cap results to limit bandwidth
        if filter.maxResults > 0 && matchingFiles.count > filter.maxResults {
            matchingFiles = Array(matchingFiles.prefix(filter.maxResults))
        }

        logger.info("Distributed search '\(query)' from \(username): \(matchingFiles.count) matches")
        ActivityLog.shared.logDistributedSearch(query: query, matchCount: matchingFiles.count)

        // Send search results back to the searching user
        Task {
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
        var offset = 0

        guard let count = data.readUInt32(at: offset) else { return }
        offset += 4

        var phrases: [String] = []
        for _ in 0..<count {
            guard let (phrase, phraseLen) = data.readString(at: offset) else { break }
            phrases.append(phrase)
            offset += phraseLen
        }

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
        var offset = 0

        // Recommendations
        guard let recCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var recommendations: [(item: String, score: Int32)] = []
        for _ in 0..<recCount {
            guard let (item, itemLen) = data.readString(at: offset) else { break }
            offset += itemLen
            guard let score = data.readInt32(at: offset) else { break }
            offset += 4
            recommendations.append((item, score))
        }

        // Unrecommendations
        guard let unrecCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var unrecommendations: [(item: String, score: Int32)] = []
        for _ in 0..<unrecCount {
            guard let (item, itemLen) = data.readString(at: offset) else { break }
            offset += itemLen
            guard let score = data.readInt32(at: offset) else { break }
            offset += 4
            unrecommendations.append((item, score))
        }

        logger.info("Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        client?.onRecommendations?(recommendations, unrecommendations)
    }

    private func handleGlobalRecommendations(_ data: Data) {
        var offset = 0

        // Global recommendations (same format as personal recommendations)
        guard let recCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var recommendations: [(item: String, score: Int32)] = []
        for _ in 0..<recCount {
            guard let (item, itemLen) = data.readString(at: offset) else { break }
            offset += itemLen
            guard let score = data.readInt32(at: offset) else { break }
            offset += 4
            recommendations.append((item, score))
        }

        // Unrecommendations
        guard let unrecCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var unrecommendations: [(item: String, score: Int32)] = []
        for _ in 0..<unrecCount {
            guard let (item, itemLen) = data.readString(at: offset) else { break }
            offset += itemLen
            guard let score = data.readInt32(at: offset) else { break }
            offset += 4
            unrecommendations.append((item, score))
        }

        logger.info("Global Recommendations: \(recommendations.count), Unrecommendations: \(unrecommendations.count)")
        client?.onGlobalRecommendations?(recommendations, unrecommendations)
    }

    private func handleUserInterests(_ data: Data) {
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        // Liked interests
        guard let likedCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var likes: [String] = []
        for _ in 0..<likedCount {
            guard let (interest, interestLen) = data.readString(at: offset) else { break }
            likes.append(interest)
            offset += interestLen
        }

        // Hated interests
        guard let hatedCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var hates: [String] = []
        for _ in 0..<hatedCount {
            guard let (interest, interestLen) = data.readString(at: offset) else { break }
            hates.append(interest)
            offset += interestLen
        }

        logger.info("User \(username) interests - likes: \(likes.count), hates: \(hates.count)")
        client?.onUserInterests?(username, likes, hates)
    }

    private func handleSimilarUsers(_ data: Data) {
        var offset = 0

        guard let userCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var users: [(username: String, rating: UInt32)] = []
        for _ in 0..<userCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            offset += usernameLen
            guard let rating = data.readUInt32(at: offset) else { break }
            offset += 4
            users.append((username, rating))
        }

        logger.info("Similar users: \(users.count)")
        client?.onSimilarUsers?(users)
    }

    private func handleItemRecommendations(_ data: Data) {
        var offset = 0

        guard let (item, itemLen) = data.readString(at: offset) else { return }
        offset += itemLen

        guard let recCount = data.readUInt32(at: offset) else { return }
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
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let avgSpeed = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let uploadNum = data.readUInt32(at: offset) else { return }
        offset += 4

        // uint32 unknown (skip)
        offset += 4

        guard let files = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let dirs = data.readUInt32(at: offset) else { return }

        logger.info("User stats for \(username): speed=\(avgSpeed), uploads=\(uploadNum), files=\(files), dirs=\(dirs)")
        client?.dispatchUserStats(username: username, avgSpeed: avgSpeed, uploadNum: UInt64(uploadNum), files: files, dirs: dirs)
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
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let tickerCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var tickers: [(username: String, ticker: String)] = []
        for _ in 0..<tickerCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            offset += usernameLen
            guard let (ticker, tickerLen) = data.readString(at: offset) else { break }
            offset += tickerLen
            tickers.append((username, ticker))
        }

        logger.info("Room ticker state for \(room): \(tickers.count) tickers")
        client?.onRoomTickerState?(room, tickers)
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
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let memberCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var members: [String] = []
        for _ in 0..<memberCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            members.append(username)
            offset += usernameLen
        }

        logger.info("Private room \(room) members: \(members.count)")
        client?.onPrivateRoomMembers?(room, members)
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
        var offset = 0

        guard let (room, roomLen) = data.readString(at: offset) else { return }
        offset += roomLen

        guard let operatorCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var operators: [String] = []
        for _ in 0..<operatorCount {
            guard let (username, usernameLen) = data.readString(at: offset) else { break }
            operators.append(username)
            offset += usernameLen
        }

        logger.info("Private room \(room) operators: \(operators.count)")
        client?.onPrivateRoomOperators?(room, operators)
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
        ActivityLog.shared.logRelogged()
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
