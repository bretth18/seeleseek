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

    // Peer connections - public for UI access
    let peerConnectionPool = PeerConnectionPool()

    // Share manager
    let shareManager = ShareManager()

    // MARK: - Initialization

    init() {
        print("🚀 NetworkClient initializing...")
        // Wire up peer connection pool callbacks to network client
        peerConnectionPool.onSearchResults = { [weak self] token, results in
            print("🔔 NetworkClient: Received \(results.count) results for token \(token)")
            if self?.onSearchResults != nil {
                print("🔔 NetworkClient: Forwarding to SearchState callback...")
                self?.onSearchResults?(token, results)
                print("✅ NetworkClient: Callback completed")
            } else {
                print("⚠️ NetworkClient: WARNING - onSearchResults callback is nil!")
            }
        }
        print("🚀 NetworkClient initialized, callbacks wired")
    }

    // MARK: - Callbacks
    var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    var onSearchResults: ((UInt32, [SearchResult]) -> Void)?  // (token, results)
    var onRoomList: (([ChatRoom]) -> Void)?
    var onRoomMessage: ((String, ChatMessage) -> Void)?
    var onPrivateMessage: ((String, ChatMessage) -> Void)?
    var onRoomJoined: ((String, [String]) -> Void)?
    var onRoomLeft: ((String) -> Void)?
    var onUserJoinedRoom: ((String, String) -> Void)?
    var onUserLeftRoom: ((String, String) -> Void)?
    var onPeerAddress: ((String, String, Int) -> Void)?

    // MARK: - Connection

    func connect(server: String, port: UInt16, username: String, password: String, preferredListenPort: UInt16? = nil) async {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        connectionError = nil
        self.username = username
        onConnectionStatusChanged?(.connecting)

        logger.info("Starting connection to \(server):\(port) as \(username)")

        do {
            // Step 1: Set up listener callback for incoming peer connections
            await listenerService.setOnNewConnection { [weak self] connection, isObfuscated in
                guard let self else { return }
                print("🟢 INCOMING PEER CONNECTION received (obfuscated: \(isObfuscated))")
                self.logger.info("Incoming peer connection (obfuscated: \(isObfuscated))")
                await self.peerConnectionPool.handleIncomingConnection(connection)
            }

            // Step 2: Start listener for incoming peer connections
            logger.info("Starting listener...")
            print("🔵 Starting listener service (preferred port: \(preferredListenPort?.description ?? "auto"))...")
            let ports = try await listenerService.start(preferredPort: preferredListenPort)
            listenPort = ports.port
            obfuscatedPort = ports.obfuscatedPort
            logger.info("Listening on port \(self.listenPort)")
            print("🟢 LISTENING on port \(self.listenPort) (obfuscated: \(self.obfuscatedPort))")

            // Step 3: Connect to server FIRST (NAT runs in background)
            print("🔌 Connecting to server...")
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

                // Step 7: Report shared files
                let folders = UInt32(shareManager.totalFolders)
                let files = UInt32(shareManager.totalFiles)
                let sharesMessage = MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files)
                try await connection.send(sharesMessage)
                logger.info("Reported shares: \(folders) folders, \(files) files")

                // Step 8: Join distributed network for search propagation
                // Tell server we need a distributed parent
                let haveNoParentMessage = MessageBuilder.haveNoParent(true)
                try await connection.send(haveNoParentMessage)
                print("🌐 Sent HaveNoParent(true) - requesting distributed network parent")

                // Tell server we accept child connections (for now, don't accept)
                let acceptChildrenMessage = MessageBuilder.acceptChildren(false)
                try await connection.send(acceptChildrenMessage)
                print("🌐 Sent AcceptChildren(false)")

                // Tell server our branch level (0 = not connected to distributed network yet)
                let branchLevelMessage = MessageBuilder.branchLevel(0)
                try await connection.send(branchLevelMessage)
                print("🌐 Sent BranchLevel(0)")

                // Print diagnostic info
                print("📊 CONNECTION DIAGNOSTICS:")
                print("   Listen port: \(self.listenPort)")
                print("   Obfuscated port: \(self.obfuscatedPort)")
                if let extIP = self.externalIP {
                    print("   External IP: \(extIP)")
                } else {
                    print("   External IP: unknown (NAT mapping may have failed)")
                }

                isConnecting = false
                isConnected = true
                onConnectionStatusChanged?(.connected)
                logger.info("Login successful!")

                // Run NAT mapping in background (don't block connection)
                Task {
                    await self.setupNATInBackground()
                }
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

    // MARK: - NAT Setup (Background)

    private func setupNATInBackground() async {
        print("🔧 NAT: Starting background port mapping...")

        // Try to map the listen port
        do {
            let mappedPort = try await natService.mapPort(listenPort)
            print("✅ NAT: Mapped port \(listenPort) -> \(mappedPort)")
        } catch {
            print("⚠️ NAT: Port mapping failed (will rely on server-mediated connections)")
        }

        // Try to map obfuscated port
        if obfuscatedPort > 0 {
            do {
                let mappedObfuscated = try await natService.mapPort(obfuscatedPort)
                print("✅ NAT: Mapped obfuscated port \(obfuscatedPort) -> \(mappedObfuscated)")
            } catch {
                // Silent failure for obfuscated port
            }
        }

        // Discover external IP
        if let extIP = await natService.discoverExternalIP() {
            await MainActor.run {
                self.externalIP = extIP
            }
            print("✅ NAT: External IP: \(extIP)")
        }

        print("🔧 NAT: Background setup complete")
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
        logger.info("Sent search request: query='\(query)' token=\(token)")
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

    /// Tell server we couldn't connect to a peer - triggers indirect connection attempt
    func sendCantConnectToPeer(token: UInt32, username: String) async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.cantConnectToPeer(token: token, username: username)
        do {
            try await connection.send(message)
            logger.info("Sent CantConnectToPeer for \(username) token=\(token)")
        } catch {
            logger.error("Failed to send CantConnectToPeer: \(error.localizedDescription)")
        }
    }

    // MARK: - Peer Connections

    /// Browse a user's shared files
    func browseUser(_ username: String) async throws -> [SharedFile] {
        guard isConnected else { throw NetworkError.notConnected }

        let token = UInt32.random(in: 0...UInt32.max)

        // Set up a continuation to wait for the peer address
        let (ip, port) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, Int), Error>) in
            // Temporarily set callback to capture the response
            let previousCallback = onPeerAddress
            onPeerAddress = { [weak self] receivedUsername, receivedIP, receivedPort in
                if receivedUsername == username {
                    self?.onPeerAddress = previousCallback
                    continuation.resume(returning: (receivedIP, receivedPort))
                } else {
                    previousCallback?(receivedUsername, receivedIP, receivedPort)
                }
            }

            // Request the peer address
            Task {
                do {
                    try await self.getUserAddress(username)
                } catch {
                    self.onPeerAddress = previousCallback
                    continuation.resume(throwing: error)
                }
            }

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(for: .seconds(10))
                if self.onPeerAddress != nil {
                    self.onPeerAddress = previousCallback
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        }

        logger.info("Got peer address for \(username): \(ip):\(port)")

        // Connect to the peer
        let connection = try await peerConnectionPool.connect(
            to: username,
            ip: ip,
            port: port,
            token: token
        )

        // Request shares
        try await connection.requestShares()

        // Wait for shares response
        let files = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SharedFile], Error>) in
            Task {
                await connection.setOnSharesReceived { files in
                    continuation.resume(returning: files)
                }

                // Timeout after 30 seconds
                try? await Task.sleep(for: .seconds(30))
                continuation.resume(throwing: NetworkError.timeout)
            }
        }

        return files
    }

    // MARK: - Share Updates

    /// Update the server with current share counts (call after scanning)
    func updateShareCounts() async {
        guard isConnected, let connection = serverConnection else { return }

        let folders = UInt32(shareManager.totalFolders)
        let files = UInt32(shareManager.totalFiles)

        do {
            let message = MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files)
            try await connection.send(message)
            logger.info("Updated share counts: \(folders) folders, \(files) files")
        } catch {
            logger.error("Failed to update share counts: \(error.localizedDescription)")
        }
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
