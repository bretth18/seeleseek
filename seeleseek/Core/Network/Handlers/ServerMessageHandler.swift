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
        default:
            // Log unhandled message
            print("Unhandled server message: \(code) (\(codeValue))")
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

    private func handleConnectToPeer(_ data: Data) {
        var offset = 0

        guard let (username, newOffset) = data.readString(at: offset) else { return }
        offset = newOffset

        guard let (connectionType, newOffset2) = data.readString(at: offset) else { return }
        offset = newOffset2

        guard let ip = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let port = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let token = data.readUInt32(at: offset) else { return }

        let ipAddress = ipString(from: ip)
        print("Connect to peer: \(username) (\(connectionType)) at \(ipAddress):\(port) token=\(token)")

        // Would initiate peer connection here
        client?.onPeerAddress?(username, ipAddress, Int(port))
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
