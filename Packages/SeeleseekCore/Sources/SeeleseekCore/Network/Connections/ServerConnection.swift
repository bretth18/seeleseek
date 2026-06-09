import Foundation
import Network
import os

public actor ServerConnection {
    // MARK: - Types

    public enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    public enum ConnectionError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case loginFailed(String)
        case timeout
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .notConnected: "Not connected to server"
            case .connectionFailed(let reason): "Connection failed: \(reason)"
            case .loginFailed(let reason): "Login failed: \(reason)"
            case .timeout: "Connection timed out"
            case .invalidResponse: "Invalid server response"
            }
        }
    }

    // MARK: - Properties

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    private(set) var state: State = .disconnected

    private var messageHandler: ((UInt32, Data) async -> Void)?
    private var stateHandler: ((State) -> Void)?

    // Connection continuation - stored as property to ensure single-resume safety
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // Bounds the connect attempt: NWConnection can sit in `.waiting`
    // indefinitely (e.g. connection refused keeps retrying on path
    // changes and never reaches `.failed`), which would otherwise hang
    // the caller forever and leave `state` stuck at `.connecting`.
    private var connectTimeoutTask: Task<Void, Never>?
    private static let connectTimeoutSeconds: Int = 15

    // Async stream for messages
    private var messageContinuation: AsyncStream<Data>.Continuation?
    // Frames parsed before a consumer registers (the stream's continuation
    // is handed over via an actor hop, so there's a window after `.ready`
    // where messages would otherwise be dropped). Flushed on registration.
    private var pendingMessages: [Data] = []
    private static let maxPendingMessages = 2048
    private var streamGeneration = 0

    private let logger = Logger(subsystem: "com.seeleseek", category: "ServerConnection")

    // MARK: - Configuration

    public static let defaultHost = "server.slsknet.org"
    public static let defaultPort: UInt16 = 2242

    // MARK: - Initialization

    public init(host: String = defaultHost, port: UInt16 = defaultPort) {
        self.host = host
        self.port = port
    }

    // MARK: - Async Message Stream

    /// Async stream of complete message frames from the server
    public nonisolated var messages: AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                await self.setMessageContinuation(continuation)
            }
        }
    }

    private func setMessageContinuation(_ continuation: AsyncStream<Data>.Continuation) {
        // A second consumer replaces the first; finish the old stream so its
        // `for await` loop exits instead of silently going quiet.
        messageContinuation?.finish()
        streamGeneration += 1
        let generation = streamGeneration
        messageContinuation = continuation
        continuation.onTermination = { @Sendable _ in
            Task { await self.clearContinuation(ifGeneration: generation) }
        }
        // Flush frames that arrived before the consumer registered.
        for frame in pendingMessages {
            continuation.yield(frame)
        }
        pendingMessages.removeAll()
    }

    private func clearContinuation(ifGeneration generation: Int) {
        // A stale stream's termination must not tear down a newer stream.
        guard generation == streamGeneration else { return }
        messageContinuation = nil
    }

    // MARK: - Public Interface

    public func setMessageHandler(_ handler: @escaping (UInt32, Data) async -> Void) async {
        self.messageHandler = handler
    }

    public func setStateHandler(_ handler: @escaping (State) -> Void) {
        self.stateHandler = handler
    }

    public func connect() async throws {
        guard case .disconnected = state else {
            logger.warning("Already connected or connecting")
            return
        }

        updateState(.connecting)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Enable TCP keepalive to detect silent connection deaths quickly
        // Without this, a dead connection (NAT timeout, ISP reset) can go undetected for hours
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveInterval = 60  // probe every 60s after idle
            tcpOptions.keepaliveCount = 3      // give up after 3 missed probes
            tcpOptions.keepaliveIdle = 120     // start probing after 2 min idle
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            updateState(.disconnected)
            throw ConnectionError.connectionFailed("Invalid port: \(port)")
        }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let conn = NWConnection(to: endpoint, using: parameters)
        connection = conn

        return try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.connectTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.connectTimeoutSeconds))
                guard !Task.isCancelled else { return }
                await self?.handleConnectTimeout()
            }
            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task {
                    await self.handleStateChange(newState)
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Resume the pending connect continuation exactly once and stop the
    /// connect timeout. Safe to call from any path; no-ops when nothing
    /// is pending.
    private func resumeConnectContinuation(throwing error: Error?) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func handleConnectTimeout() {
        guard connectContinuation != nil else { return }
        logger.error("Connect to \(self.host):\(self.port) timed out after \(Self.connectTimeoutSeconds)s")
        resumeConnectContinuation(throwing: ConnectionError.timeout)
        // Tear down so state returns to .disconnected and a future
        // connect() isn't no-op'd by the .connecting guard.
        disconnect()
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        // Resume any pending connect continuation before state change
        resumeConnectContinuation(throwing: ConnectionError.notConnected)
        // Finish the async message stream so NetworkClient's `for await` loop exits
        messageContinuation?.finish()
        messageContinuation = nil
        pendingMessages.removeAll()
        updateState(.disconnected)
    }

    public func send(_ data: Data) async throws {
        guard let connection, case .connected = state else {
            throw ConnectionError.notConnected
        }

        logger.debug("Sending \(data.count) bytes")

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.error("Send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    self?.logger.debug("Send completed")
                    continuation.resume()
                }
            })
        }
    }

    public func sendPing() async throws {
        try await send(MessageBuilder.pingMessage())
    }

    public func setOnlineStatus(_ status: UserStatus) async throws {
        try await send(MessageBuilder.setOnlineStatusMessage(status: status))
    }

    public func setSharedFoldersFiles(folders: UInt32, files: UInt32) async throws {
        try await send(MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files))
    }

    public func search(query: String, token: UInt32) async throws {
        try await send(MessageBuilder.fileSearchMessage(token: token, query: query))
    }

    public func getRoomList() async throws {
        try await send(MessageBuilder.getRoomListMessage())
    }

    public func joinRoom(_ roomName: String) async throws {
        try await send(MessageBuilder.joinRoomMessage(roomName: roomName))
    }

    public func leaveRoom(_ roomName: String) async throws {
        try await send(MessageBuilder.leaveRoomMessage(roomName: roomName))
    }

    public func sendChatMessage(room: String, message: String) async throws {
        try await send(MessageBuilder.sayInChatRoomMessage(roomName: room, message: message))
    }

    public func sendPrivateMessage(to username: String, message: String) async throws {
        try await send(MessageBuilder.privateMessageMessage(username: username, message: message))
    }

    public func acknowledgePrivateMessage(id: UInt32) async throws {
        try await send(MessageBuilder.acknowledgePrivateMessageMessage(messageId: id))
    }

    // MARK: - Private Methods

    private func handleStateChange(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            logger.info("Connected to \(self.host):\(self.port)")
            updateState(.connected)
            resumeConnectContinuation(throwing: nil)
            Task { await startReceiving() }

        case .failed(let error):
            logger.error("Connection failed: \(error.localizedDescription)")
            resumeConnectContinuation(throwing: ConnectionError.connectionFailed(error.localizedDescription))
            // Clean up and end the async stream so NetworkClient detects the loss
            disconnect()

        case .cancelled:
            logger.info("Connection cancelled")
            updateState(.disconnected)
            // If cancelled during connect, resume with error
            resumeConnectContinuation(throwing: ConnectionError.connectionFailed("Connection cancelled"))

        case .waiting(let error):
            logger.warning("Connection waiting: \(error.localizedDescription)")
            // TCP-level refusals/unreachability park NWConnection in .waiting
            // (it retries on path changes and never reaches .failed). Treat
            // the definitive POSIX codes as failures so connect() doesn't
            // hang until the timeout: ENOMEM, ENETUNREACH, ENOTCONN,
            // ETIMEDOUT, ECONNREFUSED, EHOSTUNREACH.
            if case .posix(let posixError) = error {
                let code = posixError.rawValue
                if code == 12 || code == 51 || code == 57 || code == 60 || code == 61 || code == 65 {
                    logger.error("Server connection definitive failure: POSIX \(code)")
                    resumeConnectContinuation(throwing: ConnectionError.connectionFailed(error.localizedDescription))
                    disconnect()
                }
            }

        default:
            break
        }
    }

    private func startReceiving() async {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task {
                if let data {
                    await self.handleReceivedData(data)
                }

                if isComplete || error != nil {
                    await self.disconnect()
                } else {
                    await self.startReceiving()
                }
            }
        }
    }

    // MARK: - Security Constants
    /// Maximum receive buffer size to prevent memory exhaustion
    /// Server messages are typically small, but room lists can be large
    private static let maxReceiveBufferSize = 50 * 1024 * 1024  // 50MB

    private func handleReceivedData(_ data: Data) async {
        receiveBuffer.append(data)
        logger.debug("Received \(data.count) bytes, buffer now \(self.receiveBuffer.count) bytes")

        // SECURITY: Check buffer size to prevent memory exhaustion
        guard receiveBuffer.count <= Self.maxReceiveBufferSize else {
            logger.error("Receive buffer exceeded limit, disconnecting")
            receiveBuffer.removeAll()
            disconnect()
            return
        }

        // Process complete messages
        while let (frame, consumed) = MessageParser.parseFrame(from: receiveBuffer) {
            receiveBuffer.removeFirst(consumed)

            // Per-frame trace — .debug to avoid duplicating the same
            // firehose already emitted by ServerMessageHandler.
            logger.debug("Parsed message: code=\(frame.code) payload=\(frame.payload.count) bytes")

            // Build complete message with length prefix and code
            var completeMessage = Data()
            completeMessage.appendUInt32(UInt32(frame.payload.count + 4))
            completeMessage.appendUInt32(frame.code)
            completeMessage.append(frame.payload)

            // Yield to async stream; if the consumer hasn't registered its
            // continuation yet (actor hop in `messages`), buffer the frame
            // so a fast login response isn't dropped.
            if let messageContinuation {
                messageContinuation.yield(completeMessage)
            } else if pendingMessages.count < Self.maxPendingMessages {
                pendingMessages.append(completeMessage)
            }

            // Also call legacy handler if set
            await messageHandler?(frame.code, frame.payload)
        }
    }

    private func updateState(_ newState: State) {
        state = newState
        stateHandler?(newState)
    }
}

// MARK: - Convenience Extensions

extension ServerConnection.State: Equatable {
    public static func == (lhs: ServerConnection.State, rhs: ServerConnection.State) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): true
        case (.connecting, .connecting): true
        case (.connected, .connected): true
        case (.failed, .failed): true
        default: false
        }
    }
}
