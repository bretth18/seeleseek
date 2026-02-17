import Foundation
import Network
import os
import Compression
import Synchronization

/// Manages a single peer-to-peer connection
actor PeerConnection {
    private nonisolated let logger = Logger(subsystem: "com.seeleseek", category: "PeerConnection")

    // MARK: - Types

    enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case handshaking
        case connected
        case failed(Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.connecting, .connecting): return true
            case (.handshaking, .handshaking): return true
            case (.connected, .connected): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }

    enum ConnectionType: String, Sendable {
        case peer = "P"      // General peer messages
        case file = "F"      // File transfer
        case distributed = "D" // Distributed network
    }

    struct PeerInfo: Sendable {
        let username: String
        let ip: String
        let port: Int
        var uploadSpeed: UInt32 = 0
        var downloadSpeed: UInt32 = 0
        var freeUploadSlots: Bool = true
        var queueLength: UInt32 = 0
        var sharedFiles: UInt32 = 0
        var sharedFolders: UInt32 = 0
    }

    // MARK: - Properties

    // peerInfo is protected by Mutex for thread-safe access from outside the actor
    // (e.g., PeerConnectionPool, NetworkClient, DownloadManager read it without await)
    private nonisolated let _peerInfo: Mutex<PeerInfo>
    nonisolated var peerInfo: PeerInfo {
        _peerInfo.withLock { $0 }
    }
    nonisolated let connectionType: ConnectionType
    nonisolated let isIncoming: Bool
    nonisolated let token: UInt32

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private(set) var state: State = .disconnected

    /// Check if the connection is currently connected and usable
    var isConnected: Bool {
        guard connection != nil else { return false }
        switch state {
        case .connected, .handshaking:
            return true
        default:
            return false
        }
    }

    // For incoming connections, we delay starting the receive loop until callbacks are configured
    private var autoStartReceiving = true

    // Callbacks
    private var _onStateChanged: ((State) async -> Void)?
    private var _onMessage: ((UInt32, Data) async -> Void)?
    private var _onSharesReceived: (([SharedFile]) async -> Void)?
    private var _onSearchReply: ((UInt32, [SearchResult]) async -> Void)?  // (token, results)
    private var _onTransferRequest: ((TransferRequest) async -> Void)?
    // Per-token TransferRequest handlers for handling multiple concurrent downloads on same connection
    private var _tokenTransferRequestHandlers: [UInt32: (TransferRequest) async -> Void] = [:]
    private var _onUsernameDiscovered: ((String, UInt32) async -> Void)?  // (username, token)
    private var _onFileTransferConnection: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, self)
    private var _onPierceFirewall: ((UInt32) async -> Void)?  // token from indirect connection
    private var _onUploadDenied: ((String, String) async -> Void)?  // (filename, reason)
    private var _onUploadFailed: ((String) async -> Void)?  // filename
    private var _onQueueUpload: ((String, String) async -> Void)?  // (username, filename) - peer wants to download from us
    private var _onTransferResponse: ((UInt32, Bool, UInt64?) async -> Void)?  // (token, allowed, filesize?)
    private var _onFolderContentsRequest: ((UInt32, String) async -> Void)?  // (token, folder)
    private var _onFolderContentsResponse: ((UInt32, String, [SharedFile]) async -> Void)?  // (token, folder, files)
    private var _onPlaceInQueueRequest: ((String, String) async -> Void)?  // (username, filename) - peer asks for queue position
    private var _onPlaceInQueueReply: ((String, UInt32) async -> Void)?  // (filename, position)
    private var _onSharesRequest: ((PeerConnection) async -> Void)?  // Peer wants to browse our shares
    private var _onUserInfoRequest: ((PeerConnection) async -> Void)?  // Peer wants our user info

    // SeeleSeek extension state
    private(set) var isSeeleSeekPeer = false
    private var _onArtworkRequest: ((UInt32, String, PeerConnection) async -> Void)?  // (token, filePath, connection)
    private var _onArtworkReply: ((UInt32, Data) async -> Void)?  // (token, imageData)

    // Callback setters for external access
    func setOnStateChanged(_ handler: @escaping (State) async -> Void) {
        _onStateChanged = handler
    }

    func setOnMessage(_ handler: @escaping (UInt32, Data) async -> Void) {
        _onMessage = handler
    }

    func setOnSharesReceived(_ handler: @escaping ([SharedFile]) async -> Void) {
        _onSharesReceived = handler
    }

    func setOnSearchReply(_ handler: @escaping (UInt32, [SearchResult]) async -> Void) {
        _onSearchReply = handler
    }

    func setOnTransferRequest(_ handler: @escaping (TransferRequest) async -> Void) {
        _onTransferRequest = handler
    }

    /// Register a handler for a specific token's TransferRequest
    /// This allows multiple concurrent downloads on the same connection without callback conflicts
    func setOnTransferRequestForToken(_ token: UInt32, handler: @escaping (TransferRequest) async -> Void) {
        _tokenTransferRequestHandlers[token] = handler
        logger.debug("Registered TransferRequest handler for token \(token) (total handlers: \(self._tokenTransferRequestHandlers.count))")
    }

    /// Remove a per-token TransferRequest handler
    func removeTransferRequestHandlerForToken(_ token: UInt32) {
        _tokenTransferRequestHandlers.removeValue(forKey: token)
        logger.debug("Removed TransferRequest handler for token \(token) (remaining: \(self._tokenTransferRequestHandlers.count))")
    }

    func setOnUsernameDiscovered(_ handler: @escaping (String, UInt32) async -> Void) {
        _onUsernameDiscovered = handler
    }

    func setOnFileTransferConnection(_ handler: @escaping (String, UInt32, PeerConnection) async -> Void) {
        _onFileTransferConnection = handler
    }

    func setOnPierceFirewall(_ handler: @escaping (UInt32) async -> Void) {
        _onPierceFirewall = handler
    }

    func setOnUploadDenied(_ handler: @escaping (String, String) async -> Void) {
        _onUploadDenied = handler
    }

    func setOnUploadFailed(_ handler: @escaping (String) async -> Void) {
        _onUploadFailed = handler
    }

    func setOnQueueUpload(_ handler: @escaping (String, String) async -> Void) {
        _onQueueUpload = handler
    }

    func setOnTransferResponse(_ handler: @escaping (UInt32, Bool, UInt64?) async -> Void) {
        _onTransferResponse = handler
    }

    func setOnFolderContentsRequest(_ handler: @escaping (UInt32, String) async -> Void) {
        _onFolderContentsRequest = handler
    }

    func setOnFolderContentsResponse(_ handler: @escaping (UInt32, String, [SharedFile]) async -> Void) {
        _onFolderContentsResponse = handler
    }

    func setOnPlaceInQueueRequest(_ handler: @escaping (String, String) async -> Void) {
        _onPlaceInQueueRequest = handler
    }

    func setOnPlaceInQueueReply(_ handler: @escaping (String, UInt32) async -> Void) {
        _onPlaceInQueueReply = handler
    }

    func setOnSharesRequest(_ handler: @escaping (PeerConnection) async -> Void) {
        _onSharesRequest = handler
    }

    func setOnUserInfoRequest(_ handler: @escaping (PeerConnection) async -> Void) {
        _onUserInfoRequest = handler
    }

    func setOnArtworkRequest(_ handler: @escaping (UInt32, String, PeerConnection) async -> Void) {
        _onArtworkRequest = handler
    }

    func setOnArtworkReply(_ handler: @escaping (UInt32, Data) async -> Void) {
        _onArtworkReply = handler
    }

    /// Get the discovered peer username (from PeerInit message)
    func getPeerUsername() -> String {
        return peerUsername
    }

    /// Set the peer username (used when matching PierceFirewall to pending uploads)
    func setPeerUsername(_ username: String) {
        peerUsername = username
        // Also update peerInfo for consistency
        _peerInfo.withLock { info in
            info = PeerInfo(
                username: username,
                ip: info.ip,
                port: info.port,
                uploadSpeed: info.uploadSpeed,
                downloadSpeed: info.downloadSpeed,
                freeUploadSlots: info.freeUploadSlots,
                queueLength: info.queueLength,
                sharedFiles: info.sharedFiles,
                sharedFolders: info.sharedFolders
            )
        }
        logger.debug("[\(username)] Updated peer username")
    }

    /// Get the connection state (for debug logging from other actors)
    func getState() -> State {
        return state
    }

    // Statistics
    private(set) var bytesReceived: UInt64 = 0
    private(set) var bytesSent: UInt64 = 0
    private(set) var messagesReceived: UInt32 = 0
    private(set) var messagesSent: UInt32 = 0
    private(set) var connectedAt: Date?
    private(set) var lastActivityAt: Date?

    // MARK: - Initialization

    /// Local port to bind outgoing connections to (for NAT traversal)
    private var localPort: UInt16 = 0

    init(peerInfo: PeerInfo, type: ConnectionType = .peer, token: UInt32 = 0, isIncoming: Bool = false, localPort: UInt16 = 0) {
        self._peerInfo = Mutex(peerInfo)
        self.connectionType = type
        self.token = token
        self.isIncoming = isIncoming
        self.localPort = localPort
    }

    init(connection: NWConnection, isIncoming: Bool = true, autoStartReceiving: Bool = true) {
        // For incoming connections, extract IP/port from the connection endpoint
        // This fixes the issue where peerInfo.ip and peerInfo.port were empty for incoming connections
        var extractedIP = ""
        var extractedPort = 0

        if let remoteEndpoint = connection.currentPath?.remoteEndpoint {
            switch remoteEndpoint {
            case .hostPort(let host, let port):
                // Extract IP string from host
                switch host {
                case .ipv4(let ipv4):
                    extractedIP = "\(ipv4)"
                case .ipv6(let ipv6):
                    extractedIP = "\(ipv6)"
                case .name(let hostname, _):
                    extractedIP = hostname
                @unknown default:
                    extractedIP = "\(host)"
                }
                extractedPort = Int(port.rawValue)
                logger.debug("Incoming connection: extracted IP=\(extractedIP) port=\(extractedPort)")
            default:
                logger.debug("Incoming connection: could not extract IP/port from endpoint: \(String(describing: remoteEndpoint))")
            }
        } else {
            // Path not available yet, try to extract from endpoint directly
            // This can happen before the connection is started
            logger.debug("Incoming connection: currentPath not available, IP/port unknown until connection starts")
        }

        self._peerInfo = Mutex(PeerInfo(username: "", ip: extractedIP, port: extractedPort))
        self.connectionType = .peer
        self.token = 0
        self.isIncoming = isIncoming
        self.connection = connection
        self.autoStartReceiving = autoStartReceiving
    }

    // MARK: - Connection Management

    // Track if connect continuation has been resumed to prevent double-resume
    private var connectContinuationResumed = false

    func connect() async throws {
        guard case .disconnected = state else { return }

        updateState(.connecting)
        connectContinuationResumed = false

        // Validate port range (must be valid UInt16 and non-zero)
        guard peerInfo.port > 0, peerInfo.port <= Int(UInt16.max),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(peerInfo.port)) else {
            logger.error("Invalid port: \(self.peerInfo.port)")
            throw PeerError.invalidPort
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(peerInfo.ip),
            port: nwPort
        )

        // Use simple TCP parameters - minimal configuration for maximum compatibility
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
        }

        let conn = NWConnection(to: endpoint, using: params)
        logger.debug("Creating TCP connection to \(self.peerInfo.ip):\(self.peerInfo.port)")
        connection = conn

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                conn.stateUpdateHandler = { [weak self] newState in
                    guard let self else { return }
                    Task {
                        await self.handleConnectionState(newState, continuation: continuation)
                    }
                }

                conn.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            // Cancel the NWConnection when the task is cancelled (e.g., due to timeout)
            logger.debug("Task cancelled, stopping NWConnection to \(self.peerInfo.ip):\(self.peerInfo.port)...")
            conn.cancel()
        }
    }

    func accept() async throws {
        guard let connection, isIncoming else { return }

        updateState(.connecting)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task {
                    // When connection becomes ready, extract remote endpoint if not already done
                    if case .ready = newState {
                        await self.extractRemoteEndpointIfNeeded()
                    }
                    await self.handleConnectionState(newState, continuation: continuation)
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Extract remote endpoint from connection if peerInfo IP is empty
    /// Called when connection becomes ready to ensure we have the peer's IP/port
    private func extractRemoteEndpointIfNeeded() {
        guard peerInfo.ip.isEmpty, let connection else { return }

        if let remoteEndpoint = connection.currentPath?.remoteEndpoint {
            switch remoteEndpoint {
            case .hostPort(let host, let port):
                var extractedIP = ""
                switch host {
                case .ipv4(let ipv4):
                    extractedIP = "\(ipv4)"
                case .ipv6(let ipv6):
                    extractedIP = "\(ipv6)"
                case .name(let hostname, _):
                    extractedIP = hostname
                @unknown default:
                    extractedIP = "\(host)"
                }
                let extractedPort = Int(port.rawValue)
                logger.debug("Connection ready: extracted IP=\(extractedIP) port=\(extractedPort)")

                // Update peerInfo with extracted IP/port
                _peerInfo.withLock { info in
                    info = PeerInfo(
                        username: info.username,
                        ip: extractedIP,
                        port: extractedPort,
                        uploadSpeed: info.uploadSpeed,
                        downloadSpeed: info.downloadSpeed,
                        freeUploadSlots: info.freeUploadSlots,
                        queueLength: info.queueLength,
                        sharedFiles: info.sharedFiles,
                        sharedFolders: info.sharedFolders
                    )
                }
                logger.debug("Updated peerInfo with IP=\(extractedIP) port=\(extractedPort)")
            default:
                logger.warning("Could not extract IP/port from endpoint type: \(String(describing: remoteEndpoint))")
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        clearCallbacks()
        updateState(.disconnected)
    }

    /// Clear all callbacks to prevent memory leaks from closures holding strong references
    private func clearCallbacks() {
        _onStateChanged = nil
        _onMessage = nil
        _onSharesReceived = nil
        _onSearchReply = nil
        _onTransferRequest = nil
        _tokenTransferRequestHandlers.removeAll()
        _onUsernameDiscovered = nil
        _onFileTransferConnection = nil
        _onPierceFirewall = nil
        _onUploadDenied = nil
        _onUploadFailed = nil
        _onQueueUpload = nil
        _onTransferResponse = nil
        _onFolderContentsRequest = nil
        _onFolderContentsResponse = nil
        _onPlaceInQueueRequest = nil
        _onPlaceInQueueReply = nil
        _onSharesRequest = nil
        _onUserInfoRequest = nil
    }

    /// Start the receive loop - call this after callbacks are configured for incoming connections
    func beginReceiving() {
        guard connection != nil, !autoStartReceiving else { return }
        logger.info("Beginning receive loop (callbacks configured)")
        startReceiving()
    }

    // MARK: - Handshake

    /// Send PeerInit message to identify ourselves
    /// For direct P connections, token should be 0 per protocol
    /// For indirect connections, use the token from ConnectToPeer
    func sendPeerInit(username: String, useZeroToken: Bool = true) async throws {
        updateState(.handshaking)

        // Per protocol: direct P connections use token=0
        // Only indirect connections (responding to ConnectToPeer) use non-zero token
        let peerInitToken: UInt32 = useZeroToken ? 0 : token

        let message = MessageBuilder.peerInitMessage(
            username: username,
            connectionType: connectionType.rawValue,
            token: peerInitToken
        )

        logger.debug("PeerInit: username='\(username)' type='\(self.connectionType.rawValue)' token=\(peerInitToken)")
        try await send(message)

        // Mark handshake as complete from our side after sending PeerInit
        // We can now receive peer messages (code >= 4) without waiting for peer's response
        handshakeComplete = true
        logger.debug("PeerInit sent, handshake marked complete")

        // Send SeeleSeek handshake so the peer knows we support extensions
        try? await send(MessageBuilder.seeleseekHandshakeMessage())
    }

    func sendPierceFirewall() async throws {
        let message = MessageBuilder.pierceFirewallMessage(token: token)
        logger.debug("Sending PierceFirewall to \(self.peerInfo.username) with token \(self.token) (\(message.count) bytes)")
        let pfHex = message.map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.debug("PierceFirewall data: \(pfHex)")
        try await send(message)
        // Mark handshake as complete from our side - peer will send peer messages (not init messages) now
        handshakeComplete = true
        logger.debug("PierceFirewall sent successfully to \(self.peerInfo.username), handshake complete")
    }

    // MARK: - Peer Messages

    func requestShares() async throws {
        let message = MessageBuilder.sharesRequestMessage()
        logger.debug("[\(self.peerInfo.username)] Sending GetShareFileList (code 4)")
        try await send(message)
        logger.debug("[\(self.peerInfo.username)] GetShareFileList sent successfully")
        logger.info("Requested shares from \(self.peerInfo.username)")
    }

    /// Send our shared files to a peer (response to SharesRequest)
    func sendShares(files: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])]) async throws {
        let message = MessageBuilder.sharesReplyMessage(files: files)
        logger.debug("[\(self.peerInfo.username)] Sending SharesReply with \(files.count) directories")
        try await send(message)
        logger.info("Sent shares to \(self.peerInfo.username): \(files.count) directories")
    }

    func requestUserInfo() async throws {
        let message = MessageBuilder.userInfoRequestMessage()
        try await send(message)
    }

    /// Send our user info in response to UserInfoRequest
    func sendUserInfo(
        description: String,
        picture: Data? = nil,
        totalUploads: UInt32,
        queueSize: UInt32,
        hasFreeSlots: Bool
    ) async throws {
        let message = MessageBuilder.userInfoResponseMessage(
            description: description,
            picture: picture,
            totalUploads: totalUploads,
            queueSize: queueSize,
            hasFreeSlots: hasFreeSlots
        )
        logger.debug("[\(self.peerInfo.username)] Sending UserInfoResponse: desc='\(description)' uploads=\(totalUploads) queue=\(queueSize) freeSlots=\(hasFreeSlots)")
        try await send(message)
        logger.info("Sent user info to \(self.peerInfo.username)")
    }

    func sendSearchReply(username: String, token: UInt32, results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]) async throws {
        let message = MessageBuilder.searchReplyMessage(
            username: username,
            token: token,
            results: results
        )
        try await send(message)
    }

    func queueDownload(filename: String) async throws {
        let message = MessageBuilder.queueDownloadMessage(filename: filename)
        try await send(message)
        logger.info("Queued download: \(filename)")
    }

    func sendTransferRequest(direction: FileTransferDirection, token: UInt32, filename: String, size: UInt64? = nil) async throws {
        let message = MessageBuilder.transferRequestMessage(
            direction: direction,
            token: token,
            filename: filename,
            fileSize: size
        )
        try await send(message)
    }

    func sendTransferReply(token: UInt32, allowed: Bool, fileSize: UInt64? = nil, reason: String? = nil) async throws {
        let message = MessageBuilder.transferReplyMessage(token: token, allowed: allowed, fileSize: fileSize, reason: reason)
        try await send(message)
        logger.info("Sent transfer reply: token=\(token) allowed=\(allowed)")
    }

    func sendPlaceInQueue(filename: String, place: UInt32) async throws {
        let message = MessageBuilder.placeInQueueResponseMessage(filename: filename, place: place)
        try await send(message)
        logger.info("Sent place in queue: \(filename) position=\(place)")
    }

    func sendPlaceInQueueRequest(filename: String) async throws {
        let message = MessageBuilder.placeInQueueRequestMessage(filename: filename)
        try await send(message)
        logger.debug("Sent PlaceInQueueRequest: \(filename)")
    }

    func sendUploadDenied(filename: String, reason: String) async throws {
        let message = MessageBuilder.uploadDeniedMessage(filename: filename, reason: reason)
        try await send(message)
        logger.info("Sent upload denied: \(filename) - \(reason)")
    }

    func sendUploadFailed(filename: String) async throws {
        let message = MessageBuilder.uploadFailedMessage(filename: filename)
        try await send(message)
        logger.info("Sent upload failed: \(filename)")
    }

    func requestFolderContents(token: UInt32, folder: String) async throws {
        let message = MessageBuilder.folderContentsRequestMessage(token: token, folder: folder)
        try await send(message)
        logger.info("Requested folder contents: \(folder)")
    }

    func sendFolderContents(token: UInt32, folder: String, files: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]) async throws {
        let message = MessageBuilder.folderContentsResponseMessage(token: token, folder: folder, files: files)
        try await send(message)
        logger.info("Sent folder contents: \(folder) (\(files.count) files)")
    }

    // MARK: - Data Transfer

    func send(_ data: Data) async throws {
        guard let connection else {
            logger.error("[\(self.peerInfo.username)] send() - no connection!")
            throw PeerError.notConnected
        }
        // Allow sending in connected or handshaking state
        switch state {
        case .connected, .handshaking:
            break
        default:
            logger.error("[\(self.peerInfo.username)] send() - wrong state: \(String(describing: self.state))")
            throw PeerError.notConnected
        }

        logger.debug("[\(self.peerInfo.username)] Sending \(data.count) bytes")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.error("[\(self?.peerInfo.username ?? "??")] send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self?.logger.debug("[\(self?.peerInfo.username ?? "??")] send succeeded")
                    Task {
                        await self?.recordSent(data.count)
                    }
                    continuation.resume()
                }
            })
        }
    }

    func receive(exactLength: Int) async throws -> Data {
        guard let connection else {
            throw PeerError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: exactLength, maximumLength: exactLength) { [weak self] data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    Task {
                        await self?.recordReceived(data.count)
                    }
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PeerError.connectionClosed)
                }
            }
        }
    }

    /// Send raw data without length prefix (used for file transfer handshake)
    func sendRaw(_ data: Data) async throws {
        guard let connection else {
            throw PeerError.notConnected
        }

        logger.debug("[\(self.peerInfo.username)] Sending RAW \(data.count) bytes")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.error("[\(self?.peerInfo.username ?? "??")] sendRaw failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self?.logger.debug("[\(self?.peerInfo.username ?? "??")] sendRaw succeeded")
                    Task {
                        await self?.recordSent(data.count)
                    }
                    continuation.resume()
                }
            })
        }
    }

    /// Receive exactly `count` raw bytes with optional timeout (used for file transfer handshake)
    func receiveRawBytes(count: Int, timeout: TimeInterval = 10) async throws -> Data {
        guard let connection else {
            throw PeerError.notConnected
        }

        // First, check if we already have enough data in the file transfer buffer
        // (this can happen when data arrives before we stop the receive loop)
        if fileTransferBuffer.count >= count {
            let data = fileTransferBuffer.prefix(count)
            fileTransferBuffer.removeFirst(count)
            logger.debug("[\(self.peerInfo.username)] Got \(count) raw bytes from file transfer buffer")
            return Data(data)
        }

        // If we have some buffered data but not enough, we need to receive more
        let neededFromNetwork = count - fileTransferBuffer.count
        logger.debug("[\(self.peerInfo.username)] Waiting for \(neededFromNetwork) raw bytes from network (have \(self.fileTransferBuffer.count) buffered, need \(count) total, timeout: \(timeout)s)...")

        // Capture and clear buffer before entering non-isolated closure
        let bufferedData = fileTransferBuffer
        fileTransferBuffer.removeAll()

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: neededFromNetwork, maximumLength: neededFromNetwork) { [weak self] data, _, _, error in
                        if let error {
                            self?.logger.debug("[\(self?.peerInfo.username ?? "??")] receiveRawBytes error: \(error)")
                            continuation.resume(throwing: error)
                        } else if let data, data.count >= neededFromNetwork {
                            self?.logger.debug("[\(self?.peerInfo.username ?? "??")] Received \(data.count) raw bytes from network")
                            Task {
                                await self?.recordReceived(data.count)
                            }
                            // Combine buffered data with newly received data
                            if !bufferedData.isEmpty {
                                var combined = bufferedData
                                combined.append(data)
                                continuation.resume(returning: Data(combined.prefix(count)))
                            } else {
                                continuation.resume(returning: data)
                            }
                        } else {
                            self?.logger.debug("[\(self?.peerInfo.username ?? "??")] Received incomplete data: \(data?.count ?? 0)/\(neededFromNetwork)")
                            continuation.resume(throwing: PeerError.connectionClosed)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw PeerError.timeout
            }

            guard let result = try await group.next() else {
                throw PeerError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    /// Result type for file chunk reception - distinguishes between data, completion, and errors
    enum FileChunkResult: Sendable {
        case data(Data)
        case dataWithCompletion(Data)  // Data received AND connection is now complete
        case connectionComplete
    }

    /// Receive file data in chunks for file transfers
    /// Uses 1MB buffer by default for better throughput
    func receiveFileChunk(maxLength: Int = 1024 * 1024) async throws -> FileChunkResult {
        guard let connection else {
            throw PeerError.notConnected
        }

        // First, check if we have buffered data from when the receive loop was stopped
        if !fileTransferBuffer.isEmpty {
            let chunk: Data
            if fileTransferBuffer.count <= maxLength {
                chunk = fileTransferBuffer
                fileTransferBuffer.removeAll()
            } else {
                chunk = fileTransferBuffer.prefix(maxLength)
                fileTransferBuffer.removeFirst(maxLength)
            }
            logger.debug("Using \(chunk.count) bytes from file transfer buffer")
            return .data(chunk)
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Use minimumIncompleteLength: 0 to return whatever is available
            // This helps drain the buffer when connection is closing
            connection.receive(minimumIncompleteLength: 0, maximumLength: maxLength) { [weak self] data, _, isComplete, error in
                if let error {
                    // Real error - but still try to return any data we got
                    if let data, !data.isEmpty {
                        Task { await self?.recordReceived(data.count) }
                        continuation.resume(returning: .dataWithCompletion(data))
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else if let data, !data.isEmpty {
                    Task {
                        await self?.recordReceived(data.count)
                    }
                    // If we have data AND connection is complete, signal both
                    if isComplete {
                        continuation.resume(returning: .dataWithCompletion(data))
                    } else {
                        continuation.resume(returning: .data(data))
                    }
                } else if isComplete {
                    // Connection cleanly closed with no more data
                    continuation.resume(returning: .connectionComplete)
                } else {
                    // No data and connection still open - this can happen with minimumIncompleteLength: 0
                    // Return empty data and let caller decide whether to continue
                    continuation.resume(returning: .data(Data()))
                }
            }
        }
    }

    // Flag to stop the receive loop for raw file transfers
    private var shouldStopReceiving = false

    // Buffer for file transfer data received after stopping message parsing
    private var fileTransferBuffer = Data()

    /// Stop the normal receive loop so we can do raw file transfers
    func stopReceiving() {
        shouldStopReceiving = true
        // Clear the message receive buffer - any pending data will go to file transfer buffer
        receiveBuffer.removeAll()
        logger.info("Stopping receive loop for file transfer")
        logger.debug("[\(self.peerInfo.username)] Stopped receive loop, cleared message buffer")
    }

    /// Get any data that was received after stopReceiving() was called
    func getFileTransferBuffer() -> Data {
        let data = fileTransferBuffer
        fileTransferBuffer.removeAll()
        return data
    }

    /// Prepend data back to the file transfer buffer (for partial reads)
    func prependToFileTransferBuffer(_ data: Data) {
        fileTransferBuffer = data + fileTransferBuffer
    }

    /// Drain any available data from the connection without blocking
    /// Used after connection signals complete to get remaining buffered data
    func drainAvailableData(maxLength: Int = 65536, timeout: TimeInterval = 0.5) async -> Data {
        guard let connection else {
            return Data()
        }

        do {
            return try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        // Use minimumIncompleteLength: 0 to return immediately with whatever is available
                        connection.receive(minimumIncompleteLength: 0, maximumLength: maxLength) { [weak self] data, _, isComplete, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else if let data, !data.isEmpty {
                                Task { await self?.recordReceived(data.count) }
                                continuation.resume(returning: data)
                            } else {
                                // No data available
                                continuation.resume(returning: Data())
                            }
                        }
                    }
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    return Data() // Return empty on timeout
                }

                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                return Data()
            }
        } catch {
            return Data()
        }
    }

    // MARK: - Private Methods

    private func handleConnectionState(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>?) {
        switch state {
        case .ready:
            logger.info("Peer connected: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            logger.info("Connected to peer \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            connectedAt = Date()
            updateState(.connected)
            // Only auto-start receiving if flag is set (for outgoing connections)
            // For incoming connections, we delay until callbacks are configured
            if autoStartReceiving {
                startReceiving()
            }
            if !connectContinuationResumed {
                connectContinuationResumed = true
                continuation?.resume()
            }

        case .failed(let error):
            logger.error("Peer connection failed: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            logger.error("Error details: \(error)")
            logger.error("Peer connection failed: \(error.localizedDescription)")
            updateState(.failed(error))
            // Cancel the connection to free resources
            connection?.cancel()
            connection = nil
            if !connectContinuationResumed {
                connectContinuationResumed = true
                continuation?.resume(throwing: error)
            }

        case .waiting(let error):
            logger.debug("Peer connection waiting: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            logger.debug("Waiting error: \(error)")
            // Check if this is a definitive failure (not just a transient condition)
            // POSIX errors: 12 (ENOMEM), 51 (ENETUNREACH), 57 (ENOTCONN), 60 (ETIMEDOUT), 61 (ECONNREFUSED), 65 (EHOSTUNREACH)
            if case .posix(let posixError) = error {
                let code = posixError.rawValue
                if code == 12 || code == 51 || code == 57 || code == 60 || code == 61 || code == 65 {
                    // These are definitive failures, not transient
                    logger.error("Peer connection definitive failure: \(self.peerInfo.username) - POSIX \(code)")
                    updateState(.failed(error))
                    // Cancel connection to free resources
                    connection?.cancel()
                    connection = nil
                    if !connectContinuationResumed {
                        connectContinuationResumed = true
                        continuation?.resume(throwing: error)
                    }
                }
            }

        case .preparing:
            logger.debug("Peer connection preparing: \(self.peerInfo.username) -> \(self.peerInfo.ip):\(self.peerInfo.port)")

        case .cancelled:
            logger.info("Peer connection cancelled: \(self.peerInfo.username)")
            updateState(.disconnected)
            // Resume with cancellation error if not already resumed (e.g., timeout cancelled the connection)
            if !connectContinuationResumed {
                connectContinuationResumed = true
                continuation?.resume(throwing: CancellationError())
            }

        case .setup:
            break

        @unknown default:
            break
        }
    }

    /// Resume receiving for P connections (browse) after PierceFirewall
    /// PierceFirewall normally stops the receive loop for file transfers,
    /// but P connections need to continue receiving peer messages (SharesReply, etc.)
    func resumeReceivingForPeerConnection() {
        guard shouldStopReceiving else {
            logger.debug("[\(self.peerInfo.username)] resumeReceivingForPeerConnection: already receiving")
            return
        }

        logger.debug("[\(self.peerInfo.username)] Resuming receive loop for P connection (browse)")
        shouldStopReceiving = false

        // Move any data from file transfer buffer back to receive buffer
        if !fileTransferBuffer.isEmpty {
            receiveBuffer.append(fileTransferBuffer)
            fileTransferBuffer.removeAll()
            logger.debug("[\(self.peerInfo.username)] Moved \(self.receiveBuffer.count) bytes back to receive buffer")
        }

        startReceiving()
    }

    private func startReceiving() {
        guard let connection else {
            logger.warning("[\(self.peerInfo.username)] startReceiving called but no connection!")
            return
        }

        logger.debug("[\(self.peerInfo.username)] Starting receive loop...")

        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self else {
                // self is nil, cannot log
                return
            }

            Task {
                let username = self.peerInfo.username
                if let error {
                    self.logger.debug("[\(username)] Receive error: \(error.localizedDescription)")
                }

                // Check if we should stop BEFORE processing data
                if await self.shouldStopReceiving {
                    // Store data for file transfer instead of parsing as messages
                    if let data {
                        await self.appendToFileTransferBuffer(data)
                        self.logger.debug("[\(username)] Receive loop stopped, stored \(data.count) bytes for file transfer")
                    }
                    return // Don't continue receive loop
                }

                if let data {
                    await self.handleReceivedData(data)
                } else {
                    self.logger.debug("[\(username)] No data received")
                }

                // Re-check shouldStopReceiving AFTER processing data.
                // This is critical because handleReceivedData may have processed
                // a PierceFirewall message that set shouldStopReceiving = true
                // and already started a receiveRawBytes() call.
                // If we start another receive here, we'd have two concurrent
                // receives and cause a race condition.
                if await self.shouldStopReceiving {
                    self.logger.debug("[\(username)] Receive loop stopped after processing (file transfer mode)")
                    return
                }

                if isComplete {
                    self.logger.debug("[\(username)] Connection complete, disconnecting")
                    await self.disconnect()
                } else if error == nil {
                    await self.startReceiving()
                } else {
                    self.logger.debug("[\(username)] Not continuing receive due to error")
                }
            }
        }
    }

    private func appendToFileTransferBuffer(_ data: Data) {
        fileTransferBuffer.append(data)
    }

    // Track if we've completed handshake
    private var handshakeComplete = false
    private var peerHandshakeReceived = false  // True when we receive peer's PeerInit
    private var peerUsername: String = ""

    /// Wait for the peer to complete handshake (send their PeerInit)
    /// This is needed before sending requests like GetShareFileList
    func waitForPeerHandshake(timeout: Duration = .seconds(10)) async throws {
        let start = Date()
        let timeoutSeconds = TimeInterval(timeout.components.seconds)
        while !peerHandshakeReceived {
            try await Task.sleep(for: .milliseconds(50))
            if Date().timeIntervalSince(start) > timeoutSeconds {
                logger.warning("[\(self.peerInfo.username)] Timeout waiting for peer handshake")
                throw PeerError.timeout
            }
        }
        logger.info("[\(self.peerInfo.username)] Peer handshake received")
    }

    /// Check if peer has completed handshake
    var isPeerHandshakeComplete: Bool {
        peerHandshakeReceived
    }

    // MARK: - Security Constants
    /// Maximum receive buffer size to prevent memory exhaustion from malicious peers
    /// Must be larger than max message size (100MB) to allow buffering of large share lists
    private static let maxReceiveBufferSize = 150 * 1024 * 1024  // 150MB

    private func handleReceivedData(_ data: Data) async {
        receiveBuffer.append(data)
        bytesReceived += UInt64(data.count)
        lastActivityAt = Date()

        // SECURITY: Check buffer size to prevent memory exhaustion
        guard receiveBuffer.count <= Self.maxReceiveBufferSize else {
            logger.error("Receive buffer exceeded limit (\(Self.maxReceiveBufferSize) bytes), disconnecting malicious peer")
            logger.error("SECURITY: [\(self.peerInfo.username)] Buffer overflow protection triggered, disconnecting")
            receiveBuffer.removeAll()
            disconnect()
            return
        }

        let preview = data.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.debug("[\(self.peerInfo.username)] Received \(data.count) bytes, buffer=\(self.receiveBuffer.count) bytes")
        logger.debug("[\(self.peerInfo.username)] Data preview: \(preview)")

        // Parse messages - init messages use 1-byte codes, peer messages use 4-byte codes
        while receiveBuffer.count >= 5 {
            guard let length = receiveBuffer.readUInt32(at: 0) else {
                logger.debug("[\(self.peerInfo.username)] Failed to read message length")
                break
            }

            // Sanity check - messages shouldn't be larger than 100MB
            guard length <= 100_000_000 else {
                logger.warning("[\(self.peerInfo.username)] Invalid message length: \(length) - likely file transfer data on wrong connection")
                receiveBuffer.removeAll()
                break
            }

            let totalLength = 4 + Int(length)
            guard receiveBuffer.count >= totalLength else {
                logger.debug("[\(self.peerInfo.username)] Waiting for more data: have \(self.receiveBuffer.count), need \(totalLength)")
                break
            }

            // Check if this is an init message (1-byte code) or peer message (4-byte code)
            guard let firstByte = receiveBuffer.readByte(at: 4) else {
                logger.debug("[\(self.peerInfo.username)] Failed to read first byte")
                break
            }

            logger.debug("[\(self.peerInfo.username)] Message: length=\(length), firstByte=\(firstByte), handshakeComplete=\(self.handshakeComplete)")

            if !handshakeComplete && (firstByte == 0 || firstByte == 1) {
                // Init message with 1-byte code
                logger.debug("[\(self.peerInfo.username)] Init message: code=\(firstByte) length=\(length)")
                let payload = receiveBuffer.safeSubdata(in: 5..<totalLength) ?? Data()
                receiveBuffer.removeFirst(totalLength)
                messagesReceived += 1

                await handleInitMessage(code: firstByte, payload: payload)
            } else if connectionType == .distributed {
                // Distributed messages use 1-byte code: uint32 length + uint8 code + payload
                let code = UInt32(firstByte)
                logger.debug("[\(self.peerInfo.username)] Distributed message: code=\(code) length=\(length)")
                let payload = receiveBuffer.safeSubdata(in: 5..<totalLength) ?? Data()

                receiveBuffer.removeFirst(totalLength)
                messagesReceived += 1

                // Route to distributed message handler (connected via setOnMessage in ServerMessageHandler)
                await _onMessage?(code, payload)
            } else {
                // Peer message with 4-byte code
                // Minimum valid peer message: 4 bytes length + 4 bytes code = 8 bytes total, so length >= 4
                guard length >= 4 else {
                    logger.warning("[\(self.peerInfo.username)] Invalid peer message length \(length) < 4 - likely raw file transfer data")
                    // This data is not a valid peer message - could be file transfer data on wrong connection
                    // Move to file transfer buffer and stop parsing
                    fileTransferBuffer.append(receiveBuffer)
                    receiveBuffer.removeAll()
                    break
                }
                guard receiveBuffer.count >= 8 else {
                    logger.debug("[\(self.peerInfo.username)] Buffer too small for peer message header")
                    break
                }
                guard let code = receiveBuffer.readUInt32(at: 4) else {
                    logger.debug("[\(self.peerInfo.username)] Failed to read message code")
                    break
                }
                let codeDescription = code <= 255 ? (PeerMessageCode(rawValue: UInt8(code))?.description ?? "unknown") : "invalid(\(code))"
                logger.debug("[\(self.peerInfo.username)] Peer message: code=\(code) (\(codeDescription)) length=\(length)")
                let payload = receiveBuffer.safeSubdata(in: 8..<totalLength) ?? Data()

                receiveBuffer.removeFirst(totalLength)
                messagesReceived += 1

                await handlePeerMessage(code: code, payload: payload)
            }
        }
    }

    private func handleInitMessage(code: UInt8, payload: Data) async {
        logger.info("Received init message: code=\(code) length=\(payload.count)")

        switch code {
        case PeerMessageCode.pierceFirewall.rawValue:
            // Firewall pierce - extract token and notify for matching to pending downloads
            // This connection will now be used for file transfer (raw bytes, no message framing)
            if let token = payload.readUInt32(at: 0) {
                logger.info("PierceFirewall with token: \(token)")
                logger.info("PierceFirewall received with token: \(token)")

                // CRITICAL: Stop receive loop IMMEDIATELY before invoking callback
                // After PierceFirewall, the connection switches to raw file transfer mode.
                // The next bytes will be FileOffset (8 raw bytes), not a length-prefixed message.
                shouldStopReceiving = true
                logger.debug("PierceFirewall: stopped receive loop for file transfer mode")

                // Move any remaining receive buffer data to file transfer buffer
                if !receiveBuffer.isEmpty {
                    fileTransferBuffer.append(receiveBuffer)
                    logger.debug("PierceFirewall: moved \(self.receiveBuffer.count) bytes to file transfer buffer")
                    receiveBuffer.removeAll()
                }

                await _onPierceFirewall?(token)
            }
            handshakeComplete = true
            peerHandshakeReceived = true

        case PeerMessageCode.peerInit.rawValue:
            // Peer init - extract username, type, token
            var offset = 0

            if let (username, usernameLen) = payload.readString(at: offset) {
                offset += usernameLen
                peerUsername = username

                var peerToken: UInt32 = 0
                var connType: String = "P"
                if let (type, typeLen) = payload.readString(at: offset) {
                    offset += typeLen
                    connType = type

                    if let token = payload.readUInt32(at: offset) {
                        peerToken = token
                        logger.info("PeerInit from \(username) type=\(connType) token=\(token)")
                    }
                }

                // Handle based on connection type
                if connType == "F" {
                    // File transfer connection - notify for file data handling
                    logger.info("File transfer connection from \(username) token=\(peerToken)")
                    logger.info("F connection detected: username='\(username)' token=\(peerToken)")

                    // CRITICAL: Stop receive loop IMMEDIATELY before invoking callback
                    // This prevents race condition where receive loop consumes FileTransferInit bytes
                    // before the callback handler can call stopReceiving()
                    shouldStopReceiving = true
                    logger.debug("F connection: stopped receive loop preemptively")

                    // Move any remaining receive buffer data to file transfer buffer
                    // This preserves FileTransferInit bytes that may have been received
                    if !receiveBuffer.isEmpty {
                        fileTransferBuffer.append(receiveBuffer)
                        logger.debug("F connection: moved \(self.receiveBuffer.count) bytes from receive buffer to file transfer buffer")
                        receiveBuffer.removeAll()
                    }

                    if _onFileTransferConnection != nil {
                        logger.debug("F connection callback is set, invoking...")
                        await _onFileTransferConnection?(username, peerToken, self)
                        logger.debug("F connection callback invoked")
                    } else {
                        logger.warning("F connection callback is nil!")
                    }
                } else {
                    // Regular peer connection - notify the pool
                    await _onUsernameDiscovered?(username, peerToken)
                }
            }
            handshakeComplete = true
            peerHandshakeReceived = true
            logger.info("[\(self.peerUsername)] Peer handshake complete (received PeerInit)")

        default:
            logger.warning("Unknown init message code: \(code)")
            // Assume handshake is done and this might be a peer message
            handshakeComplete = true
        }
    }

    private func handlePeerMessage(code: UInt32, payload: Data) async {
        let codeDescription: String
        if let seeleCode = SeeleSeekPeerCode(rawValue: code) {
            codeDescription = seeleCode.description
        } else if code <= 255, let peerCode = PeerMessageCode(rawValue: UInt8(code)) {
            codeDescription = peerCode.description
        } else {
            codeDescription = "unknown(\(code))"
        }
        logger.debug("[\(self.peerInfo.username)] handlePeerMessage: code=\(code) (\(codeDescription)) payload=\(payload.count) bytes")

        // Handle based on message code
        switch code {
        case UInt32(PeerMessageCode.sharesRequest.rawValue):
            logger.info("[\(self.peerInfo.username)] Received SharesRequest - peer wants to browse us")
            await handleSharesRequest()

        case UInt32(PeerMessageCode.sharesReply.rawValue):
            logger.debug("[\(self.peerInfo.username)] Routing to handleSharesReply...")
            await handleSharesReply(payload)

        case UInt32(PeerMessageCode.searchReply.rawValue):
            await handleSearchReply(payload)

        case UInt32(PeerMessageCode.userInfoReply.rawValue):
            await handleUserInfoReply(payload)

        case UInt32(PeerMessageCode.transferRequest.rawValue):
            await handleTransferRequest(payload)

        case UInt32(PeerMessageCode.transferReply.rawValue):
            await handleTransferReply(payload)

        case UInt32(PeerMessageCode.queueDownload.rawValue):
            await handleQueueDownload(payload)

        case UInt32(PeerMessageCode.placeInQueueReply.rawValue):
            await handlePlaceInQueue(payload)

        case UInt32(PeerMessageCode.uploadFailed.rawValue):
            await handleUploadFailed(payload)

        case UInt32(PeerMessageCode.uploadDenied.rawValue):
            await handleUploadDenied(payload)

        case UInt32(PeerMessageCode.folderContentsRequest.rawValue):
            await handleFolderContentsRequest(payload)

        case UInt32(PeerMessageCode.folderContentsReply.rawValue):
            await handleFolderContentsReply(payload)

        case UInt32(PeerMessageCode.placeInQueueRequest.rawValue):
            await handlePlaceInQueueRequest(payload)

        case UInt32(PeerMessageCode.uploadQueueNotification.rawValue):
            logger.debug("Received UploadQueueNotification (deprecated)")

        case UInt32(PeerMessageCode.userInfoRequest.rawValue):
            await handleUserInfoRequest()

        // SeeleSeek extension codes
        case SeeleSeekPeerCode.handshake.rawValue:
            handleSeeleSeekHandshake(payload)

        case SeeleSeekPeerCode.artworkRequest.rawValue:
            await handleArtworkRequest(payload)

        case SeeleSeekPeerCode.artworkReply.rawValue:
            await handleArtworkReply(payload)

        default:
            logger.debug("Unhandled peer message code: \(code)")
            await _onMessage?(code, payload)
        }
    }

    /// Handle SharesRequest (code 4) - peer wants to browse our shared files
    private func handleSharesRequest() async {
        logger.info("Peer \(self.peerUsername) requested our shares")
        logger.debug("[\(self.peerUsername)] Peer wants to browse our shares, invoking callback...")

        // Delegate to callback which will send the shares
        if let callback = _onSharesRequest {
            await callback(self)
        } else {
            logger.warning("[\(self.peerUsername)] No onSharesRequest callback set!")
        }
    }

    /// Handle UserInfoRequest (code 15) - peer wants our user info
    private func handleUserInfoRequest() async {
        logger.info("Peer \(self.peerUsername) requested our user info")
        logger.debug("[\(self.peerUsername)] Peer wants our user info, invoking callback...")

        // Delegate to callback which will send the user info
        if let callback = _onUserInfoRequest {
            await callback(self)
        } else {
            logger.warning("[\(self.peerUsername)] No onUserInfoRequest callback set!")
        }
    }

    // MARK: - SeeleSeek Extension Handlers

    /// Handle SeeleSeek handshake (code 10000) — marks this peer as a SeeleSeek client.
    private func handleSeeleSeekHandshake(_ payload: Data) {
        let version = payload.count > 0 ? payload[payload.startIndex] : 0
        isSeeleSeekPeer = true
        logger.info("[\(self.peerUsername)] SeeleSeek peer detected (version \(version))")
    }

    /// Handle artwork request (code 10001) — peer wants album art for a file.
    private func handleArtworkRequest(_ payload: Data) async {
        var offset = 0
        guard let token = payload.readUInt32(at: offset) else {
            logger.warning("[\(self.peerUsername)] ArtworkRequest: missing token")
            return
        }
        offset += 4
        guard let (filePath, _) = payload.readString(at: offset) else {
            logger.warning("[\(self.peerUsername)] ArtworkRequest: missing filePath")
            return
        }
        logger.info("[\(self.peerUsername)] ArtworkRequest: token=\(token) file=\(filePath)")
        await _onArtworkRequest?(token, filePath, self)
    }

    /// Handle artwork reply (code 10002) — peer sent us album art.
    private func handleArtworkReply(_ payload: Data) async {
        var offset = 0
        guard let token = payload.readUInt32(at: offset) else {
            logger.warning("[\(self.peerUsername)] ArtworkReply: missing token")
            return
        }
        offset += 4
        // Remaining bytes are the image data
        let imageData = payload.count > offset ? Data(payload[offset...]) : Data()
        logger.info("[\(self.peerUsername)] ArtworkReply: token=\(token) imageSize=\(imageData.count)")
        await _onArtworkReply?(token, imageData)
    }

    // MARK: - Standard Peer Message Handlers

    private func handleSharesReply(_ data: Data) async {
        logger.debug("[\(self.peerInfo.username)] handleSharesReply called with \(data.count) bytes")
        let dataPreview = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.debug("[\(self.peerInfo.username)] Data starts with: \(dataPreview)")

        // Shares are zlib compressed per protocol spec
        let decompressed: Data
        do {
            decompressed = try decompressZlib(data)
            logger.debug("[\(self.peerInfo.username)] Decompressed shares: \(data.count) -> \(decompressed.count) bytes")
        } catch {
            logger.error("[\(self.peerInfo.username)] Failed to decompress shares: \(error)")
            // SharesReply is always zlib compressed per protocol - raw data cannot be parsed
            await _onSharesReceived?([])
            return
        }

        var offset = 0
        var files: [SharedFile] = []

        // Parse directory count
        guard let dirCount = decompressed.readUInt32(at: offset) else {
            logger.debug("[\(self.peerInfo.username)] Failed to read directory count at offset \(offset)")
            return
        }
        // SECURITY: Limit directory count to prevent DoS
        let maxDirCount: UInt32 = 100_000
        guard dirCount <= maxDirCount else {
            logger.warning("SECURITY: Directory count \(dirCount) exceeds limit \(maxDirCount)")
            return
        }
        offset += 4
        logger.debug("[\(self.peerInfo.username)] Directory count: \(dirCount)")

        for dirIndex in 0..<dirCount {
            guard let (dirName, dirLen) = decompressed.readString(at: offset) else {
                logger.debug("[\(self.peerInfo.username)] Failed to read dir name at offset \(offset)")
                break
            }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else {
                logger.debug("[\(self.peerInfo.username)] Failed to read file count at offset \(offset)")
                break
            }
            // SECURITY: Limit file count per directory
            let maxFileCount: UInt32 = 100_000
            guard fileCount <= maxFileCount else {
                logger.warning("SECURITY: File count \(fileCount) exceeds limit")
                break
            }
            offset += 4

            if dirIndex < 3 {
                logger.debug("[\(self.peerInfo.username)] Dir[\(dirIndex)]: '\(dirName)' with \(fileCount) files")
            }

            for _ in 0..<fileCount {
                guard decompressed.readByte(at: offset) != nil else { break }
                offset += 1

                guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                offset += filenameLen

                guard let size = decompressed.readUInt64(at: offset) else { break }
                offset += 8

                guard let (_, extLen) = decompressed.readString(at: offset) else { break }
                offset += extLen

                guard let attrCount = decompressed.readUInt32(at: offset) else { break }
                // SECURITY: Limit attribute count
                let maxAttrCount: UInt32 = 100
                guard attrCount <= maxAttrCount else { break }
                offset += 4

                var bitrate: UInt32?
                var duration: UInt32?

                for _ in 0..<attrCount {
                    guard let attrType = decompressed.readUInt32(at: offset) else { break }
                    offset += 4
                    guard let attrValue = decompressed.readUInt32(at: offset) else { break }
                    offset += 4

                    switch attrType {
                    case 0: bitrate = attrValue
                    case 1: duration = attrValue
                    default: break
                    }
                }

                let file = SharedFile(
                    filename: "\(dirName)\\\(filename)",
                    size: size,
                    bitrate: bitrate,
                    duration: duration,
                    isPrivate: false
                )
                files.append(file)
            }
        }

        // Skip the "unknown" uint32 (always 0 per protocol)
        if offset + 4 <= decompressed.count {
            offset += 4
        }

        // Parse private directories (buddy-only files)
        if let privateDirCount = decompressed.readUInt32(at: offset) {
            // SECURITY: Limit private directory count
            let maxPrivateDirCount: UInt32 = 100_000
            guard privateDirCount <= maxPrivateDirCount else {
                logger.warning("SECURITY: Private directory count \(privateDirCount) exceeds limit")
                return
            }
            offset += 4
            logger.debug("[\(self.peerInfo.username)] Private directory count: \(privateDirCount)")

            for _ in 0..<privateDirCount {
                guard let (dirName, dirLen) = decompressed.readString(at: offset) else { break }
                offset += dirLen

                guard let fileCount = decompressed.readUInt32(at: offset) else { break }
                // SECURITY: Limit file count per directory
                let maxFileCount: UInt32 = 100_000
                guard fileCount <= maxFileCount else { break }
                offset += 4

                for _ in 0..<fileCount {
                    guard decompressed.readByte(at: offset) != nil else { break }
                    offset += 1

                    guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                    offset += filenameLen

                    guard let size = decompressed.readUInt64(at: offset) else { break }
                    offset += 8

                    guard let (_, extLen) = decompressed.readString(at: offset) else { break }
                    offset += extLen

                    guard let attrCount = decompressed.readUInt32(at: offset) else { break }
                    // SECURITY: Limit attribute count
                    let maxAttrCount: UInt32 = 100
                    guard attrCount <= maxAttrCount else { break }
                    offset += 4

                    var bitrate: UInt32?
                    var duration: UInt32?

                    for _ in 0..<attrCount {
                        guard let attrType = decompressed.readUInt32(at: offset) else { break }
                        offset += 4
                        guard let attrValue = decompressed.readUInt32(at: offset) else { break }
                        offset += 4

                        switch attrType {
                        case 0: bitrate = attrValue
                        case 1: duration = attrValue
                        default: break
                        }
                    }

                    let file = SharedFile(
                        filename: "\(dirName)\\\(filename)",
                        size: size,
                        bitrate: bitrate,
                        duration: duration,
                        isPrivate: true  // Mark as private/locked
                    )
                    files.append(file)
                }
            }
        }

        logger.debug("[\(self.peerInfo.username)] Parsed \(files.count) files (including private), callback set: \(self._onSharesReceived != nil)")
        logger.info("Received \(files.count) shared files from \(self.peerInfo.username)")
        await _onSharesReceived?(files)
    }

    private func handleSearchReply(_ data: Data) async {
        logger.debug("[\(self.peerInfo.username)] handleSearchReply called with \(data.count) bytes")
        logger.info("handleSearchReply called with \(data.count) bytes")

        // Search replies may be zlib compressed - try decompression first.
        // If decompressed bytes do not parse, fall back to raw payload parsing.
        var candidatePayloads: [(data: Data, wasCompressed: Bool)] = [(data, false)]
        if data.count > 4 {
            do {
                let decompressed = try decompressZlib(data)
                logger.debug("[\(self.peerInfo.username)] Decompressed from \(data.count) to \(decompressed.count) bytes")
                logger.info("Decompressed search reply from \(data.count) to \(decompressed.count) bytes")
                candidatePayloads.insert((decompressed, true), at: 0)
            } catch {
                logger.debug("[\(self.peerInfo.username)] Not compressed or decompression failed: \(error)")
            }
        }

        var parsedInfo: MessageParser.SearchReplyInfo?
        var parsedFromCompressed = false
        for candidate in candidatePayloads {
            logger.debug("[\(self.peerInfo.username)] Parsing data (compressed=\(candidate.wasCompressed))")
            if let parsed = MessageParser.parseSearchReply(candidate.data) {
                parsedInfo = parsed
                parsedFromCompressed = candidate.wasCompressed
                break
            }
        }

        guard let parsed = parsedInfo else {
            let dataPreview = data.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
            logger.error("[\(self.peerInfo.username)] Failed to parse search reply!")
            logger.debug("[\(self.peerInfo.username)] Data starts with: \(dataPreview)")
            return
        }

        logger.debug("[\(self.peerInfo.username)] Search reply parse succeeded (compressed=\(parsedFromCompressed))")

        let results = parsed.files.map { file in
            SearchResult(
                username: parsed.username.isEmpty ? peerUsername : parsed.username,
                filename: file.filename,
                size: file.size,
                bitrate: file.attributes.first { $0.type == 0 }?.value,
                duration: file.attributes.first { $0.type == 1 }?.value,
                sampleRate: file.attributes.first { $0.type == 4 }?.value,
                bitDepth: file.attributes.first { $0.type == 5 }?.value,
                freeSlots: parsed.freeSlots,
                uploadSpeed: parsed.uploadSpeed,
                queueLength: parsed.queueLength,
                isPrivate: file.isPrivate
            )
        }

        let username = parsed.username.isEmpty ? peerUsername : parsed.username
        logger.info("[\(self.peerInfo.username)] Parsed \(results.count) search results from \(username) for token \(parsed.token)")
        logger.info("Parsed \(results.count) search results from \(username) for token \(parsed.token)")

        if _onSearchReply != nil {
            logger.debug("[\(self.peerInfo.username)] Invoking search reply callback for token \(parsed.token)...")
            await _onSearchReply?(parsed.token, results)
            logger.debug("[\(self.peerInfo.username)] Callback invoked successfully")
            logger.info("Search results callback invoked for token \(parsed.token)")
        } else {
            logger.warning("[\(self.peerInfo.username)] No search reply callback set!")
            logger.warning("No search reply callback set!")
        }
    }

    private func handleUserInfoReply(_ data: Data) async {
        var offset = 0

        guard let (_, descLen) = data.readString(at: offset) else { return }
        offset += descLen

        // Has picture flag
        guard let hasPicture = data.readBool(at: offset) else { return }
        offset += 1

        if hasPicture {
            guard let pictureLen = data.readUInt32(at: offset) else { return }
            offset += 4 + Int(pictureLen)
        }

        guard let totalUploads = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let queueSize = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let slotsFree = data.readBool(at: offset) else { return }

        logger.info("User info: uploads=\(totalUploads) queue=\(queueSize) freeSlots=\(slotsFree)")
    }

    private func handleTransferRequest(_ data: Data) async {
        guard let parsed = MessageParser.parseTransferRequest(data) else {
            let hexDump = data.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
            logger.error("Failed to parse TransferRequest, data: \(hexDump)")
            return
        }

        let fileSize = parsed.fileSize ?? 0
        if fileSize == 0 && parsed.direction == .upload {
            logger.warning("TransferRequest has zero file size - this may cause issues")
            logger.warning("TransferRequest: direction=\(String(describing: parsed.direction)) token=\(parsed.token) filename=\(parsed.filename) size=\(fileSize) (WARNING: zero size!)")
        } else {
            logger.info("TransferRequest: direction=\(String(describing: parsed.direction)) token=\(parsed.token) filename=\(parsed.filename) size=\(fileSize)")
        }

        let request = TransferRequest(
            direction: parsed.direction,
            token: parsed.token,
            filename: parsed.filename,
            size: fileSize,
            username: peerInfo.username
        )

        // Check for per-token handler first (for concurrent downloads on same connection)
        if let tokenHandler = _tokenTransferRequestHandlers[parsed.token] {
            logger.debug("Dispatching TransferRequest to per-token handler for token \(parsed.token)")
            await tokenHandler(request)
            // Remove the handler after use (one-shot callback)
            _tokenTransferRequestHandlers.removeValue(forKey: parsed.token)
        } else if let globalHandler = _onTransferRequest {
            // Fall back to global handler
            logger.debug("Dispatching TransferRequest to global handler")
            await globalHandler(request)
        } else {
            logger.warning("No handler for TransferRequest token=\(parsed.token)")
        }
    }

    private func handleTransferReply(_ data: Data) async {
        var offset = 0

        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let allowed = data.readBool(at: offset) else { return }
        offset += 1

        var filesize: UInt64? = nil
        if allowed {
            if let size = data.readUInt64(at: offset) {
                filesize = size
                logger.info("Transfer allowed: token=\(token) size=\(size)")
                logger.info("TransferResponse: token=\(token) allowed=true size=\(size)")
            }
        } else {
            if let (reason, _) = data.readString(at: offset) {
                logger.info("Transfer denied: token=\(token) reason=\(reason)")
                logger.info("TransferResponse: token=\(token) allowed=false reason=\(reason)")
            }
        }

        await _onTransferResponse?(token, allowed, filesize)
    }

    private func handleQueueDownload(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        // Use peerInfo.username as fallback - peerUsername is only set when receiving PeerInit,
        // but on outgoing connections the peer may send messages before their PeerInit
        let username = self.peerUsername.isEmpty ? self.peerInfo.username : self.peerUsername
        logger.info("QueueUpload received from \(username): \(filename)")
        await _onQueueUpload?(username, filename)
    }

    private func handlePlaceInQueue(_ data: Data) async {
        guard let (filename, len) = data.readString(at: 0) else { return }
        guard let place = data.readUInt32(at: len) else { return }
        logger.info("Queue position for \(filename): \(place)")
        await _onPlaceInQueueReply?(filename, place)
    }

    private func handleUploadFailed(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        let username = self.peerUsername.isEmpty ? self.peerInfo.username : self.peerUsername
        logger.warning("UploadFailed from \(username): \(filename)")
        await _onUploadFailed?(filename)
    }

    private func handleUploadDenied(_ data: Data) async {
        guard let (filename, filenameLen) = data.readString(at: 0) else { return }
        let reason = data.readString(at: filenameLen)?.string ?? "Unknown reason"
        logger.warning("Upload denied for \(filename): \(reason)")
        logger.warning("UploadDenied: \(filename) - \(reason)")
        await _onUploadDenied?(filename, reason)
    }

    private func handleFolderContentsRequest(_ data: Data) async {
        var offset = 0

        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let (folder, _) = data.readString(at: offset) else { return }

        logger.info("Folder contents request: \(folder) token=\(token)")
        logger.info("FolderContentsRequest: \(folder) token=\(token)")
        await _onFolderContentsRequest?(token, folder)
    }

    private func handlePlaceInQueueRequest(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        let username = self.peerUsername.isEmpty ? self.peerInfo.username : self.peerUsername
        logger.info("PlaceInQueueRequest for: \(filename) from \(username)")
        await _onPlaceInQueueRequest?(username, filename)
    }

    private func handleFolderContentsReply(_ data: Data) async {
        // Folder contents are zlib compressed
        guard let decompressed = try? decompressZlib(data) else {
            logger.error("Failed to decompress folder contents")
            return
        }

        var offset = 0

        guard let token = decompressed.readUInt32(at: offset) else { return }
        offset += 4

        guard let (folder, folderLen) = decompressed.readString(at: offset) else { return }
        offset += folderLen

        guard let folderCount = decompressed.readUInt32(at: offset) else { return }
        offset += 4

        var files: [SharedFile] = []
        let maxFolderCount: UInt32 = 100_000
        let maxFileCount: UInt32 = 100_000
        let maxAttributeCount: UInt32 = 100
        guard folderCount <= maxFolderCount else { return }

        for _ in 0..<folderCount {
            guard let (_, dirLen) = decompressed.readString(at: offset) else { break }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else { break }
            offset += 4
            guard fileCount <= maxFileCount else { break }

            for _ in 0..<fileCount {
                // uint8 code
                guard decompressed.readByte(at: offset) != nil else { break }
                offset += 1

                // string filename
                guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                offset += filenameLen

                // uint64 size
                guard let size = decompressed.readUInt64(at: offset) else { break }
                offset += 8

                // string extension
                guard let (_, extLen) = decompressed.readString(at: offset) else { break }
                offset += extLen

                // uint32 attribute count
                guard let attrCount = decompressed.readUInt32(at: offset) else { break }
                offset += 4
                guard attrCount <= maxAttributeCount else { break }

                var bitrate: UInt32?
                var duration: UInt32?

                for _ in 0..<attrCount {
                    guard let attrType = decompressed.readUInt32(at: offset) else { break }
                    offset += 4
                    guard let attrValue = decompressed.readUInt32(at: offset) else { break }
                    offset += 4

                    switch attrType {
                    case 0: bitrate = attrValue
                    case 1: duration = attrValue
                    default: break
                    }
                }

                let file = SharedFile(
                    filename: filename,
                    size: size,
                    bitrate: bitrate,
                    duration: duration
                )
                files.append(file)
            }
        }

        logger.info("Received folder contents: \(folder) (\(files.count) files)")
        logger.info("FolderContentsReply: \(folder) with \(files.count) files")
        await _onFolderContentsResponse?(token, folder, files)
    }

    private func updateState(_ newState: State) {
        state = newState
        Task {
            await _onStateChanged?(newState)
        }
    }

    private func recordSent(_ bytes: Int) {
        bytesSent += UInt64(bytes)
        messagesSent += 1
        lastActivityAt = Date()
    }

    private func recordReceived(_ bytes: Int) {
        bytesReceived += UInt64(bytes)
        lastActivityAt = Date()
    }

    // MARK: - Zlib Decompression

    private func decompressZlib(_ data: Data) throws -> Data {
        // SoulSeek uses standard zlib format (RFC 1950):
        // - 2-byte header
        // - DEFLATE compressed data
        // - 4-byte Adler-32 checksum
        //
        // Apple's COMPRESSION_ZLIB expects raw DEFLATE (RFC 1951) without header/footer.
        // We need to strip the 2-byte header and 4-byte footer.

        guard data.count > 6 else {
            logger.debug("Decompression: data too short (\(data.count) bytes)")
            throw PeerError.decompressionFailed
        }

        // Verify zlib header (first byte should have compression method 8 = deflate)
        let cmf = data[data.startIndex]
        let flg = data[data.startIndex + 1]
        let compressionMethod = cmf & 0x0F
        let cmfHex = String(format: "%02x", cmf)
        let flgHex = String(format: "%02x", flg)
        logger.debug("Decompression: CMF=0x\(cmfHex) FLG=0x\(flgHex) method=\(compressionMethod)")

        guard compressionMethod == 8 else {
            logger.debug("Not zlib format (method != 8), trying raw deflate")
            // Not zlib format, try raw deflate
            return try decompressRawDeflate(data)
        }

        // Strip zlib header (2 bytes) and Adler-32 checksum (4 bytes)
        let deflateData = data.dropFirst(2).dropLast(4)
        logger.debug("Stripped zlib header/footer: \(data.count) -> \(deflateData.count) bytes")

        let result = try decompressRawDeflate(Data(deflateData))
        logger.debug("Decompressed: \(deflateData.count) -> \(result.count) bytes")

        // Log first few bytes of decompressed data
        let preview = result.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.debug("Decompressed preview: \(preview)")

        return result
    }

    private func decompressRawDeflate(_ data: Data) throws -> Data {
        // SECURITY: Maximum decompressed size to prevent decompression bombs
        let maxDecompressedSize = 50 * 1024 * 1024  // 50MB max
        // SECURITY: Maximum compression ratio (normal zlib is ~10-50x, >1000x is suspicious)
        let maxCompressionRatio = 1000

        let decompressed = try data.withUnsafeBytes { sourceBuffer -> Data in
            let sourceSize = data.count
            guard let baseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw PeerError.decompressionFailed
            }

            // Start with a reasonable estimate, expand if needed
            var destinationSize = min(max(sourceSize * 20, 65536), maxDecompressedSize)
            var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)

            var decodedSize = compression_decode_buffer(
                &destinationBuffer,
                destinationSize,
                baseAddress,
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )

            // If output buffer was too small, try with larger buffer (but capped)
            if decodedSize == 0 || decodedSize == destinationSize {
                destinationSize = min(sourceSize * 100, maxDecompressedSize)
                // SECURITY: Check if we've hit the limit
                guard destinationSize <= maxDecompressedSize else {
                    logger.warning("SECURITY: Decompression size limit exceeded")
                    throw PeerError.decompressionFailed
                }
                destinationBuffer = [UInt8](repeating: 0, count: destinationSize)
                decodedSize = compression_decode_buffer(
                    &destinationBuffer,
                    destinationSize,
                    baseAddress,
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard decodedSize > 0 else {
                throw PeerError.decompressionFailed
            }

            // SECURITY: Check compression ratio
            let compressionRatio = decodedSize / max(sourceSize, 1)
            if compressionRatio > maxCompressionRatio {
                logger.warning("SECURITY: Suspicious compression ratio \(compressionRatio):1")
                throw PeerError.decompressionFailed
            }

            // SECURITY: Final size check
            guard decodedSize <= maxDecompressedSize else {
                logger.warning("SECURITY: Decompressed size \(decodedSize) exceeds limit \(maxDecompressedSize)")
                throw PeerError.decompressionFailed
            }

            return Data(destinationBuffer.prefix(decodedSize))
        }

        return decompressed
    }
}

// MARK: - Types

struct TransferRequest: Sendable {
    let direction: FileTransferDirection
    let token: UInt32
    let filename: String
    let size: UInt64
    let username: String
}

enum PeerError: Error, LocalizedError {
    case notConnected
    case connectionClosed
    case handshakeFailed
    case decompressionFailed
    case timeout
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to peer"
        case .connectionClosed: return "Connection closed"
        case .handshakeFailed: return "Handshake failed"
        case .decompressionFailed: return "Failed to decompress data"
        case .timeout: return "Connection timed out"
        case .invalidPort: return "Invalid port number"
        }
    }
}

import Compression
