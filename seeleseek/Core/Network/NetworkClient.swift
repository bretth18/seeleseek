import Foundation
import Network
import os
import CryptoKit
import Synchronization

/// Main network interface that coordinates server and peer connections
@Observable
@MainActor
final class NetworkClient {
    private nonisolated let logger = Logger(subsystem: "com.seeleseek", category: "NetworkClient")

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
    private var pingTask: Task<Void, Never>?
    private var loginContinuation: CheckedContinuation<Bool, Error>?

    // MARK: - Keepalive Configuration
    /// Interval between ping messages (5 minutes)
    private static let pingInterval: TimeInterval = 300

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
    // Uses (continuation, requestID) to prevent double-resume when same user is requested multiple times
    private var pendingPeerAddressRequests: [String: (continuation: CheckedContinuation<(ip: String, port: Int), Error>, requestID: UUID)] = [:]

    // MARK: - Pending Status Requests (for checking if user is online before browse/download)
    private var pendingStatusRequests: [String: CheckedContinuation<(status: UserStatus, privileged: Bool), Never>] = [:]

    // MARK: - Initialization

    init() {
        logger.info("NetworkClient initializing...")
        // Wire up peer connection pool callbacks to network client
        peerConnectionPool.onSearchResults = { [weak self] token, results in
            self?.logger.debug("NetworkClient: Received \(results.count) results for token \(token)")
            if self?.onSearchResults != nil {
                self?.logger.debug("NetworkClient: Forwarding to SearchState callback...")
                self?.onSearchResults?(token, results)
                self?.logger.debug("NetworkClient: Callback completed")
            } else {
                self?.logger.warning("NetworkClient: onSearchResults callback is nil!")
            }
        }

        // Wire up incoming connection matching for downloads
        peerConnectionPool.onIncomingConnectionMatched = { [weak self] username, token, connection in
            self?.logger.debug("NetworkClient: Incoming connection matched: \(username) token=\(token)")
            await self?.onIncomingConnectionMatched?(username, token, connection)
        }

        // Wire up file transfer connections
        peerConnectionPool.onFileTransferConnection = { [weak self] username, token, connection in
            self?.logger.debug("NetworkClient: File transfer connection received - username='\(username)' token=\(token)")
            if self?.onFileTransferConnection != nil {
                self?.logger.debug("NetworkClient: Forwarding to DownloadManager...")
                await self?.onFileTransferConnection?(username, token, connection)
                self?.logger.debug("NetworkClient: Forward complete")
            } else {
                self?.logger.warning("NetworkClient: onFileTransferConnection callback is nil!")
            }
        }

        // Wire up PierceFirewall for indirect connections
        // First check if it matches a pending browse request, then delegate to DownloadManager
        peerConnectionPool.onPierceFirewall = { [weak self] token, connection in
            self?.logger.debug("NetworkClient: PierceFirewall token=\(token)")
            // Check if this is for a pending browse request
            if self?.handlePierceFirewallForBrowse(token: token, connection: connection) == true {
                self?.logger.debug("NetworkClient: PierceFirewall handled as browse request")
                return
            }
            // Otherwise, delegate to DownloadManager
            await self?.onPierceFirewall?(token, connection)
        }

        // Wire up upload denied/failed
        peerConnectionPool.onUploadDenied = { [weak self] filename, reason in
            self?.logger.warning("NetworkClient: Upload denied: \(filename) - \(reason)")
            self?.onUploadDenied?(filename, reason)
        }

        peerConnectionPool.onUploadFailed = { [weak self] filename in
            self?.logger.warning("NetworkClient: Upload failed: \(filename)")
            self?.onUploadFailed?(filename)
        }

        // Wire up QueueUpload for upload handling
        peerConnectionPool.onQueueUpload = { [weak self] username, filename, connection in
            self?.logger.info("NetworkClient: QueueUpload from \(username): \(filename)")
            await self?.onQueueUpload?(username, filename, connection)
        }

        // Wire up TransferResponse for upload handling
        peerConnectionPool.onTransferResponse = { [weak self] token, allowed, filesize, connection in
            self?.logger.debug("NetworkClient: TransferResponse token=\(token) allowed=\(allowed)")
            await self?.onTransferResponse?(token, allowed, filesize, connection)
        }

        // Wire up FolderContentsRequest for folder browsing
        peerConnectionPool.onFolderContentsRequest = { [weak self] username, token, folder, connection in
            self?.logger.debug("NetworkClient: FolderContentsRequest from \(username): \(folder)")
            await self?.handleFolderContentsRequest(username: username, token: token, folder: folder, connection: connection)
        }

        // Wire up FolderContentsResponse for folder browsing
        peerConnectionPool.onFolderContentsResponse = { [weak self] token, folder, files in
            self?.logger.debug("NetworkClient: FolderContentsResponse: \(folder) with \(files.count) files")
            self?.onFolderContentsResponse?(token, folder, files)
        }

        // Wire up PlaceInQueueRequest for queue position management
        peerConnectionPool.onPlaceInQueueRequest = { [weak self] username, filename, connection in
            self?.logger.debug("NetworkClient: PlaceInQueueRequest from \(username): \(filename)")
            await self?.onPlaceInQueueRequest?(username, filename, connection)
        }

        // Wire up PlaceInQueueReply for download queue position updates
        peerConnectionPool.onPlaceInQueueReply = { [weak self] username, filename, position in
            self?.logger.debug("NetworkClient: PlaceInQueueReply from \(username): \(filename) pos=\(position)")
            await self?.onPlaceInQueueReply?(username, filename, position)
        }

        // Wire up SharesRequest for when peers want to browse our shared files
        peerConnectionPool.onSharesRequest = { [weak self] username, connection in
            self?.logger.info("NetworkClient: SharesRequest from \(username) - sending our shares")
            await self?.handleSharesRequest(username: username, connection: connection)
        }

        // Wire up UserInfoRequest for when peers want our user info
        peerConnectionPool.onUserInfoRequest = { [weak self] username, connection in
            self?.logger.info("NetworkClient: UserInfoRequest from \(username) - sending our user info")
            await self?.handleUserInfoRequest(username: username, connection: connection)
        }

        // Wire up shares received through pool (for unsolicited shares or pool-routed browse)
        peerConnectionPool.onSharesReceived = { [weak self] username, files in
            self?.logger.info("NetworkClient: Received \(files.count) shared files from \(username) via pool")
        }

        // Wire up user IP discovery for country flags
        peerConnectionPool.onUserIPDiscovered = { [weak self] username, ip in
            self?.userInfoCache.registerIP(ip, for: username)
        }

        logger.info("NetworkClient initialized, callbacks wired")
    }

