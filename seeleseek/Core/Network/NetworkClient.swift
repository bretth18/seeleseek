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

    // MARK: - Distributed Network
    var acceptDistributedChildren = false  // Set to true to participate as a node
    private(set) var distributedBranchLevel: UInt32 = 0
    private(set) var distributedBranchRoot: String = ""
    private var distributedChildren: [PeerConnection] = []

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

    // User info cache (country codes, etc.)
    let userInfoCache = UserInfoCache()

    // MARK: - Pending Peer Address Requests (for concurrent browse/folder requests)
    private var pendingPeerAddressRequests: [String: CheckedContinuation<(ip: String, port: Int), Error>] = [:]

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

        // Wire up incoming connection matching for downloads
        peerConnectionPool.onIncomingConnectionMatched = { [weak self] username, token, connection in
            print("🔔 NetworkClient: Incoming connection matched: \(username) token=\(token)")
            await self?.onIncomingConnectionMatched?(username, token, connection)
        }

        // Wire up file transfer connections
        peerConnectionPool.onFileTransferConnection = { [weak self] username, token, connection in
            print("📁 NetworkClient: File transfer connection received - username='\(username)' token=\(token)")
            if self?.onFileTransferConnection != nil {
                print("📁 NetworkClient: Forwarding to DownloadManager...")
                await self?.onFileTransferConnection?(username, token, connection)
                print("📁 NetworkClient: Forward complete")
            } else {
                print("❌ NetworkClient: onFileTransferConnection callback is nil!")
            }
        }

        // Wire up PierceFirewall for indirect connections
        // First check if it matches a pending browse request, then delegate to DownloadManager
        peerConnectionPool.onPierceFirewall = { [weak self] token, connection in
            print("🔓 NetworkClient: PierceFirewall token=\(token)")
            // Check if this is for a pending browse request
            if self?.handlePierceFirewallForBrowse(token: token, connection: connection) == true {
                print("🔓 NetworkClient: PierceFirewall handled as browse request")
                return
            }
            // Otherwise, delegate to DownloadManager
            await self?.onPierceFirewall?(token, connection)
        }

        // Wire up upload denied/failed
        peerConnectionPool.onUploadDenied = { [weak self] filename, reason in
            print("🚫 NetworkClient: Upload denied: \(filename) - \(reason)")
            self?.onUploadDenied?(filename, reason)
        }

        peerConnectionPool.onUploadFailed = { [weak self] filename in
            print("❌ NetworkClient: Upload failed: \(filename)")
            self?.onUploadFailed?(filename)
        }

        // Wire up QueueUpload for upload handling
        peerConnectionPool.onQueueUpload = { [weak self] username, filename, connection in
            print("📥 NetworkClient: QueueUpload from \(username): \(filename)")
            await self?.onQueueUpload?(username, filename, connection)
        }

        // Wire up TransferResponse for upload handling
        peerConnectionPool.onTransferResponse = { [weak self] token, allowed, filesize, connection in
            print("📨 NetworkClient: TransferResponse token=\(token) allowed=\(allowed)")
            await self?.onTransferResponse?(token, allowed, filesize, connection)
        }

        // Wire up FolderContentsRequest for folder browsing
        peerConnectionPool.onFolderContentsRequest = { [weak self] username, token, folder, connection in
            print("📁 NetworkClient: FolderContentsRequest from \(username): \(folder)")
            await self?.handleFolderContentsRequest(username: username, token: token, folder: folder, connection: connection)
        }

        // Wire up FolderContentsResponse for folder browsing
        peerConnectionPool.onFolderContentsResponse = { [weak self] token, folder, files in
            print("📁 NetworkClient: FolderContentsResponse: \(folder) with \(files.count) files")
            self?.onFolderContentsResponse?(token, folder, files)
        }

        // Wire up PlaceInQueueRequest for queue position management
        peerConnectionPool.onPlaceInQueueRequest = { [weak self] username, filename, connection in
            print("📊 NetworkClient: PlaceInQueueRequest from \(username): \(filename)")
            await self?.onPlaceInQueueRequest?(username, filename, connection)
        }

        // Wire up SharesRequest for when peers want to browse our shared files
        peerConnectionPool.onSharesRequest = { [weak self] username, connection in
            print("📂 NetworkClient: SharesRequest from \(username) - sending our shares")
            await self?.handleSharesRequest(username: username, connection: connection)
        }

        // Wire up UserInfoRequest for when peers want our user info
        peerConnectionPool.onUserInfoRequest = { [weak self] username, connection in
            print("👤 NetworkClient: UserInfoRequest from \(username) - sending our user info")
            await self?.handleUserInfoRequest(username: username, connection: connection)
        }

        // Wire up user IP discovery for country flags
        peerConnectionPool.onUserIPDiscovered = { [weak self] username, ip in
            self?.userInfoCache.registerIP(ip, for: username)
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
    /// @deprecated Use addPeerAddressHandler() instead for multi-listener support
    var onPeerAddress: ((String, String, Int) -> Void)?

    // Multi-listener support for peer address responses
    // This fixes the issue where DownloadManager and UploadManager callbacks could overwrite each other
    private var peerAddressHandlers: [(String, String, Int) -> Void] = []

    /// Add a handler for peer address responses (supports multiple listeners)
    func addPeerAddressHandler(_ handler: @escaping (String, String, Int) -> Void) {
        peerAddressHandlers.append(handler)
        print("🔧 NetworkClient: Added peer address handler (total: \(peerAddressHandlers.count))")
    }
    var onIncomingConnectionMatched: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, connection)
    var onFileTransferConnection: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, connection)
    var onPierceFirewall: ((UInt32, PeerConnection) async -> Void)?  // (token, connection)
    var onUploadDenied: ((String, String) -> Void)?  // (filename, reason)
    var onUploadFailed: ((String) -> Void)?  // filename
    var onQueueUpload: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection) - peer wants to download from us
    var onTransferResponse: ((UInt32, Bool, UInt64?, PeerConnection) async -> Void)?  // (token, allowed, filesize?, connection)
    var onFolderContentsRequest: ((String, UInt32, String, PeerConnection) async -> Void)?  // (username, token, folder, connection) - peer wants folder contents
    var onFolderContentsResponse: ((UInt32, String, [SharedFile]) -> Void)?  // (token, folder, files)
    var onPlaceInQueueRequest: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection)

    // User interests & recommendations callbacks
    var onRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    var onGlobalRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    var onUserInterests: ((String, [String], [String]) -> Void)?  // (username, likes, hates)
    var onSimilarUsers: (([(username: String, rating: UInt32)]) -> Void)?
    var onItemRecommendations: ((String, [(item: String, score: Int32)]) -> Void)?  // (item, recommendations)
    var onItemSimilarUsers: ((String, [String]) -> Void)?  // (item, users)

    // User stats & privileges callbacks
    var onUserStatus: ((String, UserStatus, Bool) -> Void)?  // (username, status, privileged)
    var onUserStats: ((String, UInt32, UInt64, UInt32, UInt32) -> Void)?  // (username, avgSpeed, uploadNum, files, dirs)
    var onPrivilegesChecked: ((UInt32) -> Void)?  // timeLeft in seconds
    var onUserPrivileges: ((String, Bool) -> Void)?  // (username, privileged)
    var onPrivilegedUsers: (([String]) -> Void)?  // list of privileged usernames

    // Room ticker callbacks
    var onRoomTickerState: ((String, [(username: String, ticker: String)]) -> Void)?  // (room, tickers)
    var onRoomTickerAdd: ((String, String, String) -> Void)?  // (room, username, ticker)
    var onRoomTickerRemove: ((String, String) -> Void)?  // (room, username)

    // Wishlist callback
    var onWishlistInterval: ((UInt32) -> Void)?  // interval in seconds

    // Private room callbacks
    var onPrivateRoomMembers: ((String, [String]) -> Void)?  // (room, members)
    var onPrivateRoomMemberAdded: ((String, String) -> Void)?  // (room, username)
    var onPrivateRoomMemberRemoved: ((String, String) -> Void)?  // (room, username)
    var onPrivateRoomOperatorGranted: ((String) -> Void)?  // room
    var onPrivateRoomOperatorRevoked: ((String) -> Void)?  // room
    var onPrivateRoomOperators: ((String, [String]) -> Void)?  // (room, operators)

    // MARK: - Connection

    func connect(server: String, port: UInt16, username: String, password: String, preferredListenPort: UInt16? = nil) async {
        guard !isConnecting && !isConnected else { return }

        isConnecting = true
        connectionError = nil
        self.username = username
        peerConnectionPool.ourUsername = username  // Set for PeerInit messages
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
            peerConnectionPool.listenPort = ports.port  // For NAT traversal - bind outgoing connections to listen port
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

                // Tell server we accept child connections
                let acceptChildrenMessage = MessageBuilder.acceptChildren(acceptDistributedChildren)
                try await connection.send(acceptChildrenMessage)
                print("🌐 Sent AcceptChildren(\(acceptDistributedChildren))")

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
        // Check if UPnP/NAT-PMP is enabled in settings
        let enableNAT = UserDefaults.standard.object(forKey: "settings.enableUPnP") == nil
            ? true  // Default to enabled
            : UserDefaults.standard.bool(forKey: "settings.enableUPnP")

        if !enableNAT {
            print("🔧 NAT: Port mapping disabled in settings")
            // Still try to discover external IP via STUN/web service (non-invasive)
            if let extIP = await natService.discoverExternalIP() {
                await MainActor.run {
                    self.externalIP = extIP
                }
                print("✅ NAT: External IP: \(extIP)")
            }
            return
        }

        print("🔧 NAT: Starting background port mapping...")

        // Add delay to avoid triggering IDS with rapid network activity at startup
        try? await Task.sleep(for: .seconds(2))

        // Try to map the listen port
        do {
            let mappedPort = try await natService.mapPort(listenPort)
            print("✅ NAT: Mapped port \(listenPort) -> \(mappedPort)")
        } catch {
            print("⚠️ NAT: Port mapping failed (will rely on server-mediated connections)")
        }

        // Small delay between mapping attempts to avoid IDS triggers
        try? await Task.sleep(for: .milliseconds(500))

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

            for await message in connection.messages {
                await self.handleMessage(message)
            }

            // Stream ended (connection closed)
            await MainActor.run {
                self.connectionError = "Connection closed"
                self.isConnected = false
                self.onConnectionStatusChanged?(.disconnected)
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

    /// Tell server we couldn't connect to a peer (used by peer responding to us)
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

    /// Request server to tell peer to connect to us (indirect connection request)
    /// Server will forward this to the peer, who will then send PierceFirewall to us
    func sendConnectToPeer(token: UInt32, username: String, connectionType: String = "P") async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.connectToPeer(token: token, username: username, connectionType: connectionType)
        do {
            try await connection.send(message)
            logger.info("Sent ConnectToPeer for \(username) token=\(token) type=\(connectionType)")
            print("📤 Sent ConnectToPeer: token=\(token) username=\(username) type=\(connectionType)")
        } catch {
            logger.error("Failed to send ConnectToPeer: \(error.localizedDescription)")
        }
    }

    // MARK: - Peer Address Response Handling

    /// Internal handler for peer address responses - dispatches to pending requests AND all registered handlers
    func handlePeerAddressResponse(username: String, ip: String, port: Int) {
        print("🔔 handlePeerAddressResponse: \(username) @ \(ip):\(port)")

        // Check for pending internal request (browse/folder)
        if let continuation = pendingPeerAddressRequests.removeValue(forKey: username) {
            print("  → Resuming pending getPeerAddress continuation")
            continuation.resume(returning: (ip, port))
        }

        // Call all registered handlers (multi-listener pattern)
        if !peerAddressHandlers.isEmpty {
            print("  → Calling \(peerAddressHandlers.count) registered peer address handlers")
            for handler in peerAddressHandlers {
                handler(username, ip, port)
            }
        }

        // Also call legacy single callback for backward compatibility
        if onPeerAddress != nil {
            print("  → Forwarding to legacy onPeerAddress callback")
            onPeerAddress?(username, ip, port)
        }

        if peerAddressHandlers.isEmpty && onPeerAddress == nil {
            print("  ⚠️ No peer address handlers registered!")
        }
    }

    /// Request peer address and wait for response (concurrent-safe)
    /// Can be called from multiple places concurrently - each request gets its own continuation
    func getPeerAddress(for username: String, timeout: Duration = .seconds(10)) async throws -> (ip: String, port: Int) {
        // Check if there's already a pending request for this user
        if pendingPeerAddressRequests[username] != nil {
            // Another request is in flight - wait a bit and try to get existing connection
            try await Task.sleep(for: .milliseconds(500))
            if let existingConnection = peerConnectionPool.getConnectionForUser(username) {
                let info = existingConnection.peerInfo
                return (info.ip, info.port)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Register pending request
            pendingPeerAddressRequests[username] = continuation

            // Request the peer address
            Task {
                do {
                    try await self.getUserAddress(username)
                } catch {
                    // Remove and resume with error if request fails
                    if self.pendingPeerAddressRequests.removeValue(forKey: username) != nil {
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Timeout
            Task {
                try? await Task.sleep(for: timeout)
                // Remove and resume with timeout if still pending
                if self.pendingPeerAddressRequests.removeValue(forKey: username) != nil {
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        }
    }

    // MARK: - Peer Connections

    // Pending browse requests waiting for indirect connections (keyed by TOKEN)
    // When peer connects via PierceFirewall, they send the same token we used in ConnectToPeer
    private var pendingBrowseConnections: [UInt32: (username: String, continuation: CheckedContinuation<PeerConnection, Error>)] = [:]

    /// Browse a user's shared files
    func browseUser(_ username: String) async throws -> [SharedFile] {
        print("📂 Browse: START browseUser(\(username))")
        guard isConnected else {
            print("📂 Browse: ERROR - not connected")
            throw NetworkError.notConnected
        }

        var connection: PeerConnection

        // Step 0: Check if we already have an active connection to this user
        // This is common - the peer may have connected to us for search results
        if let existingConnection = peerConnectionPool.getConnectionForUser(username) {
            print("📂 Browse: Found existing connection to \(username), reusing it!")
            connection = existingConnection
        } else {
            // No existing connection - need to establish one
            let token = UInt32.random(in: 0...UInt32.max)
            print("📂 Browse: No existing connection, using token \(token) for \(username)")

            // Step 1: Send ConnectToPeer to server FIRST
            // This tells the server to forward a connection request to the peer
            // The peer will then try to connect to us with PierceFirewall
            await sendConnectToPeer(token: token, username: username, connectionType: "P")
            print("📂 Browse: Sent ConnectToPeer to server")

            // Step 2: Get peer address
            print("📂 Browse: Getting peer address for \(username)...")
            let (ip, port) = try await getPeerAddress(for: username)

            logger.info("Got peer address for \(username): \(ip):\(port)")
            print("📂 Browse: Got address \(ip):\(port), attempting direct connection...")

            // Step 3: Try direct connection first
            do {
                connection = try await peerConnectionPool.connect(
                    to: username,
                    ip: ip,
                    port: port,
                    token: token
                )
                print("📂 Browse: Direct connection to \(username) successful!")
            } catch {
                // Direct connection failed - wait for indirect connection
                // The server already told the peer to connect to us (step 1)
                // The peer will send PierceFirewall with the same token
                print("📂 Browse: Direct connection failed (\(error.localizedDescription)), waiting for indirect...")
                logger.info("Direct connection to \(username) failed, waiting for PierceFirewall")
                print("📂 Browse: Waiting for PierceFirewall with token=\(token)...")

                // Wait for the peer to connect to us via PierceFirewall with matching token
                connection = try await waitForIndirectBrowseConnection(token: token, username: username, timeout: 15)
                print("📂 Browse: Indirect connection from \(username) received via PierceFirewall!")
            }
        }

        print("📂 Browse: Connected to \(username), waiting for peer handshake...")

        // Wait for peer's PeerInit before sending any requests
        // Per SoulSeek protocol: after establishing P connection, we send PeerInit
        // and MUST wait for peer's PeerInit before sending SharesRequest
        try await connection.waitForPeerHandshake(timeout: .seconds(10))
        print("📂 Browse: Peer handshake complete, setting up callback...")

        // Set up callback BEFORE requesting shares
        nonisolated(unsafe) var sharesResumed = false
        nonisolated(unsafe) var receivedFiles: [SharedFile] = []

        // Set up the callback first (outside the continuation to avoid race)
        await connection.setOnSharesReceived { files in
            print("📂 Browse: Callback received \(files.count) files from \(username)")
            receivedFiles = files
            sharesResumed = true
        }

        // Request shares
        print("📂 Browse: Requesting shares from \(username)...")
        try await connection.requestShares()
        print("📂 Browse: Shares request sent, waiting for response...")

        // Poll for response with timeout
        let startTime = Date()
        let timeoutSeconds: TimeInterval = 30

        while !sharesResumed {
            try await Task.sleep(for: .milliseconds(100))

            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                print("📂 Browse: Timeout waiting for shares from \(username)")
                throw NetworkError.timeout
            }
        }

        print("📂 Browse: Got \(receivedFiles.count) files from \(username)")
        return receivedFiles
    }

    /// Wait for an indirect connection via PierceFirewall with matching token
    private func waitForIndirectBrowseConnection(token: UInt32, username: String, timeout: TimeInterval) async throws -> PeerConnection {
        return try await withCheckedThrowingContinuation { continuation in
            // Register that we're waiting for this token
            pendingBrowseConnections[token] = (username: username, continuation: continuation)
            print("📂 Browse: Registered pending browse for token=\(token) username=\(username)")

            // Set up timeout
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                // If still pending, resume with timeout error
                if let pending = pendingBrowseConnections.removeValue(forKey: token) {
                    print("📂 Browse: Timeout waiting for PierceFirewall from \(pending.username) (token=\(token))")
                    pending.continuation.resume(throwing: NetworkError.timeout)
                }
            }
        }
    }

    /// Called when PierceFirewall is received - check if it matches a pending browse request
    /// Returns true if it was handled as a browse request
    func handlePierceFirewallForBrowse(token: UInt32, connection: PeerConnection) -> Bool {
        if let pending = pendingBrowseConnections.removeValue(forKey: token) {
            print("📂 Browse: PierceFirewall token=\(token) matched pending browse for \(pending.username)")
            pending.continuation.resume(returning: connection)
            return true
        }
        return false
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like
    func addThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingILike(item)
        try await serverConnection?.send(message)
        logger.info("Added thing I like: \(item)")
    }

    /// Remove something I like
    func removeThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingILike(item)
        try await serverConnection?.send(message)
        logger.info("Removed thing I like: \(item)")
    }

    /// Add something I hate
    func addThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingIHate(item)
        try await serverConnection?.send(message)
        logger.info("Added thing I hate: \(item)")
    }

    /// Remove something I hate
    func removeThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingIHate(item)
        try await serverConnection?.send(message)
        logger.info("Removed thing I hate: \(item)")
    }

    /// Get my recommendations
    func getRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getRecommendations()
        try await serverConnection?.send(message)
        logger.info("Requested recommendations")
    }

    /// Get global (network-wide) recommendations - popular interests across all users
    func getGlobalRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getGlobalRecommendations()
        try await serverConnection?.send(message)
        logger.info("Requested global recommendations")
    }

    /// Get a user's interests
    func getUserInterests(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserInterests(username)
        try await serverConnection?.send(message)
        logger.info("Requested interests for: \(username)")
    }

    /// Get similar users
    func getSimilarUsers() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getSimilarUsers()
        try await serverConnection?.send(message)
        logger.info("Requested similar users")
    }

    /// Get recommendations for an item
    func getItemRecommendations(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemRecommendations(item)
        try await serverConnection?.send(message)
        logger.info("Requested recommendations for item: \(item)")
    }

    /// Get similar users for an item
    func getItemSimilarUsers(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemSimilarUsers(item)
        try await serverConnection?.send(message)
        logger.info("Requested similar users for item: \(item)")
    }

    // MARK: - User Watching (Buddy List)

    /// Watch a user (receive status updates)
    func watchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.watchUserMessage(username: username)
        try await serverConnection?.send(message)
        logger.info("Watching user: \(username)")
    }

    /// Stop watching a user
    func unwatchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.unwatchUserMessage(username: username)
        try await serverConnection?.send(message)
        logger.info("Unwatched user: \(username)")
    }

    /// Get a user's current status
    func getUserStatus(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStatusMessage(username: username)
        try await serverConnection?.send(message)
        logger.info("Requested status for: \(username)")
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (speed, files, dirs)
    func getUserStats(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStats(username)
        try await serverConnection?.send(message)
        logger.info("Requested stats for: \(username)")
    }

    /// Check our privilege time remaining
    func checkPrivileges() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.checkPrivileges()
        try await serverConnection?.send(message)
        logger.info("Checking privileges")
    }

    /// Get a user's privilege status
    func getUserPrivileges(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserPrivileges(username)
        try await serverConnection?.send(message)
        logger.info("Requested privileges for: \(username)")
    }

    // MARK: - Room Tickers

    /// Set a ticker message for a room
    func setRoomTicker(room: String, ticker: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.setRoomTicker(room: room, ticker: ticker)
        try await serverConnection?.send(message)
        logger.info("Set ticker in \(room): \(ticker)")
    }

    // MARK: - Room Search & Wishlist

    /// Search within a specific room
    func searchRoom(_ room: String, query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.roomSearch(room: room, token: token, query: query)
        try await serverConnection?.send(message)
        logger.info("Room search in \(room): \(query)")
    }

    /// Add a wishlist search (runs periodically)
    func addWishlistSearch(query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.wishlistSearch(token: token, query: query)
        try await serverConnection?.send(message)
        logger.info("Added wishlist search: \(query)")
    }

    // MARK: - Private Rooms

    /// Add a member to a private room
    func addPrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddMember(room: room, username: username)
        try await serverConnection?.send(message)
        logger.info("Adding \(username) to private room \(room)")
    }

    /// Remove a member from a private room
    func removePrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveMember(room: room, username: username)
        try await serverConnection?.send(message)
        logger.info("Removing \(username) from private room \(room)")
    }

    /// Leave a private room
    func leavePrivateRoom(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelMembership(room: room)
        try await serverConnection?.send(message)
        logger.info("Leaving private room \(room)")
    }

    /// Give up ownership of a private room
    func giveUpPrivateRoomOwnership(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelOwnership(room: room)
        try await serverConnection?.send(message)
        logger.info("Giving up ownership of \(room)")
    }

    /// Add an operator to a private room
    func addPrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddOperator(room: room, username: username)
        try await serverConnection?.send(message)
        logger.info("Adding \(username) as operator in \(room)")
    }

    /// Remove an operator from a private room
    func removePrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveOperator(room: room, username: username)
        try await serverConnection?.send(message)
        logger.info("Removing \(username) as operator from \(room)")
    }

    // MARK: - Distributed Network

    /// Update whether we accept distributed children
    func setAcceptDistributedChildren(_ accept: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        acceptDistributedChildren = accept
        let message = MessageBuilder.acceptChildren(accept)
        try await serverConnection?.send(message)
        logger.info("Set AcceptChildren(\(accept))")
    }

    /// Update our branch level
    func setDistributedBranchLevel(_ level: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchLevel = level
        let message = MessageBuilder.branchLevel(level)
        try await serverConnection?.send(message)
        logger.info("Set BranchLevel(\(level))")
    }

    /// Update our branch root
    func setDistributedBranchRoot(_ root: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchRoot = root
        let message = MessageBuilder.branchRoot(root)
        try await serverConnection?.send(message)
        logger.info("Set BranchRoot(\(root))")
    }

    /// Update our child depth
    func setDistributedChildDepth(_ depth: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.childDepth(depth)
        try await serverConnection?.send(message)
        logger.info("Set ChildDepth(\(depth))")
    }

    /// Add a distributed child connection
    func addDistributedChild(_ connection: PeerConnection) {
        self.distributedChildren.append(connection)
        let count = self.distributedChildren.count
        self.logger.info("Added distributed child, total: \(count)")
    }

    /// Remove a distributed child connection
    func removeDistributedChild(_ connection: PeerConnection) async {
        self.distributedChildren.removeAll { $0 === connection }
        let count = self.distributedChildren.count
        self.logger.info("Removed distributed child, total: \(count)")
    }

    /// Forward a distributed search to all children
    func forwardDistributedSearch(unknown: UInt32, username: String, token: UInt32, query: String) async {
        guard !self.distributedChildren.isEmpty else { return }

        self.logger.info("Forwarding distributed search to \(self.distributedChildren.count) children")

        for child in self.distributedChildren {
            do {
                // Build the distributed search message
                var searchPayload = Data()
                searchPayload.appendUInt8(DistributedMessageCode.searchRequest.rawValue)
                searchPayload.appendUInt32(unknown)
                searchPayload.appendString(username)
                searchPayload.appendUInt32(token)
                searchPayload.appendString(query)

                var message = Data()
                message.appendUInt32(UInt32(searchPayload.count))
                message.append(searchPayload)

                try await child.send(message)
            } catch {
                logger.error("Failed to forward search to child: \(error.localizedDescription)")
            }
        }
    }

    /// Get number of distributed children
    var distributedChildCount: Int { distributedChildren.count }

    // MARK: - Folder Browsing

    /// Handle incoming folder contents request - respond with our files in that folder
    private func handleFolderContentsRequest(username: String, token: UInt32, folder: String, connection: PeerConnection) async {
        logger.info("Folder contents request from \(username) for: \(folder)")

        // Find files in the requested folder
        let filesInFolder = shareManager.fileIndex.filter { file in
            file.sharedPath.hasPrefix(folder + "\\") || file.sharedPath == folder
        }

        if filesInFolder.isEmpty {
            logger.info("No files found in folder: \(folder)")
            // Still send empty response
        }

        // Build file list
        let files: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] = filesInFolder.map { file in
            var attributes: [(UInt32, UInt32)] = []
            if let bitrate = file.bitrate {
                attributes.append((0, bitrate))
            }
            if let duration = file.duration {
                attributes.append((1, duration))
            }
            return (
                filename: file.filename,
                size: file.size,
                extension_: file.fileExtension,
                attributes: attributes
            )
        }

        do {
            try await connection.sendFolderContents(token: token, folder: folder, files: files)
            logger.info("Sent folder contents: \(folder) (\(files.count) files)")
        } catch {
            logger.error("Failed to send folder contents: \(error.localizedDescription)")
        }
    }

    // MARK: - Shares Request Handling

    /// Handle incoming shares request - respond with our shared file list
    private func handleSharesRequest(username: String, connection: PeerConnection) async {
        logger.info("Shares request from \(username)")
        print("📂 Handling SharesRequest from \(username)")

        // Group files by directory
        var directoriesMap: [String: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)]] = [:]

        for file in shareManager.fileIndex {
            // Get the directory path
            let components = file.sharedPath.split(separator: "\\")
            guard components.count > 1 else { continue }

            let directory = components.dropLast().joined(separator: "\\")
            let filename = String(components.last!)

            directoriesMap[directory, default: []].append((
                filename: filename,
                size: file.size,
                bitrate: file.bitrate,
                duration: file.duration
            ))
        }

        // Convert to array format
        let directories: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])] =
            directoriesMap.map { (directory: $0.key, files: $0.value) }
                .sorted { $0.directory < $1.directory }

        print("📂 Sending \(directories.count) directories with \(shareManager.totalFiles) total files to \(username)")

        do {
            try await connection.sendShares(files: directories)
            logger.info("Sent shares to \(username): \(directories.count) directories")
        } catch {
            logger.error("Failed to send shares to \(username): \(error.localizedDescription)")
            print("❌ Failed to send shares: \(error)")
        }
    }

    // MARK: - User Info Request Handling

    /// Handle incoming user info request - respond with our profile info
    private func handleUserInfoRequest(username: String, connection: PeerConnection) async {
        logger.info("User info request from \(username)")
        print("👤 Handling UserInfoRequest from \(username)")

        // Get upload stats
        let totalUploads = UInt32(shareManager.totalFiles)  // Could track actual upload count
        let queueSize = UInt32(0)  // Could get from upload manager
        let hasFreeSlots = true  // Could check upload manager

        // User description - could be configurable
        let description = "SeeleSeek - Soulseek client for macOS"

        do {
            try await connection.sendUserInfo(
                description: description,
                picture: nil,  // No picture support yet
                totalUploads: totalUploads,
                queueSize: queueSize,
                hasFreeSlots: hasFreeSlots
            )
            logger.info("Sent user info to \(username)")
            print("👤 Sent user info to \(username)")
        } catch {
            logger.error("Failed to send user info to \(username): \(error.localizedDescription)")
            print("❌ Failed to send user info: \(error)")
        }
    }

    /// Request folder contents from a peer
    func requestFolderContents(from username: String, folder: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }

        let token = UInt32.random(in: 0...UInt32.max)

        // Check if we have an existing connection to this user
        if let existingConnection = peerConnectionPool.getConnectionForUser(username) {
            try await existingConnection.requestFolderContents(token: token, folder: folder)
            return
        }

        // Need to establish connection first - use concurrent-safe method
        let (ip, port) = try await getPeerAddress(for: username)

        // Connect to peer
        let connectionToken = UInt32.random(in: 0...UInt32.max)
        let connection = try await peerConnectionPool.connect(
            to: username,
            ip: ip,
            port: port,
            token: connectionToken
        )

        // Request folder contents
        try await connection.requestFolderContents(token: token, folder: folder)
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
