import Foundation
import Network
import os
import CryptoKit

/// Main network interface that coordinates server and peer connections
@Observable
@MainActor
final class NetworkClient {
    private let logger = Logger(subsystem: "com.seeleseek", category: "NetworkClient")

    // MARK: - Connection State
    private(set) var isConnecting = false
    private(set) var isConnected = false
    private(set) var connectionError: String?

    // MARK: - User Info
    private(set) var username: String = ""
    private(set) var loggedIn = false

    // MARK: - Network Info
    private(set) var listenPort: UInt16 = 0
    private(set) var obfuscatedPort: UInt16 = 0
    private(set) var externalIP: String?

    // MARK: - Internal
    private var serverConnection: ServerConnection?
    private var messageHandler: ServerMessageHandler?
    private var receiveTask: Task<Void, Never>?

    // Services
    private let listenerService = ListenerService()
    private let natService = NATService()

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

        logger.info("Starting connection to \(server):\(port) as \(username)")

        do {
            // Step 1: Start listener for incoming peer connections
            logger.info("Starting listener...")
            let ports = try await listenerService.start()
            listenPort = ports.port
            obfuscatedPort = ports.obfuscatedPort
            logger.info("Listening on port \(self.listenPort)")

            // Step 2: Try NAT traversal (don't fail if it doesn't work)
            logger.info("Attempting NAT traversal...")
            if let mappedPort = try? await natService.mapPort(listenPort) {
                logger.info("NAT mapped to external port \(mappedPort)")
            }

            if let extIP = await natService.discoverExternalIP() {
                externalIP = extIP
                logger.info("External IP: \(extIP)")
            }

            // Step 3: Connect to server
            logger.info("Connecting to server...")
            let connection = ServerConnection(host: server, port: port)
            serverConnection = connection
            messageHandler = ServerMessageHandler(client: self)

            try await connection.connect()
            logger.info("Connected to server")

            // Step 4: Send login
            let hash = computeMD5("\(username)\(password)")
            logger.info("Sending login (hash: \(hash.prefix(8))...)")

            let loginMessage = MessageBuilder.loginMessage(
                username: username,
                password: password
            )
            try await connection.send(loginMessage)

            // Start receiving messages (login response will come through here)
            startReceiving()

            // Wait briefly for login response
            try await Task.sleep(for: .milliseconds(500))

            if loggedIn {
                // Step 5: Send listen port to server
                logger.info("Sending listen port...")
                let portMessage = MessageBuilder.setListenPortMessage(port: UInt32(listenPort), obfuscatedPort: UInt32(obfuscatedPort))
                try await connection.send(portMessage)

                // Step 6: Set online status
                let statusMessage = MessageBuilder.setOnlineStatusMessage(status: .online)
                try await connection.send(statusMessage)

                // Step 7: Report shared files (0 for now)
                let sharesMessage = MessageBuilder.sharedFoldersFilesMessage(folders: 0, files: 0)
                try await connection.send(sharesMessage)

                isConnecting = false
                isConnected = true
                onConnectionStatusChanged?(.connected)
                logger.info("Login successful!")
            } else if connectionError == nil {
                // Still waiting for login response - give it more time
                isConnecting = false
                isConnected = true
                onConnectionStatusChanged?(.connected)
            }

        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            isConnecting = false
            isConnected = false
            connectionError = error.localizedDescription
            onConnectionStatusChanged?(.disconnected)

            // Cleanup
            await listenerService.stop()
        }
    }

    func disconnect() {
        logger.info("Disconnecting...")

        receiveTask?.cancel()
        receiveTask = nil

        Task {
            await serverConnection?.disconnect()
            serverConnection = nil

            await listenerService.stop()
            await natService.removeAllMappings()
        }

        isConnected = false
        loggedIn = false
        listenPort = 0
        obfuscatedPort = 0
        externalIP = nil
        onConnectionStatusChanged?(.disconnected)

        logger.info("Disconnected")
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
    let digest = Insecure.MD5.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