    // MARK: - Callbacks
    var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    var onSearchResults: ((UInt32, [SearchResult]) -> Void)?  // (token, results)
    var onRoomList: (([ChatRoom]) -> Void)?
    var onRoomListFull: ((_ publicRooms: [ChatRoom], _ ownedPrivate: [ChatRoom], _ memberPrivate: [ChatRoom], _ operated: [String]) -> Void)?
    var onRoomMessage: ((String, ChatMessage) -> Void)?
    var onPrivateMessage: ((String, ChatMessage) -> Void)?
    var onRoomJoined: ((String, [String], String?, [String]) -> Void)?  // (room, users, owner?, operators)
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
        logger.debug("NetworkClient: Added peer address handler (total: \(self.peerAddressHandlers.count))")
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
    var onPlaceInQueueReply: ((String, String, UInt32) async -> Void)?  // (username, filename, position)

    // User interests & recommendations callbacks
    var onRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    var onGlobalRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    var onUserInterests: ((String, [String], [String]) -> Void)?  // (username, likes, hates)
    var onSimilarUsers: (([(username: String, rating: UInt32)]) -> Void)?
    var onItemRecommendations: ((String, [(item: String, score: Int32)]) -> Void)?  // (item, recommendations)
    var onItemSimilarUsers: ((String, [String]) -> Void)?  // (item, users)

    // Profile data provider - returns (description, picture) for UserInfoResponse
    var profileDataProvider: (() -> (description: String, picture: Data?))?

    // Search response filter - returns (respondToSearches, minQueryLength, maxResults)
    var searchResponseFilter: (() -> (enabled: Bool, minQueryLength: Int, maxResults: Int))?

    // User stats & privileges callbacks
    private var userStatusHandlers: [(String, UserStatus, Bool) -> Void] = []
    /// Register a handler for user status updates. Multiple handlers supported.
    func addUserStatusHandler(_ handler: @escaping (String, UserStatus, Bool) -> Void) {
        userStatusHandlers.append(handler)
    }
    private var userStatsHandlers: [(String, UInt32, UInt64, UInt32, UInt32) -> Void] = []
    /// Register a handler for user stats updates. Multiple handlers supported.
    func addUserStatsHandler(_ handler: @escaping (String, UInt32, UInt64, UInt32, UInt32) -> Void) {
        userStatsHandlers.append(handler)
    }
    /// Dispatch user stats to all registered handlers
    func dispatchUserStats(username: String, avgSpeed: UInt32, uploadNum: UInt64, files: UInt32, dirs: UInt32) {
        for handler in userStatsHandlers {
            handler(username, avgSpeed, uploadNum, files, dirs)
        }
    }
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

    // Admin/system message callback
    var onAdminMessage: ((String) -> Void)?  // Server-wide admin message

    // Excluded search phrases callback
    var onExcludedSearchPhrases: (([String]) -> Void)?  // Phrases excluded from search by server

    // Room membership callbacks
    var onRoomMembershipGranted: ((String) -> Void)?  // room name
    var onRoomMembershipRevoked: ((String) -> Void)?  // room name
    var onRoomInvitationsEnabled: ((Bool) -> Void)?  // enabled
    var onPasswordChanged: ((String) -> Void)?  // confirmed password
    var onRoomAdded: ((String) -> Void)?  // room name
    var onRoomRemoved: ((String) -> Void)?  // room name

