import Foundation
import Network
import os
import Compression

/// Manages a single peer-to-peer connection
actor PeerConnection {
    private let logger = Logger(subsystem: "com.seeleseek", category: "PeerConnection")

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

    // Note: peerInfo uses nonisolated(unsafe) because it may be updated after init
    // when extracting IP/port from incoming connections. This is safe because
    // updates only happen during connection setup, before concurrent access.
    nonisolated(unsafe) var peerInfo: PeerInfo
    nonisolated let connectionType: ConnectionType
    nonisolated let isIncoming: Bool
    nonisolated let token: UInt32

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private(set) var state: State = .disconnected

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
        print("📝 Registered TransferRequest handler for token \(token) (total handlers: \(_tokenTransferRequestHandlers.count))")
    }

    /// Remove a per-token TransferRequest handler
    func removeTransferRequestHandlerForToken(_ token: UInt32) {
        _tokenTransferRequestHandlers.removeValue(forKey: token)
        print("📝 Removed TransferRequest handler for token \(token) (remaining: \(_tokenTransferRequestHandlers.count))")
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

    /// Get the discovered peer username (from PeerInit message)
    func getPeerUsername() -> String {
        return peerUsername
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
        self.peerInfo = peerInfo
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
                print("📥 Incoming connection: extracted IP=\(extractedIP) port=\(extractedPort)")
            default:
                print("📥 Incoming connection: could not extract IP/port from endpoint: \(remoteEndpoint)")
            }
        } else {
            // Path not available yet, try to extract from endpoint directly
            // This can happen before the connection is started
            print("📥 Incoming connection: currentPath not available, IP/port unknown until connection starts")
        }

        self.peerInfo = PeerInfo(username: "", ip: extractedIP, port: extractedPort)
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

        let conn = NWConnection(to: endpoint, using: params)
        print("🔌 Creating TCP connection to \(peerInfo.ip):\(peerInfo.port)")
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
            print("⏰ Task cancelled, stopping NWConnection to \(self.peerInfo.ip):\(self.peerInfo.port)...")
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
                print("📥 Connection ready: extracted IP=\(extractedIP) port=\(extractedPort)")

                // Update peerInfo with extracted IP/port
                peerInfo = PeerInfo(
                    username: peerInfo.username,
                    ip: extractedIP,
                    port: extractedPort,
                    uploadSpeed: peerInfo.uploadSpeed,
                    downloadSpeed: peerInfo.downloadSpeed,
                    freeUploadSlots: peerInfo.freeUploadSlots,
                    queueLength: peerInfo.queueLength,
                    sharedFiles: peerInfo.sharedFiles,
                    sharedFolders: peerInfo.sharedFolders
                )
                print("✅ Updated peerInfo with IP=\(extractedIP) port=\(extractedPort)")
            default:
                print("⚠️ Could not extract IP/port from endpoint type: \(remoteEndpoint)")
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
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

        print("📤 PeerInit: username='\(username)' type='\(connectionType.rawValue)' token=\(peerInitToken)")
        try await send(message)

        // Mark handshake as complete from our side after sending PeerInit
        // We can now receive peer messages (code >= 4) without waiting for peer's response
        handshakeComplete = true
        print("📤 PeerInit sent, handshake marked complete")
    }

    func sendPierceFirewall() async throws {
        let message = MessageBuilder.pierceFirewallMessage(token: token)
        print("📤 Sending PierceFirewall to \(peerInfo.username) with token \(token) (\(message.count) bytes)")
        print("📤 PierceFirewall data: \(message.map { String(format: "%02x", $0) }.joined(separator: " "))")
        try await send(message)
        // Mark handshake as complete from our side - peer will send peer messages (not init messages) now
        handshakeComplete = true
        print("📤 PierceFirewall sent successfully to \(peerInfo.username), handshake complete")
    }

    // MARK: - Peer Messages

    func requestShares() async throws {
        let message = MessageBuilder.sharesRequestMessage()
        print("📂 [\(peerInfo.username)] Sending GetShareFileList (code 4), message: \(message.map { String(format: "%02x", $0) }.joined(separator: " "))")
        try await send(message)
        print("📂 [\(peerInfo.username)] GetShareFileList sent successfully")
        logger.info("Requested shares from \(self.peerInfo.username)")
    }

    func requestUserInfo() async throws {
        let message = MessageBuilder.userInfoRequestMessage()
        try await send(message)
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

    func sendTransferReply(token: UInt32, allowed: Bool, reason: String? = nil) async throws {
        let message = MessageBuilder.transferReplyMessage(token: token, allowed: allowed, reason: reason)
        try await send(message)
        logger.info("Sent transfer reply: token=\(token) allowed=\(allowed)")
    }

    func sendPlaceInQueue(filename: String, place: UInt32) async throws {
        let message = MessageBuilder.placeInQueueResponseMessage(filename: filename, place: place)
        try await send(message)
        logger.info("Sent place in queue: \(filename) position=\(place)")
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
            print("❌ [\(peerInfo.username)] send() - no connection!")
            throw PeerError.notConnected
        }
        // Allow sending in connected or handshaking state
        switch state {
        case .connected, .handshaking:
            break
        default:
            print("❌ [\(peerInfo.username)] send() - wrong state: \(state)")
            throw PeerError.notConnected
        }

        print("📤 [\(peerInfo.username)] Sending \(data.count) bytes: \(data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    print("❌ [\(self?.peerInfo.username ?? "??")] send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ [\(self?.peerInfo.username ?? "??")] send succeeded")
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

        print("📤 [\(peerInfo.username)] Sending RAW \(data.count) bytes: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    print("❌ [\(self?.peerInfo.username ?? "??")] sendRaw failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ [\(self?.peerInfo.username ?? "??")] sendRaw succeeded")
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

        print("📥 [\(peerInfo.username)] Waiting for \(count) raw bytes (timeout: \(timeout)s)...")

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
                        if let error {
                            print("❌ [\(self?.peerInfo.username ?? "??")] receiveRawBytes error: \(error)")
                            continuation.resume(throwing: error)
                        } else if let data, data.count >= count {
                            print("✅ [\(self?.peerInfo.username ?? "??")] Received \(data.count) raw bytes")
                            Task {
                                await self?.recordReceived(data.count)
                            }
                            continuation.resume(returning: data)
                        } else {
                            print("❌ [\(self?.peerInfo.username ?? "??")] Received incomplete data: \(data?.count ?? 0)/\(count)")
                            continuation.resume(throwing: PeerError.connectionClosed)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw PeerError.timeout
            }

            let result = try await group.next()!
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
            print("📁 Using \(chunk.count) bytes from file transfer buffer")
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
        print("📡 [\(peerInfo.username)] Stopped receive loop, cleared message buffer")
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
            print("🟢 PEER CONNECTED: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
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
            print("🔴 PEER CONNECTION FAILED: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            print("🔴 Error details: \(error)")
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
            print("🟡 PEER CONNECTION WAITING: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            print("🟡 Waiting error: \(error)")
            // Check if this is a definitive failure (not just a transient condition)
            // POSIX errors: 12 (ENOMEM), 51 (ENETUNREACH), 57 (ENOTCONN), 60 (ETIMEDOUT), 61 (ECONNREFUSED), 65 (EHOSTUNREACH)
            if case .posix(let posixError) = error {
                let code = posixError.rawValue
                if code == 12 || code == 51 || code == 57 || code == 60 || code == 61 || code == 65 {
                    // These are definitive failures, not transient
                    print("🔴 PEER CONNECTION DEFINITIVE FAILURE: \(self.peerInfo.username) - POSIX \(code)")
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
            print("🔵 PEER CONNECTION PREPARING: \(self.peerInfo.username) -> \(self.peerInfo.ip):\(self.peerInfo.port)")

        case .cancelled:
            print("⚪ PEER CONNECTION CANCELLED: \(self.peerInfo.username)")
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

    private func startReceiving() {
        guard let connection else {
            print("📡 [\(peerInfo.username)] startReceiving called but no connection!")
            return
        }

        print("📡 [\(peerInfo.username)] Starting receive loop...")

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                print("📡 startReceiving callback but self is nil!")
                return
            }

            Task {
                let username = self.peerInfo.username
                if let error {
                    print("📡 [\(username)] Receive error: \(error.localizedDescription)")
                }

                // Check if we should stop BEFORE processing data
                if await self.shouldStopReceiving {
                    // Store data for file transfer instead of parsing as messages
                    if let data {
                        await self.appendToFileTransferBuffer(data)
                        print("📡 [\(username)] Receive loop stopped, stored \(data.count) bytes for file transfer")
                    }
                    return // Don't continue receive loop
                }

                if let data {
                    await self.handleReceivedData(data)
                } else {
                    print("📡 [\(username)] No data received")
                }

                if isComplete {
                    print("📡 [\(username)] Connection complete, disconnecting")
                    await self.disconnect()
                } else if error == nil {
                    await self.startReceiving()
                } else {
                    print("📡 [\(username)] Not continuing receive due to error")
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
                print("⏱️ [\(peerInfo.username)] Timeout waiting for peer handshake")
                throw PeerError.timeout
            }
        }
        print("✅ [\(peerInfo.username)] Peer handshake received")
    }

    /// Check if peer has completed handshake
    var isPeerHandshakeComplete: Bool {
        peerHandshakeReceived
    }

    private func handleReceivedData(_ data: Data) async {
        receiveBuffer.append(data)
        bytesReceived += UInt64(data.count)
        lastActivityAt = Date()

        let preview = data.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("📥 [\(peerInfo.username)] Received \(data.count) bytes, buffer=\(receiveBuffer.count) bytes")
        print("📥 [\(peerInfo.username)] Data preview: \(preview)")

        // Parse messages - init messages use 1-byte codes, peer messages use 4-byte codes
        while receiveBuffer.count >= 5 {
            guard let length = receiveBuffer.readUInt32(at: 0) else {
                print("📥 [\(peerInfo.username)] Failed to read message length")
                break
            }

            // Sanity check - messages shouldn't be larger than 100MB
            guard length <= 100_000_000 else {
                print("📥 [\(peerInfo.username)] Invalid message length: \(length) - likely file transfer data on wrong connection")
                receiveBuffer.removeAll()
                break
            }

            let totalLength = 4 + Int(length)
            guard receiveBuffer.count >= totalLength else {
                print("📥 [\(peerInfo.username)] Waiting for more data: have \(receiveBuffer.count), need \(totalLength)")
                break
            }

            // Check if this is an init message (1-byte code) or peer message (4-byte code)
            guard let firstByte = receiveBuffer.readByte(at: 4) else {
                print("📥 [\(peerInfo.username)] Failed to read first byte")
                break
            }

            print("📥 [\(peerInfo.username)] Message: length=\(length), firstByte=\(firstByte), handshakeComplete=\(handshakeComplete)")

            if !handshakeComplete && (firstByte == 0 || firstByte == 1) {
                // Init message with 1-byte code
                print("📥 [\(peerInfo.username)] Init message: code=\(firstByte) length=\(length)")
                let payload = receiveBuffer.safeSubdata(in: 5..<totalLength) ?? Data()
                receiveBuffer.removeFirst(totalLength)
                messagesReceived += 1

                await handleInitMessage(code: firstByte, payload: payload)
            } else {
                // Peer message with 4-byte code
                guard receiveBuffer.count >= 8 else {
                    print("📥 [\(peerInfo.username)] Buffer too small for peer message header")
                    break
                }
                guard let code = receiveBuffer.readUInt32(at: 4) else {
                    print("📥 [\(peerInfo.username)] Failed to read message code")
                    break
                }
                let codeDescription = code <= 255 ? (PeerMessageCode(rawValue: UInt8(code))?.description ?? "unknown") : "invalid(\(code))"
                print("📥 [\(peerInfo.username)] Peer message: code=\(code) (\(codeDescription)) length=\(length)")
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
            if let token = payload.readUInt32(at: 0) {
                logger.info("PierceFirewall with token: \(token)")
                print("🔓 PierceFirewall received with token: \(token)")
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
                    print("📁 F CONNECTION DETECTED: username='\(username)' token=\(peerToken)")

                    // CRITICAL: Stop receive loop IMMEDIATELY before invoking callback
                    // This prevents race condition where receive loop consumes FileTransferInit bytes
                    // before the callback handler can call stopReceiving()
                    shouldStopReceiving = true
                    print("📁 F connection: stopped receive loop preemptively")

                    // Move any remaining receive buffer data to file transfer buffer
                    // This preserves FileTransferInit bytes that may have been received
                    if !receiveBuffer.isEmpty {
                        fileTransferBuffer.append(receiveBuffer)
                        print("📁 F connection: moved \(receiveBuffer.count) bytes from receive buffer to file transfer buffer")
                        receiveBuffer.removeAll()
                    }

                    if _onFileTransferConnection != nil {
                        print("📁 F connection callback IS set, invoking...")
                        await _onFileTransferConnection?(username, peerToken, self)
                        print("📁 F connection callback invoked")
                    } else {
                        print("❌ F connection callback is NIL!")
                    }
                } else {
                    // Regular peer connection - notify the pool
                    await _onUsernameDiscovered?(username, peerToken)
                }
            }
            handshakeComplete = true
            peerHandshakeReceived = true
            print("✅ [\(peerUsername)] Peer handshake complete (received PeerInit)")

        default:
            logger.warning("Unknown init message code: \(code)")
            // Assume handshake is done and this might be a peer message
            handshakeComplete = true
        }
    }

    private func handlePeerMessage(code: UInt32, payload: Data) async {
        let codeDescription = code <= 255 ? (PeerMessageCode(rawValue: UInt8(code))?.description ?? "unknown") : "invalid"
        print("📨 [\(peerInfo.username)] handlePeerMessage: code=\(code) (\(codeDescription)) payload=\(payload.count) bytes")
        logger.debug("Peer message: code=\(code) length=\(payload.count)")

        // Handle based on message code
        switch code {
        case UInt32(PeerMessageCode.sharesReply.rawValue):
            print("📂 [\(peerInfo.username)] Routing to handleSharesReply...")
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

        default:
            logger.debug("Unhandled peer message code: \(code)")
            await _onMessage?(code, payload)
        }
    }

    private func handleSharesReply(_ data: Data) async {
        print("📂 [\(peerInfo.username)] handleSharesReply called with \(data.count) bytes")
        let dataPreview = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("📂 [\(peerInfo.username)] Data starts with: \(dataPreview)")

        // Shares are zlib compressed
        let decompressed: Data
        do {
            decompressed = try decompressZlib(data)
            print("📂 [\(peerInfo.username)] Decompressed shares: \(data.count) -> \(decompressed.count) bytes")
        } catch {
            print("📂 [\(peerInfo.username)] Failed to decompress shares: \(error)")
            logger.error("Failed to decompress shares: \(error)")
            // Try parsing raw data as fallback
            print("📂 [\(peerInfo.username)] Trying raw data as fallback...")
            decompressed = data
        }

        var offset = 0
        var files: [SharedFile] = []

        // Parse directory count
        guard let dirCount = decompressed.readUInt32(at: offset) else {
            print("📂 [\(peerInfo.username)] Failed to read directory count at offset \(offset)")
            return
        }
        offset += 4
        print("📂 [\(peerInfo.username)] Directory count: \(dirCount)")

        for dirIndex in 0..<dirCount {
            guard let (dirName, dirLen) = decompressed.readString(at: offset) else {
                print("📂 [\(peerInfo.username)] Failed to read dir name at offset \(offset)")
                break
            }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else {
                print("📂 [\(peerInfo.username)] Failed to read file count at offset \(offset)")
                break
            }
            offset += 4

            if dirIndex < 3 {
                print("📂 [\(peerInfo.username)] Dir[\(dirIndex)]: '\(dirName)' with \(fileCount) files")
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
                    duration: duration
                )
                files.append(file)
            }
        }

        print("📂 [\(peerInfo.username)] Parsed \(files.count) files, callback set: \(_onSharesReceived != nil)")
        logger.info("Received \(files.count) shared files from \(self.peerInfo.username)")
        await _onSharesReceived?(files)
    }

    private func handleSearchReply(_ data: Data) async {
        print("🔍 [\(peerInfo.username)] handleSearchReply called with \(data.count) bytes")
        logger.info("handleSearchReply called with \(data.count) bytes")

        // Search replies may be zlib compressed - try decompression first
        var parseData = data
        var wasCompressed = false
        if data.count > 4 {
            do {
                let decompressed = try decompressZlib(data)
                print("🔍 [\(peerInfo.username)] Decompressed from \(data.count) to \(decompressed.count) bytes")
                logger.info("Decompressed search reply from \(data.count) to \(decompressed.count) bytes")
                parseData = decompressed
                wasCompressed = true
            } catch {
                print("🔍 [\(peerInfo.username)] Not compressed or decompression failed: \(error)")
                // Not compressed or decompression failed - try parsing raw data
            }
        }

        let dataPreview = parseData.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("🔍 [\(peerInfo.username)] Parsing data (compressed=\(wasCompressed)): \(dataPreview)")

        guard let parsed = MessageParser.parseSearchReply(parseData) else {
            print("❌ [\(peerInfo.username)] Failed to parse search reply!")
            print("❌ [\(peerInfo.username)] Data starts with: \(parseData.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " "))")
            logger.error("Failed to parse search reply, data starts with: \(parseData.prefix(20).map { String(format: "%02x", $0) }.joined())")
            return
        }

        let results = parsed.files.map { file in
            SearchResult(
                username: parsed.username.isEmpty ? peerUsername : parsed.username,
                filename: file.filename,
                size: file.size,
                bitrate: file.attributes.first { $0.type == 0 }?.value,
                duration: file.attributes.first { $0.type == 1 }?.value,
                freeSlots: parsed.freeSlots,
                uploadSpeed: parsed.uploadSpeed,
                queueLength: parsed.queueLength
            )
        }

        let username = parsed.username.isEmpty ? peerUsername : parsed.username
        print("✅ [\(peerInfo.username)] Parsed \(results.count) search results from \(username) for token \(parsed.token)")
        logger.info("Parsed \(results.count) search results from \(username) for token \(parsed.token)")

        if _onSearchReply != nil {
            print("🔔 [\(peerInfo.username)] Invoking search reply callback for token \(parsed.token)...")
            await _onSearchReply?(parsed.token, results)
            print("✅ [\(peerInfo.username)] Callback invoked successfully")
            logger.info("Search results callback invoked for token \(parsed.token)")
        } else {
            print("⚠️ [\(peerInfo.username)] No search reply callback set!")
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
            logger.error("Failed to parse TransferRequest")
            print("❌ Failed to parse TransferRequest, data: \(data.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " "))")
            return
        }

        let fileSize = parsed.fileSize ?? 0
        if fileSize == 0 && parsed.direction == .upload {
            logger.warning("TransferRequest has zero file size - this may cause issues")
            print("⚠️ TransferRequest: direction=\(parsed.direction) token=\(parsed.token) filename=\(parsed.filename) size=\(fileSize) (WARNING: zero size!)")
        } else {
            print("📨 TransferRequest: direction=\(parsed.direction) token=\(parsed.token) filename=\(parsed.filename) size=\(fileSize)")
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
            print("📨 Dispatching TransferRequest to per-token handler for token \(parsed.token)")
            await tokenHandler(request)
            // Remove the handler after use (one-shot callback)
            _tokenTransferRequestHandlers.removeValue(forKey: parsed.token)
        } else if let globalHandler = _onTransferRequest {
            // Fall back to global handler
            print("📨 Dispatching TransferRequest to global handler")
            await globalHandler(request)
        } else {
            print("⚠️ No handler for TransferRequest token=\(parsed.token)")
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
                print("✅ TransferResponse: token=\(token) allowed=true size=\(size)")
            }
        } else {
            if let (reason, _) = data.readString(at: offset) {
                logger.info("Transfer denied: token=\(token) reason=\(reason)")
                print("🚫 TransferResponse: token=\(token) allowed=false reason=\(reason)")
            }
        }

        await _onTransferResponse?(token, allowed, filesize)
    }

    private func handleQueueDownload(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        let username = self.peerUsername.isEmpty ? "unknown" : self.peerUsername
        logger.info("Queue upload request from \(username): \(filename)")
        print("📥 QueueUpload received from \(self.peerUsername): \(filename)")
        await _onQueueUpload?(self.peerUsername, filename)
    }

    private func handlePlaceInQueue(_ data: Data) async {
        guard let (filename, len) = data.readString(at: 0) else { return }
        guard let place = data.readUInt32(at: len) else { return }
        logger.info("Queue position for \(filename): \(place)")
        print("📊 Queue position for \(filename): \(place)")
    }

    private func handleUploadFailed(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        logger.warning("Upload failed for: \(filename)")
        print("❌ UploadFailed from \(peerUsername): \(filename)")
        // Write to debug log file
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] ❌ UploadFailed from \(peerUsername): \(filename)\n"
        if let logPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("seeleseek_debug.log"),
           let data = logLine.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
        await _onUploadFailed?(filename)
    }

    private func handleUploadDenied(_ data: Data) async {
        guard let (filename, filenameLen) = data.readString(at: 0) else { return }
        let reason = data.readString(at: filenameLen)?.string ?? "Unknown reason"
        logger.warning("Upload denied for \(filename): \(reason)")
        print("🚫 UploadDenied: \(filename) - \(reason)")
        await _onUploadDenied?(filename, reason)
    }

    private func handleFolderContentsRequest(_ data: Data) async {
        var offset = 0

        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let (folder, _) = data.readString(at: offset) else { return }

        logger.info("Folder contents request: \(folder) token=\(token)")
        print("📁 FolderContentsRequest: \(folder) token=\(token)")
        await _onFolderContentsRequest?(token, folder)
    }

    private func handlePlaceInQueueRequest(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        logger.info("Place in queue request for: \(filename)")
        print("📊 PlaceInQueueRequest for: \(filename) from \(self.peerUsername)")
        await _onPlaceInQueueRequest?(self.peerUsername, filename)
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

        guard let fileCount = decompressed.readUInt32(at: offset) else { return }
        offset += 4

        var files: [SharedFile] = []

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

        logger.info("Received folder contents: \(folder) (\(files.count) files)")
        print("📁 FolderContentsReply: \(folder) with \(files.count) files")
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
            print("🗜️ Decompression: data too short (\(data.count) bytes)")
            throw PeerError.decompressionFailed
        }

        // Verify zlib header (first byte should have compression method 8 = deflate)
        let cmf = data[data.startIndex]
        let flg = data[data.startIndex + 1]
        let compressionMethod = cmf & 0x0F
        print("🗜️ Decompression: CMF=0x\(String(format: "%02x", cmf)) FLG=0x\(String(format: "%02x", flg)) method=\(compressionMethod)")

        guard compressionMethod == 8 else {
            print("🗜️ Not zlib format (method != 8), trying raw deflate")
            // Not zlib format, try raw deflate
            return try decompressRawDeflate(data)
        }

        // Strip zlib header (2 bytes) and Adler-32 checksum (4 bytes)
        let deflateData = data.dropFirst(2).dropLast(4)
        print("🗜️ Stripped zlib header/footer: \(data.count) -> \(deflateData.count) bytes")

        let result = try decompressRawDeflate(Data(deflateData))
        print("🗜️ Decompressed: \(deflateData.count) -> \(result.count) bytes")

        // Log first few bytes of decompressed data
        let preview = result.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("🗜️ Decompressed preview: \(preview)")

        return result
    }

    private func decompressRawDeflate(_ data: Data) throws -> Data {
        let decompressed = try data.withUnsafeBytes { sourceBuffer -> Data in
            let sourceSize = data.count
            // Start with a reasonable estimate, expand if needed
            var destinationSize = max(sourceSize * 20, 65536)
            var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)

            var decodedSize = compression_decode_buffer(
                &destinationBuffer,
                destinationSize,
                sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )

            // If output buffer was too small, try with larger buffer
            if decodedSize == 0 || decodedSize == destinationSize {
                destinationSize = sourceSize * 100
                destinationBuffer = [UInt8](repeating: 0, count: destinationSize)
                decodedSize = compression_decode_buffer(
                    &destinationBuffer,
                    destinationSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard decodedSize > 0 else {
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
