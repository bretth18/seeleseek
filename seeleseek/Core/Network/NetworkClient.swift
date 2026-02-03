import Foundation
import Network

/// Main network interface that coordinates server and peer connections
@Observable
@MainActor
final class NetworkClient {
    // MARK: - Connection State
    private(set) var isConnecting = false
    private(set) var isConnected = false
    private(set) var connectionError: String?

    // MARK: - User Info
    private(set) var username: String = ""
    private(set) var loggedIn = false

    // MARK: - Internal
    private var serverConnection: ServerConnection?
    private var messageHandler: ServerMessageHandler?
    private var receiveTask: Task<Void, Never>?

    // MARK: - Callbacks
    var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    var onSearchResults: (([SearchResult]) -> Void)?
    var onRoomList: (([ChatRoom]) -> Void)?
    var onRoomMessage: ((String, ChatMessage) -> Void)?
    var onPrivateMessage: ((String, ChatMessage) -> Void)?
    var onRoomJoined: ((String, [String]) -> Void)?
    var onRoomLeft: ((String) -> Void)?
    var onUserJoinedRoom: ((String, String) -> Void)?
    var onUserLeftRoom: ((String, String) -> Void)?
    var onPeerAddress: ((String, String, Int) -> Void)?

    // MARK: - Connection

    func connect(server: String, port: UInt16, username: String, password: String) async {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        connectionError = nil
        self.username = username
        onConnectionStatusChanged?(.connecting)

        do {
            let connection = ServerConnection(host: server, port: port)
            serverConnection = connection
            messageHandler = ServerMessageHandler(client: self)

            try await connection.connect()

            // Send login
            let loginMessage = MessageBuilder.login(
                username: username,
                password: password,
                version: 157,
                hash: computeMD5("\(username)\(password)")
            )
            try await connection.send(loginMessage)

            isConnecting = false
            isConnected = true
            onConnectionStatusChanged?(.connected)

            // Start receiving messages
            startReceiving()

        } catch {
            isConnecting = false
            isConnected = false
            connectionError = error.localizedDescription
            onConnectionStatusChanged?(.disconnected)
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        Task {
            await serverConnection?.disconnect()
            serverConnection = nil
        }

        isConnected = false
        loggedIn = false
        onConnectionStatusChanged?(.disconnected)
    }

    // MARK: - Message Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self = self, let connection = self.serverConnection else { return }

            do {
                for try await message in connection.messages {
                    await self.handleMessage(message)
                }
            } catch {
                await MainActor.run {
                    self.connectionError = error.localizedDescription
                    self.isConnected = false
                    self.onConnectionStatusChanged?(.disconnected)
                }
            }
        }
    }

    private func handleMessage(_ data: Data) async {
        await messageHandler?.handle(data)
    }

    // MARK: - Server Commands

    func search(query: String, token: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.fileSearch(token: token, query: query)
        try await connection.send(message)
    }

    func getRoomList() async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.roomList()
        try await connection.send(message)
    }

    func joinRoom(_ name: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.joinRoom(name)
        try await connection.send(message)
    }

    func leaveRoom(_ name: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.leaveRoom(name)
        try await connection.send(message)
    }

    func sendRoomMessage(_ room: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let data = MessageBuilder.sayInRoom(room: room, message: message)
        try await connection.send(data)
    }

    func sendPrivateMessage(to username: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let data = MessageBuilder.privateMessage(username: username, message: message)
        try await connection.send(data)
    }

    func getUserAddress(_ username: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.getUserAddress(username)
        try await connection.send(message)
    }

    func setStatus(_ status: UserStatus) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.setStatus(status)
        try await connection.send(message)
    }

    func setSharedFilesCount(_ files: UInt32, directories: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.sharedFoldersFiles(folders: directories, files: files)
        try await connection.send(message)
    }

    // MARK: - Internal State Updates

    func setLoggedIn(_ success: Bool, message: String?) {
        loggedIn = success
        if !success {
            connectionError = message
            onConnectionStatusChanged?(.disconnected)
        }
    }
}

// MARK: - Errors

enum NetworkError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout:
            return "Connection timed out"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

// MARK: - MD5 Helper

private func computeMD5(_ string: String) -> String {
    guard let data = string.data(using: .utf8) else { return "" }

    // Simple MD5 implementation for auth
    // In production, use CryptoKit or CommonCrypto
    var digest = [UInt8](repeating: 0, count: 16)

    data.withUnsafeBytes { buffer in
        _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
    }

    return digest.map { String(format: "%02x", $0) }.joined()
}

// CommonCrypto bridge
import CommonCrypto