    // Can't create room callback
    var onCantCreateRoom: ((String) -> Void)?  // room name

    // Can't connect to peer callback (server tells us indirect connection failed)
    var onCantConnectToPeer: ((UInt32) -> Void)?  // token

    // Global room callback
    var onGlobalRoomMessage: ((String, String, String) -> Void)?  // (room, username, message)
    var onProtocolNotice: ((UInt32, Data) -> Void)?  // (server code, raw payload)

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
                logger.info("Incoming peer connection received (obfuscated: \(isObfuscated))")
                self.logger.info("Incoming peer connection (obfuscated: \(isObfuscated))")
                await self.peerConnectionPool.handleIncomingConnection(connection)
            }

            // Step 2: Start listener for incoming peer connections
            logger.info("Starting listener...")
            let portDesc = preferredListenPort?.description ?? "auto"
            logger.info("Starting listener service (preferred port: \(portDesc))...")
            let ports = try await listenerService.start(preferredPort: preferredListenPort)
            listenPort = ports.port
            obfuscatedPort = ports.obfuscatedPort
            peerConnectionPool.listenPort = ports.port  // For NAT traversal - bind outgoing connections to listen port
            logger.info("Listening on port \(self.listenPort)")
            logger.info("Listening on port \(self.listenPort) (obfuscated: \(self.obfuscatedPort))")

            // Step 3: Connect to server FIRST (NAT runs in background)
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

            // Wait for login response using continuation (resumed by setLoggedIn)
            let loginSuccess: Bool
            do {
                loginSuccess = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    self.loginContinuation = continuation

                    // Timeout after 10 seconds so we don't wait forever
                    Task {
                        try? await Task.sleep(for: .seconds(10))
                        if let pending = self.loginContinuation {
                            self.loginContinuation = nil
                            pending.resume(throwing: ServerConnection.ConnectionError.timeout)
                        }
                    }
                }
            } catch {
                // Login timed out or failed via continuation
                isConnecting = false
                isConnected = false
                connectionError = error.localizedDescription
                onConnectionStatusChanged?(.disconnected)
                await listenerService.stop()
                return
            }

            if loginSuccess {
                // Step 5: Send listen port to server
                logger.info("Sending listen port...")
                let portMessage = MessageBuilder.setListenPortMessage(port: UInt32(listenPort))
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
                logger.info("Sent HaveNoParent(true) - requesting distributed network parent")

                // Tell server we accept child connections
                let acceptChildrenMessage = MessageBuilder.acceptChildren(acceptDistributedChildren)
                try await connection.send(acceptChildrenMessage)
                logger.info("Sent AcceptChildren(\(self.acceptDistributedChildren))")

                // Tell server our branch level (0 = not connected to distributed network yet)
                let branchLevelMessage = MessageBuilder.branchLevel(0)
                try await connection.send(branchLevelMessage)
                logger.info("Sent BranchLevel(0)")

                // Print diagnostic info
                logger.info("CONNECTION DIAGNOSTICS:")
                logger.info("  Listen port: \(self.listenPort)")
                logger.info("  Obfuscated port: \(self.obfuscatedPort)")
                if let extIP = self.externalIP {
                    logger.info("  External IP: \(extIP)")
                } else {
                    logger.info("  External IP: unknown (NAT mapping may have failed)")
                }

                isConnecting = false
                isConnected = true
                onConnectionStatusChanged?(.connected)
                logger.info("Login successful!")

                // Start keepalive ping timer
                startPingTimer()

                // Run NAT mapping in background (don't block connection)
                Task {
                    await self.setupNATInBackground()
                }
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
        ActivityLog.shared.logDisconnected()

        // Cancel any pending login wait
        if let continuation = loginContinuation {
            loginContinuation = nil
            continuation.resume(throwing: ServerConnection.ConnectionError.notConnected)
        }

        receiveTask?.cancel()
        receiveTask = nil

        pingTask?.cancel()
        pingTask = nil

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

    // MARK: - Keepalive

    /// Start periodic ping timer to keep connection alive
    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.pingInterval))
                    guard let self = self, self.isConnected, let connection = self.serverConnection else {
                        return
                    }
                    let pingMessage = MessageBuilder.pingMessage()
                    try await connection.send(pingMessage)
                    self.logger.debug("Sent keepalive ping")
                } catch is CancellationError {
                    return
                } catch {
                    self?.logger.warning("Keepalive ping failed: \(error.localizedDescription)")
                    // Continue trying - connection may recover
                }
            }
        }
        logger.info("Keepalive ping timer started (interval: \(Self.pingInterval)s)")
    }

    // MARK: - NAT Setup (Background)

    private func setupNATInBackground() async {
        // Check if UPnP/NAT-PMP is enabled in settings
        let enableNAT = UserDefaults.standard.object(forKey: "settings.enableUPnP") == nil
            ? true  // Default to enabled
            : UserDefaults.standard.bool(forKey: "settings.enableUPnP")

        if !enableNAT {
            logger.info("NAT: Port mapping disabled in settings")
            // Still try to discover external IP via STUN/web service (non-invasive)
            if let extIP = await natService.discoverExternalIP() {
                await MainActor.run {
                    self.externalIP = extIP
                }
                logger.info("NAT: External IP: \(extIP)")
            }
            return
        }

        logger.info("NAT: Starting background port mapping...")

        // Add delay to avoid triggering IDS with rapid network activity at startup
        try? await Task.sleep(for: .seconds(2))

        // Try to map the listen port
        do {
            let mappedPort = try await natService.mapPort(listenPort)
            logger.info("NAT: Mapped port \(self.listenPort) -> \(mappedPort)")
        } catch {
            logger.warning("NAT: Port mapping failed (will rely on server-mediated connections)")
        }

        // Small delay between mapping attempts to avoid IDS triggers
        try? await Task.sleep(for: .milliseconds(500))

        // Try to map obfuscated port
        if obfuscatedPort > 0 {
            do {
                let mappedObfuscated = try await natService.mapPort(obfuscatedPort)
                logger.info("NAT: Mapped obfuscated port \(self.obfuscatedPort) -> \(mappedObfuscated)")
            } catch {
                // Silent failure for obfuscated port
            }
        }

        // Discover external IP
        if let extIP = await natService.discoverExternalIP() {
            await MainActor.run {
                self.externalIP = extIP
            }
            logger.info("NAT: External IP: \(extIP)")
        }

        logger.info("NAT: Background setup complete")
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

    // SECURITY: Maximum search query length
    private static let maxSearchQueryLength = 500

    private func requireConnectedServerConnection() throws -> ServerConnection {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }
        return connection
    }

    func search(query: String, token: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // SECURITY: Truncate query if too long
        let sanitizedQuery = String(query.prefix(Self.maxSearchQueryLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedQuery.isEmpty else {
            throw NetworkError.invalidResponse
        }

        let message = MessageBuilder.fileSearchMessage(token: token, query: sanitizedQuery)
        try await connection.send(message)
        logger.info("Sent search request: query='\(sanitizedQuery)' token=\(token)")
    }

    func getRoomList() async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.getRoomListMessage()
        try await connection.send(message)
    }

    func joinRoom(_ name: String, isPrivate: Bool = false) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.joinRoomMessage(roomName: name, isPrivate: isPrivate)
        try await connection.send(message)
    }

    func leaveRoom(_ name: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.leaveRoomMessage(roomName: name)
        try await connection.send(message)
    }

    // SECURITY: Maximum chat message length
    private static let maxMessageLength = 2000
    // SECURITY: Maximum username/room name length
    private static let maxNameLength = 100

    func sendRoomMessage(_ room: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // SECURITY: Validate and sanitize input
        let sanitizedRoom = String(room.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedRoom.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.sayInChatRoomMessage(roomName: sanitizedRoom, message: sanitizedMessage)
        try await connection.send(data)
    }

    func sendPrivateMessage(to username: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // SECURITY: Validate and sanitize input
        let sanitizedUsername = String(username.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedUsername.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.privateMessageMessage(username: sanitizedUsername, message: sanitizedMessage)
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

        let message = MessageBuilder.setOnlineStatusMessage(status: status)
        try await connection.send(message)
    }

    func setSharedFilesCount(_ files: UInt32, directories: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.sharedFoldersFilesMessage(folders: directories, files: files)
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

    /// Acknowledge a private message to the server (code 23)
    func acknowledgePrivateMessage(messageId: UInt32) async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.acknowledgePrivateMessageMessage(messageId: messageId)
        do {
            try await connection.send(message)
            logger.info("Acknowledged private message \(messageId)")
        } catch {
            logger.error("Failed to acknowledge private message: \(error.localizedDescription)")
        }
    }

    /// Request server to tell peer to connect to us (indirect connection request)
    /// Server will forward this to the peer, who will then send PierceFirewall to us
    func sendConnectToPeer(token: UInt32, username: String, connectionType: String = "P") async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.connectToPeerMessage(token: token, username: username, connectionType: connectionType)
        do {
            try await connection.send(message)
            logger.info("Sent ConnectToPeer for \(username) token=\(token) type=\(connectionType)")
            logger.debug("Sent ConnectToPeer: token=\(token) username=\(username) type=\(connectionType)")
        } catch {
            logger.error("Failed to send ConnectToPeer: \(error.localizedDescription)")
        }
    }

    // MARK: - Peer Address Response Handling

    /// Internal handler for peer address responses - dispatches to pending requests AND all registered handlers
    func handlePeerAddressResponse(username: String, ip: String, port: Int) {
        logger.debug("handlePeerAddressResponse: \(username) @ \(ip):\(port)")

        // Check for pending internal request (browse/folder)
        if let pending = pendingPeerAddressRequests.removeValue(forKey: username) {
            logger.debug("Resuming pending getPeerAddress continuation (requestID: \(pending.requestID))")
            pending.continuation.resume(returning: (ip, port))
        }

        // Call all registered handlers (multi-listener pattern)
        if !peerAddressHandlers.isEmpty {
            logger.debug("Calling \(self.peerAddressHandlers.count) registered peer address handlers")
            for handler in peerAddressHandlers {
                handler(username, ip, port)
            }
        }

        // Also call legacy single callback for backward compatibility
        if onPeerAddress != nil {
            logger.debug("Forwarding to legacy onPeerAddress callback")
            onPeerAddress?(username, ip, port)
        }

        if peerAddressHandlers.isEmpty && onPeerAddress == nil {
            logger.warning("No peer address handlers registered!")
        }
    }

    /// Request peer address and wait for response (concurrent-safe)
    /// Can be called from multiple places concurrently - each request gets its own continuation
    func getPeerAddress(for username: String, timeout: Duration = .seconds(10)) async throws -> (ip: String, port: Int) {
        // Check if there's already a pending request for this user
        if pendingPeerAddressRequests[username] != nil {
            // Another request is in flight - wait a bit and try to get existing connection
            try await Task.sleep(for: .milliseconds(500))
            if let existingConnection = await peerConnectionPool.getConnectionForUser(username) {
                let info = existingConnection.peerInfo
                return (info.ip, info.port)
            }
        }

        // Generate unique request ID to prevent double-resume when same user is requested multiple times
        let requestID = UUID()

        return try await withCheckedThrowingContinuation { continuation in
            // Register pending request with unique ID
            pendingPeerAddressRequests[username] = (continuation: continuation, requestID: requestID)

            // Request the peer address
            Task {
                do {
                    try await self.getUserAddress(username)
                } catch {
                    // Remove and resume with error if request fails AND this is still our request
                    if let pending = self.pendingPeerAddressRequests[username],
                       pending.requestID == requestID {
                        self.pendingPeerAddressRequests.removeValue(forKey: username)
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Timeout
            Task {
                try? await Task.sleep(for: timeout)
                // Remove and resume with timeout if still pending AND this is still our request
                // This check prevents double-resume when a new request replaced our continuation
                if let pending = self.pendingPeerAddressRequests[username],
                   pending.requestID == requestID {
                    self.pendingPeerAddressRequests.removeValue(forKey: username)
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        }
    }

    // MARK: - Peer Connections

    // Pending browse requests waiting for indirect connections (keyed by TOKEN)
    // When peer connects via PierceFirewall, they send the same token we used in ConnectToPeer
    // (pendingBrowseStates is defined below in the browse section)

    /// Browse a user's shared files
    func browseUser(_ username: String) async throws -> [SharedFile] {
        logger.debug("Browse: START browseUser(\(username))")
        guard isConnected else {
            logger.error("Browse: ERROR - not connected")
            throw NetworkError.notConnected
        }

        var connection: PeerConnection
        var isIndirectConnection = false

        // Always create a fresh connection for browse
        do {
            let token = UInt32.random(in: 0...UInt32.max)
            logger.debug("Browse: Using token \(token) for \(username)")

            // CRITICAL: Register pending browse BEFORE sending ConnectToPeer to avoid race condition
            // PierceFirewall can arrive immediately after ConnectToPeer is sent!
            registerPendingBrowse(token: token, username: username, timeout: 30)

            // Step 1: Send ConnectToPeer to server - peer will try to connect to us via PierceFirewall
            await sendConnectToPeer(token: token, username: username, connectionType: "P")
            logger.debug("Browse: Sent ConnectToPeer to server")

            // Step 2: Get peer address for direct connection attempt
            logger.debug("Browse: Getting peer address for \(username)...")
            let (ip, port) = try await getPeerAddress(for: username)
            logger.debug("Browse: Got address \(ip):\(port)")

            // Step 3: Race direct connection + handshake (10s timeout) vs indirect (PierceFirewall)
            // Direct TCP connect blocks for ~60s on timeout, way too long. PierceFirewall
            // typically arrives in ~1-3s. Also, even when direct TCP connects, the peer may
            // not respond with PeerInit (they already connected to us via PierceFirewall).
            do {
                connection = try await withThrowingTaskGroup(of: PeerConnection.self) { group in
                    group.addTask {
                        let conn = try await self.peerConnectionPool.connect(
                            to: username, ip: ip, port: port, token: token
                        )
                        // Must also complete handshake - peer may not respond if they
                        // already connected to us via PierceFirewall
                        try await conn.waitForPeerHandshake(timeout: .seconds(8))
                        return conn
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        throw NetworkError.timeout
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                cancelPendingBrowse(token: token)
                logger.debug("Browse: Direct connection + handshake to \(username) successful!")
            } catch {
                // Direct timed out or failed - use indirect (PierceFirewall) connection
                logger.debug("Browse: Direct failed (\(error.localizedDescription)), waiting for indirect...")
                connection = try await waitForPendingBrowse(token: token)
                isIndirectConnection = true
                logger.debug("Browse: Got indirect connection from \(username)")
            }
        }

        if isIndirectConnection {
            // Resume receive loop - PierceFirewall stops it assuming file transfer mode,
            // but P connections need to continue receiving peer messages (SharesReply, etc.)
            await connection.resumeReceivingForPeerConnection()
            logger.debug("Browse: Resumed receive loop for indirect P connection")
        }

        // For indirect connections, PierceFirewall sets peerHandshakeReceived=true
        // so this returns immediately. For direct, handshake was already done in the race.
        try await connection.waitForPeerHandshake(timeout: .seconds(5))
        logger.debug("Browse: Handshake verified, setting up callback...")

        // Set up callback BEFORE requesting shares
        let sharesResumed = Mutex(false)
        let receivedFiles = Mutex<[SharedFile]>([])

        // Set up the callback first (outside the continuation to avoid race)
        await connection.setOnSharesReceived { [self] files in
            self.logger.debug("Browse: Callback received \(files.count) files from \(username)")
            receivedFiles.withLock { $0 = files }
            sharesResumed.withLock { $0 = true }
        }

        // Request shares
        logger.debug("Browse: Requesting shares from \(username)...")
        try await connection.requestShares()
        logger.debug("Browse: Shares request sent, waiting for response...")

        // Poll for response with timeout
        let startTime = Date()
        let timeoutSeconds: TimeInterval = 30

        while !sharesResumed.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(100))

            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                logger.warning("Browse: Timeout waiting for shares from \(username)")
                throw NetworkError.timeout
            }
        }

        let result = receivedFiles.withLock { $0 }
        logger.debug("Browse: Got \(result.count) files from \(username)")
        return result
    }

    // Pending browse state - tracks both waiting and received connections
    private struct PendingBrowseState {
        let username: String
        var continuation: CheckedContinuation<PeerConnection, Error>?
        var receivedConnection: PeerConnection?  // Set if PierceFirewall arrives before we start waiting
        var timeoutTask: Task<Void, Never>?
        var timedOut = false
    }
    private var pendingBrowseStates: [UInt32: PendingBrowseState] = [:]

    /// Register a pending browse BEFORE sending ConnectToPeer (to avoid race condition)
    func registerPendingBrowse(token: UInt32, username: String, timeout: TimeInterval) {
        var state = PendingBrowseState(username: username)

        // Set up timeout
        state.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self else { return }

            // If still pending without a connection, mark as timed out
            if var pending = self.pendingBrowseStates[token] {
                if pending.receivedConnection == nil {
                    logger.warning("Browse: Timeout waiting for PierceFirewall from \(pending.username) (token=\(token))")
                    pending.timedOut = true
                    self.pendingBrowseStates[token] = pending

                    // If there's a continuation waiting, resume it with error
                    if let continuation = pending.continuation {
                        pending.continuation = nil
                        self.pendingBrowseStates[token] = pending
                        continuation.resume(throwing: NetworkError.timeout)
                    }
                }
            }
        }

        pendingBrowseStates[token] = state
    }

    /// Wait for a previously registered pending browse to receive PierceFirewall
    func waitForPendingBrowse(token: UInt32) async throws -> PeerConnection {
        // Check if connection already arrived
        if let state = pendingBrowseStates[token] {
            if let connection = state.receivedConnection {
                logger.debug("Browse: PierceFirewall already received for token=\(token)")
                pendingBrowseStates.removeValue(forKey: token)
                return connection
            }
            if state.timedOut {
                pendingBrowseStates.removeValue(forKey: token)
                throw NetworkError.timeout
            }
        }

        // Wait for connection
        return try await withCheckedThrowingContinuation { continuation in
            if var state = pendingBrowseStates[token] {
                // Check again if connection arrived while we were setting up
                if let connection = state.receivedConnection {
                    pendingBrowseStates.removeValue(forKey: token)
                    continuation.resume(returning: connection)
                    return
                }
                if state.timedOut {
                    pendingBrowseStates.removeValue(forKey: token)
                    continuation.resume(throwing: NetworkError.timeout)
                    return
                }
                state.continuation = continuation
                pendingBrowseStates[token] = state
            } else {
                // Token was already removed (cancelled or error)
                continuation.resume(throwing: NetworkError.timeout)
            }
        }
    }

    /// Cancel a pending browse (used when direct connection succeeds or search delivery completes)
    func cancelPendingBrowse(token: UInt32) {
        if let state = pendingBrowseStates.removeValue(forKey: token) {
            state.timeoutTask?.cancel()
            // Don't resume continuation - caller will handle the success case
        }
    }

    /// Called when PierceFirewall is received - check if it matches a pending browse request
    /// Returns true if it was handled as a browse request
    func handlePierceFirewallForBrowse(token: UInt32, connection: PeerConnection) -> Bool {
        if var state = pendingBrowseStates[token] {
            logger.debug("Browse: PierceFirewall token=\(token) matched pending browse for \(state.username)")

            // Set the username on the connection (PierceFirewall doesn't include PeerInit with username)
            Task {
                await connection.setPeerUsername(state.username)
                logger.debug("Browse: Set username '\(state.username)' on indirect connection")
            }

            // Store the connection
            state.receivedConnection = connection
            state.timeoutTask?.cancel()

            // If there's a continuation waiting, resume it immediately
            if let continuation = state.continuation {
                pendingBrowseStates.removeValue(forKey: token)
                continuation.resume(returning: connection)
            } else {
                // No one waiting yet - store for later
                pendingBrowseStates[token] = state
            }
            return true
        }
        return false
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like
    func addThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I like: \(item)")
    }

    /// Remove something I like
    func removeThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I like: \(item)")
    }

    /// Add something I hate
    func addThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I hate: \(item)")
    }

    /// Remove something I hate
    func removeThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I hate: \(item)")
    }

    /// Get my recommendations
    func getRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations")
    }

    /// Get global (network-wide) recommendations - popular interests across all users
    func getGlobalRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getGlobalRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested global recommendations")
    }

    /// Get a user's interests
    func getUserInterests(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserInterests(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested interests for: \(username)")
    }

    /// Get similar users
    func getSimilarUsers() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getSimilarUsers()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users")
    }

    /// Get recommendations for an item
    func getItemRecommendations(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemRecommendations(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations for item: \(item)")
    }

    /// Get similar users for an item
    func getItemSimilarUsers(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemSimilarUsers(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users for item: \(item)")
    }

    // MARK: - User Watching (Buddy List)

    /// Watch a user (receive status updates)
    func watchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.watchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Watching user: \(username)")
    }

    /// Stop watching a user
    func unwatchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.unwatchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unwatched user: \(username)")
    }

    /// Ignore user (server code 11)
    func ignoreUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.ignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Ignored user: \(username)")
    }

    /// Unignore user (server code 12)
    func unignoreUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.unignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unignored user: \(username)")
    }

    /// Get a user's current status
    func getUserStatus(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStatusMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested status for: \(username)")
    }

    /// Check if a user is online before attempting to connect
    /// Returns the user's status (offline, away, online) with a timeout
    func checkUserOnlineStatus(_ username: String, timeout: TimeInterval = 5.0) async throws -> (status: UserStatus, privileged: Bool) {
        guard isConnected else { throw NetworkError.notConnected }

        // Check if we already have a pending request for this user
        if pendingStatusRequests[username] != nil {
            logger.warning("Already have pending status request for \(username)")
        }

        // Send the status request
        let message = MessageBuilder.getUserStatusMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Checking online status for: \(username)")

        // Wait for response with timeout
        return await withCheckedContinuation { continuation in
            pendingStatusRequests[username] = continuation

            // Set up timeout
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                // If still pending, assume offline (no response = user doesn't exist or server issue)
                if let pending = pendingStatusRequests.removeValue(forKey: username) {
                    logger.warning("Status check timeout for \(username), assuming offline")
                    pending.resume(returning: (status: .offline, privileged: false))
                }
            }
        }
    }

    /// Handle status response - resumes pending status checks
    func handleUserStatusResponse(username: String, status: UserStatus, privileged: Bool) {
        // Resume any pending status check for this user
        if let continuation = pendingStatusRequests.removeValue(forKey: username) {
            continuation.resume(returning: (status: status, privileged: privileged))
        }

        // Notify all registered status handlers
        for handler in userStatusHandlers {
            handler(username, status, privileged)
        }
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (speed, files, dirs)
    func getUserStats(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStats(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested stats for: \(username)")
    }

    /// Check our privilege time remaining
    func checkPrivileges() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.checkPrivileges()
        try await requireConnectedServerConnection().send(message)
        logger.info("Checking privileges")
    }

    /// Get a user's privilege status
    func getUserPrivileges(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserPrivileges(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested privileges for: \(username)")
    }

    // MARK: - Room Tickers

    /// Set a ticker message for a room
    func setRoomTicker(room: String, ticker: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.setRoomTicker(room: room, ticker: ticker)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ticker in \(room): \(ticker)")
    }

    // MARK: - Room Search & Wishlist

    /// Search within a specific room
    func searchRoom(_ room: String, query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.roomSearch(room: room, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Room search in \(room): \(query)")
    }

    /// Legacy room search request (server code 25)
    func searchRoomLegacy(_ room: String, query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.fileSearchRoomMessage(room: room, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Legacy room search in \(room): \(query)")
    }

    /// Add a wishlist search (runs periodically)
    func addWishlistSearch(query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.wishlistSearch(token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added wishlist search: \(query)")
    }

    // MARK: - Private Rooms

    /// Add a member to a private room
    func addPrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) to private room \(room)")
    }

    /// Remove a member from a private room
    func removePrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) from private room \(room)")
    }

    /// Leave a private room
    func leavePrivateRoom(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelMembership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Leaving private room \(room)")
    }

    /// Give up ownership of a private room
    func giveUpPrivateRoomOwnership(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelOwnership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Giving up ownership of \(room)")
    }

    /// Add an operator to a private room
    func addPrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) as operator in \(room)")
    }

    /// Remove an operator from a private room
    func removePrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) as operator from \(room)")
    }

    // MARK: - User Search

    /// Search a specific user's files
    func userSearch(username: String, token: UInt32, query: String) async throws {
        let message = MessageBuilder.userSearchMessage(username: username, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Upload Speed & Privileges

    /// Report upload speed to server
    func reportUploadSpeed(_ speed: UInt32) async throws {
        let message = MessageBuilder.sendUploadSpeedMessage(speed: speed)
        try await requireConnectedServerConnection().send(message)
    }

    /// Give privileges to another user
    func givePrivileges(to username: String, days: UInt32) async throws {
        let message = MessageBuilder.givePrivilegesMessage(username: username, days: days)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Room Invitations

    /// Enable or disable room invitations
    func enableRoomInvitations(_ enable: Bool) async throws {
        let message = MessageBuilder.enableRoomInvitationsMessage(enable: enable)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Bulk Messaging

    /// Send a message to multiple users at once
    func messageUsers(_ usernames: [String], message: String) async throws {
        let msg = MessageBuilder.messageUsersMessage(usernames: usernames, message: message)
        try await requireConnectedServerConnection().send(msg)
    }

    // MARK: - Global Room

    /// Join the global room
    func joinGlobalRoom() async throws {
        let message = MessageBuilder.joinGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    /// Leave the global room
    func leaveGlobalRoom() async throws {
        let message = MessageBuilder.leaveGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Distributed Network

    /// Update whether we accept distributed children
    func setAcceptDistributedChildren(_ accept: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        acceptDistributedChildren = accept
        let message = MessageBuilder.acceptChildren(accept)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set AcceptChildren(\(accept))")
    }

    /// Update our branch level
    func setDistributedBranchLevel(_ level: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchLevel = level
        let message = MessageBuilder.branchLevel(level)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchLevel(\(level))")
    }

    /// Update our branch root
    func setDistributedBranchRoot(_ root: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchRoot = root
        let message = MessageBuilder.branchRoot(root)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchRoot(\(root))")
    }

    /// Update our child depth
    func setDistributedChildDepth(_ depth: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.childDepth(depth)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ChildDepth(\(depth))")
    }

    /// Reset distributed network state (called when server sends code 130)
    func resetDistributedNetwork() async {
        guard isConnected else { return }

        logger.info("Resetting distributed network state")

        // Disconnect all children
        for child in distributedChildren {
            await child.disconnect()
        }
        distributedChildren.removeAll()

        // Reset branch state
        distributedBranchLevel = 0
        distributedBranchRoot = ""

        // Tell server we have no parent and need one
        do {
            let haveNoParentMessage = MessageBuilder.haveNoParent(true)
            try await requireConnectedServerConnection().send(haveNoParentMessage)

            let branchLevelMessage = MessageBuilder.branchLevel(0)
            try await requireConnectedServerConnection().send(branchLevelMessage)

            let acceptChildrenMessage = MessageBuilder.acceptChildren(acceptDistributedChildren)
            try await requireConnectedServerConnection().send(acceptChildrenMessage)

            logger.info("Distributed network reset complete, awaiting new parent assignment")
        } catch {
            logger.error("Failed to send distributed reset messages: \(error.localizedDescription)")
        }
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
        logger.info("Handling SharesRequest from \(username)")

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

        logger.info("Sending \(directories.count) directories with \(self.shareManager.totalFiles) total files to \(username)")

        do {
            try await connection.sendShares(files: directories)
            logger.info("Sent shares to \(username): \(directories.count) directories")
        } catch {
            logger.error("Failed to send shares to \(username): \(error.localizedDescription)")
            logger.error("Failed to send shares: \(error)")
        }
    }

    // MARK: - User Info Request Handling

    /// Handle incoming user info request - respond with our profile info
    private func handleUserInfoRequest(username: String, connection: PeerConnection) async {
        logger.info("UserInfoRequest from \(username)")

        let totalUploads = UInt32(shareManager.totalFiles)
        let queueSize = UInt32(0)
        let hasFreeSlots = true

        // Get profile data from SocialState (or fall back to default)
        let profileData = profileDataProvider?() ?? (description: "SeeleSeek - Soulseek client for macOS", picture: nil)

        do {
            try await connection.sendUserInfo(
                description: profileData.description,
                picture: profileData.picture,
                totalUploads: totalUploads,
                queueSize: queueSize,
                hasFreeSlots: hasFreeSlots
            )
            logger.info("Sent user info to \(username)")
        } catch {
            logger.error("Failed to send user info to \(username): \(error.localizedDescription)")
        }
    }

    /// Request folder contents from a peer
    func requestFolderContents(from username: String, folder: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }

        let token = UInt32.random(in: 0...UInt32.max)

        // Check if we have an existing connection to this user
        if let existingConnection = await peerConnectionPool.getConnectionForUser(username) {
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
        if success {
            if let continuation = loginContinuation {
                loginContinuation = nil
                continuation.resume(returning: true)
            }
        } else {
            connectionError = message
            if let continuation = loginContinuation {
                loginContinuation = nil
                continuation.resume(throwing: ServerConnection.ConnectionError.loginFailed(message ?? "Unknown error"))
            }
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
