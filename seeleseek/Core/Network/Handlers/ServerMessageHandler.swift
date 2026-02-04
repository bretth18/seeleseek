import Foundation
import os

/// Handles incoming server messages and dispatches to appropriate callbacks
@MainActor
final class ServerMessageHandler {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ServerMessageHandler")
    private weak var client: NetworkClient?

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
            print("🌐 DISTRIBUTED MSG: code=\(codeValue) (\(code?.description ?? "unknown")) length=\(messageLength)")
        }

        guard let code = code else {
            logger.warning("Unknown message code: \(codeValue)")
            return
        }

        let payload = data.safeSubdata(in: 8..<Int(messageLength + 4)) ?? Data()

        switch code {
        case .login:
            handleLogin(payload)
        case .roomList:
            handleRoomList(payload)
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
        case .getUserStatus:
            handleGetUserStatus(payload)
        case .connectToPeer:
            handleConnectToPeer(payload)
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
        default:
            // Log unhandled message with more detail
            print("📨 Unhandled server message: \(code) (code=\(codeValue)) payload=\(payload.count) bytes")
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
            if let (greetingStr, newOffset) = data.readString(at: offset) {
                offset = newOffset
                greeting = greetingStr
                logger.info("Login greeting: \(greeting)")
            }

            // Read IP address
            if let ip = data.readUInt32(at: offset) {
                offset += 4
                logger.info("Server reports IP: \(self.ipString(from: ip))")
            }

            client?.setLoggedIn(true, message: greeting)
        } else {
            // Login failed - read reason
            if let (reason, _) = data.readString(at: offset) {
                logger.error("Login failed: \(reason)")
                client?.setLoggedIn(false, message: reason)
            } else {
                logger.error("Login failed: Unknown error")
                client?.setLoggedIn(false, message: "Unknown error")
            }
        }
    }

    private func handleRoomList(_ data: Data) {
        var offset = 0
        var rooms: [ChatRoom] = []

        // Number of rooms
        guard let roomCount = data.readUInt32(at: offset) else { return }
        offset += 4

        // Room names
        var roomNames: [String] = []
        for _ in 0..<roomCount {
            guard let (name, newOffset) = data.readString(at: offset) else { break }
            roomNames.append(name)
            offset = newOffset
        }

        // User counts
        guard let countCount = data.readUInt32(at: offset) else { return }
        offset += 4

        var userCounts: [UInt32] = []
        for _ in 0..<countCount {
            guard let count = data.readUInt32(at: offset) else { break }
            userCounts.append(count)
            offset += 4
        }

        // Build room list
        for (index, name) in roomNames.enumerated() {
            let userCount = index < userCounts.count ? Int(userCounts[index]) : 0
            // Create placeholder users for the count since we don't have the actual names yet
            let placeholderUsers = Array(repeating: "", count: userCount)
            rooms.append(ChatRoom(name: name, users: placeholderUsers))
        }

        client?.onRoomList?(rooms)
    }

    private func handleJoinRoom(_ data: Data) {
        var offset = 0

        // Room name
        guard let (roomName, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        // Number of users
        guard let userCount = data.readUInt32(at: offset) else { return }
        offset += 4

        // User names
        var users: [String] = []
        for _ in 0..<userCount {
            guard let (username, newOffset) = data.readString(at: offset) else { break }
            users.append(username)
            offset = newOffset
        }

        client?.onRoomJoined?(roomName, users)
    }

    private func handleLeaveRoom(_ data: Data) {
        guard let (roomName, _) = data.readString(at: 0) else { return }
        client?.onRoomLeft?(roomName)
    }

    private func handleSayInRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, newOffset1) = data.readString(at: offset) else { return }
        offset = newOffset1

        guard let (username, newOffset2) = data.readString(at: offset) else { return }
        offset = newOffset2

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

        guard let (roomName, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        guard let (username, _) = data.readString(at: offset) else { return }

        client?.onUserJoinedRoom?(roomName, username)
    }

    private func handleUserLeftRoom(_ data: Data) {
        var offset = 0

        guard let (roomName, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

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

        guard let (username, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        guard let (message, _) = data.readString(at: offset) else { return }

        let chatMessage = ChatMessage(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            username: username,
            content: message,
            isSystem: false,
            isOwn: false
        )

        client?.onPrivateMessage?(username, chatMessage)

        // Send acknowledgment
        Task {
            await acknowledgePrivateMessage(messageId)
        }
    }

    private func acknowledgePrivateMessage(_ messageId: UInt32) async {
        // Would send ack back to server
        // MessageBuilder.acknowledgePrivateMessage(messageId)
    }

    private func handleGetUserAddress(_ data: Data) {
        var offset = 0

        guard let (username, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        guard let ip = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let port = data.readUInt32(at: offset) else { return }

        let ipAddress = ipString(from: ip)
        client?.onPeerAddress?(username, ipAddress, Int(port))
    }

    private func handleGetUserStatus(_ data: Data) {
        var offset = 0

        guard let (username, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        guard let status = data.readUInt32(at: offset) else { return }

        // Could dispatch to a callback if needed
        print("User \(username) status: \(status)")
    }

    // Track pending connections to avoid duplicates and limit concurrency
    private var pendingConnections: Set<String> = []
    private var activeConnectionCount = 0
    private let maxConcurrentConnections = 5

    private func handleConnectToPeer(_ data: Data) {
        var offset = 0

        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        guard let (connectionType, typeLen) = data.readString(at: offset) else { return }
        offset += typeLen

        guard let ip = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let port = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let token = data.readUInt32(at: offset) else { return }

        let ipAddress = ipString(from: ip)
        let connectionKey = "\(username)-\(token)"

        // Skip if we're already trying to connect to this peer
        if pendingConnections.contains(connectionKey) {
            print("⏭️ Skipping duplicate ConnectToPeer for \(username)")
            return
        }

        // Limit concurrent connections to avoid resource exhaustion
        if activeConnectionCount >= maxConcurrentConnections {
            print("⏸️ Too many concurrent connections, skipping \(username)")
            return
        }

        logger.info("ConnectToPeer: \(username) (\(connectionType)) at \(ipAddress):\(port) token=\(token)")
        pendingConnections.insert(connectionKey)
        activeConnectionCount += 1

        // Initiate peer connection for search results, transfers, etc.
        Task {
            defer {
                pendingConnections.remove(connectionKey)
                activeConnectionCount -= 1
            }

            do {
                guard let pool = client?.peerConnectionPool else { return }

                print("🔵 Connecting to peer \(username) at \(ipAddress):\(port) [\(activeConnectionCount)/\(maxConcurrentConnections)]")

                // Try direct connection with a shorter timeout
                let connection = try await withTimeout(seconds: 5) {
                    try await pool.connect(
                        to: username,
                        ip: ipAddress,
                        port: Int(port),
                        token: token
                    )
                }

                // Send PierceFirewall to complete handshake
                print("🔵 Sending PierceFirewall to \(username) with token \(token)")
                try await connection.sendPierceFirewall()

                logger.info("Connected to peer \(username) for \(connectionType), handshake sent")
                print("🟢 Connected to peer \(username) for \(connectionType)")

            } catch {
                logger.error("Failed to connect to peer \(username): \(error.localizedDescription)")
                print("🔴 Failed to connect to peer \(username): \(error)")

                // Tell server we couldn't connect - it may try indirect connection
                await client?.sendCantConnectToPeer(token: token, username: username)
            }
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw NetworkError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Distributed Network Handlers

    private func handlePossibleParents(_ data: Data) {
        var offset = 0

        guard let parentCount = data.readUInt32(at: offset) else { return }
        offset += 4

        print("🌐 Received \(parentCount) possible distributed parents")

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
            print("🌐   Parent \(i+1): \(username) at \(ipStr):\(port)")
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
                    print("🌐 Successfully connected to distributed parent \(parent.username)")
                    break
                }
            }
        }
    }

    private var distributedParentConnection: PeerConnection?

    private func connectToDistributedParent(username: String, ip: String, port: Int) async -> Bool {
        print("🌐 Connecting to distributed parent: \(username) at \(ip):\(port)")

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

            print("🟢 Connected to distributed parent: \(username)")
            logger.info("Connected to distributed parent \(username)")

            // Store the connection to keep it alive
            distributedParentConnection = connection

            // Set up message handling for distributed messages
            await connection.setOnMessage { [weak self] code, payload in
                await self?.handleDistributedMessage(code: code, payload: payload)
            }

            return true
        } catch {
            print("🔴 Failed to connect to distributed parent \(username): \(error)")
            logger.error("Failed to connect to distributed parent \(username): \(error.localizedDescription)")
            // Explicitly disconnect to free resources
            await connection.disconnect()
            return false
        }
    }

    private func handleDistributedMessage(code: UInt32, payload: Data) async {
        print("🌐 Distributed message received: code=\(code) size=\(payload.count)")

        // Distributed messages use the same codes as DistributedMessageCode
        switch code {
        case UInt32(DistributedMessageCode.branchLevel.rawValue):
            // uint32 branch level
            if let level = payload.readUInt32(at: 0) {
                print("🌐 Branch level: \(level)")
            }

        case UInt32(DistributedMessageCode.branchRoot.rawValue):
            // string branch root username
            if let (rootUsername, _) = payload.readString(at: 0) {
                print("🌐 Branch root: \(rootUsername)")
            }

        case UInt32(DistributedMessageCode.searchRequest.rawValue):
            // This is a search request from the distributed network
            handleDistributedSearch(payload)

        default:
            print("🌐 Unknown distributed message code: \(code)")
        }
    }

    private func handleEmbeddedMessage(_ data: Data) {
        // Server sends us an embedded distributed message (when we're a branch root)
        // Format: uint8 distrib_code + message payload
        guard let distribCode = data.readByte(at: 0) else { return }

        let payload = data.safeSubdata(in: 1..<data.count) ?? Data()

        print("🌐 Received embedded distributed message: code=\(distribCode) size=\(payload.count)")

        if distribCode == DistributedMessageCode.searchRequest.rawValue {
            // This is a distributed search - we should check our files and respond
            handleDistributedSearch(payload)
        }
    }

    private func handleDistributedSearch(_ data: Data) {
        var offset = 0

        // uint32 unknown
        guard data.readUInt32(at: offset) != nil else { return }
        offset += 4

        // string username (who is searching)
        guard let (username, usernameLen) = data.readString(at: offset) else { return }
        offset += usernameLen

        // uint32 token
        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        // string query
        guard let (query, _) = data.readString(at: offset) else { return }

        print("🔍 Distributed search from \(username): '\(query)' token=\(token)")

        // TODO: Search our shared files and send results back via P connection
        // For now, just log it
    }

    private func handleResetDistributed() {
        print("🌐 Server requested distributed network reset")
        // TODO: Disconnect from parent, clear children, and request new parent
    }

    private func handleParentMinSpeed(_ data: Data) {
        guard let speed = data.readUInt32(at: 0) else { return }
        print("🌐 Parent minimum speed: \(speed)")
    }

    private func handleParentSpeedRatio(_ data: Data) {
        guard let ratio = data.readUInt32(at: 0) else { return }
        print("🌐 Parent speed ratio: \(ratio)")
    }

    // MARK: - Helpers

    private func ipString(from value: UInt32) -> String {
        let b1 = value & 0xFF
        let b2 = (value >> 8) & 0xFF
        let b3 = (value >> 16) & 0xFF
        let b4 = (value >> 24) & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}
