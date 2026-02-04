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

    let peerInfo: PeerInfo
    let connectionType: ConnectionType
    let isIncoming: Bool
    let token: UInt32

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private(set) var state: State = .disconnected

    // Callbacks
    private var _onStateChanged: ((State) async -> Void)?
    private var _onMessage: ((UInt32, Data) async -> Void)?
    private var _onSharesReceived: (([SharedFile]) async -> Void)?
    private var _onSearchReply: ((UInt32, [SearchResult]) async -> Void)?  // (token, results)
    private var _onTransferRequest: ((TransferRequest) async -> Void)?
    private var _onUsernameDiscovered: ((String, UInt32) async -> Void)?  // (username, token)

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

    func setOnUsernameDiscovered(_ handler: @escaping (String, UInt32) async -> Void) {
        _onUsernameDiscovered = handler
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

    init(peerInfo: PeerInfo, type: ConnectionType = .peer, token: UInt32 = 0, isIncoming: Bool = false) {
        self.peerInfo = peerInfo
        self.connectionType = type
        self.token = token
        self.isIncoming = isIncoming
    }

    init(connection: NWConnection, isIncoming: Bool = true) {
        // For incoming connections, we don't know the peer info yet
        self.peerInfo = PeerInfo(username: "", ip: "", port: 0)
        self.connectionType = .peer
        self.token = 0
        self.isIncoming = isIncoming
        self.connection = connection
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

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        // Note: We don't bind to the listen port for outgoing connections.
        // Binding to the same port as the listener can cause conflicts.
        // NAT hole punching for TCP requires a different approach (simultaneous open)
        // which is complex and rarely needed since most peers use ConnectToPeer fallback.

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn

        return try await withCheckedThrowingContinuation { continuation in
            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task {
                    await self.handleConnectionState(newState, continuation: continuation)
                }
            }

            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    func accept() async throws {
        guard let connection, isIncoming else { return }

        updateState(.connecting)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task {
                    await self.handleConnectionState(newState, continuation: continuation)
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
    }

    // MARK: - Handshake

    func sendPeerInit(username: String) async throws {
        updateState(.handshaking)

        let message = MessageBuilder.peerInitMessage(
            username: username,
            connectionType: connectionType.rawValue,
            token: token
        )

        try await send(message)
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
        try await send(message)
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

    // MARK: - Private Methods

    private func handleConnectionState(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>?) {
        switch state {
        case .ready:
            print("🟢 PEER CONNECTED: \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            logger.info("Connected to peer \(self.peerInfo.username) at \(self.peerInfo.ip):\(self.peerInfo.port)")
            connectedAt = Date()
            updateState(.connected)
            // Start receiving BEFORE resuming continuation to ensure we're ready for data
            startReceiving()
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
            // Don't resume continuation on cancel - it might have already been resumed

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
                if let error {
                    print("📡 [\(await self.peerInfo.username)] Receive error: \(error.localizedDescription)")
                }

                if let data {
                    await self.handleReceivedData(data)
                } else {
                    print("📡 [\(await self.peerInfo.username)] No data received")
                }

                if isComplete {
                    print("📡 [\(await self.peerInfo.username)] Connection complete, disconnecting")
                    await self.disconnect()
                } else if error == nil {
                    await self.startReceiving()
                } else {
                    print("📡 [\(await self.peerInfo.username)] Not continuing receive due to error")
                }
            }
        }
    }

    // Track if we've completed handshake
    private var handshakeComplete = false
    private var peerUsername: String = ""

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
                print("📥 [\(peerInfo.username)] Peer message: code=\(code) (\(PeerMessageCode(rawValue: UInt8(code))?.description ?? "unknown")) length=\(length)")
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
            // Firewall pierce - extract token
            if let token = payload.readUInt32(at: 0) {
                logger.info("PierceFirewall with token: \(token)")
            }
            handshakeComplete = true

        case PeerMessageCode.peerInit.rawValue:
            // Peer init - extract username, type, token
            var offset = 0

            if let (username, usernameLen) = payload.readString(at: offset) {
                offset += usernameLen
                peerUsername = username

                var peerToken: UInt32 = 0
                if let (connType, typeLen) = payload.readString(at: offset) {
                    offset += typeLen

                    if let token = payload.readUInt32(at: offset) {
                        peerToken = token
                        logger.info("PeerInit from \(username) type=\(connType) token=\(token)")
                    }
                }

                // Notify the pool of the discovered username
                await _onUsernameDiscovered?(username, peerToken)
            }
            handshakeComplete = true

        default:
            logger.warning("Unknown init message code: \(code)")
            // Assume handshake is done and this might be a peer message
            handshakeComplete = true
        }
    }

    private func handlePeerMessage(code: UInt32, payload: Data) async {
        logger.debug("Peer message: code=\(code) length=\(payload.count)")

        // Handle based on message code
        switch code {
        case UInt32(PeerMessageCode.sharesReply.rawValue):
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

        default:
            logger.debug("Unhandled peer message code: \(code)")
            await _onMessage?(code, payload)
        }
    }

    private func handleSharesReply(_ data: Data) async {
        // Shares are zlib compressed
        guard let decompressed = try? decompressZlib(data) else {
            logger.error("Failed to decompress shares")
            return
        }

        var offset = 0
        var files: [SharedFile] = []

        // Parse directory count
        guard let dirCount = decompressed.readUInt32(at: offset) else { return }
        offset += 4

        for _ in 0..<dirCount {
            guard let (dirName, dirLen) = decompressed.readString(at: offset) else { break }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else { break }
            offset += 4

            for _ in 0..<fileCount {
                guard decompressed.readByte(at: offset) != nil else { break }
                offset += 1

                guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                offset += filenameLen

                guard let size = decompressed.readUInt64(at: offset) else { break }
                offset += 8

                guard let (ext, extLen) = decompressed.readString(at: offset) else { break }
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

        guard let (description, descLen) = data.readString(at: offset) else { return }
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
        guard let parsed = MessageParser.parseTransferRequest(data) else { return }

        let request = TransferRequest(
            direction: parsed.direction,
            token: parsed.token,
            filename: parsed.filename,
            size: parsed.fileSize ?? 0,
            username: peerInfo.username
        )

        await _onTransferRequest?(request)
    }

    private func handleTransferReply(_ data: Data) async {
        var offset = 0

        guard let token = data.readUInt32(at: offset) else { return }
        offset += 4

        guard let allowed = data.readBool(at: offset) else { return }
        offset += 1

        if allowed {
            guard let filesize = data.readUInt64(at: offset) else { return }
            logger.info("Transfer allowed: token=\(token) size=\(filesize)")
        } else {
            if let (reason, _) = data.readString(at: offset) {
                logger.info("Transfer denied: token=\(token) reason=\(reason)")
            }
        }
    }

    private func handleQueueDownload(_ data: Data) async {
        guard let (filename, _) = data.readString(at: 0) else { return }
        logger.info("Queue download request: \(filename)")
    }

    private func handlePlaceInQueue(_ data: Data) async {
        guard let (filename, len) = data.readString(at: 0) else { return }
        guard let place = data.readUInt32(at: len) else { return }
        logger.info("Queue position for \(filename): \(place)")
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
