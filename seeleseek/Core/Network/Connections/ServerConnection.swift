import Foundation
import Network
import os

actor ServerConnection {
    // MARK: - Types

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    enum ConnectionError: Error, LocalizedError {
        case notConnected
        case connectionFailed(String)
        case loginFailed(String)
        case timeout
        case invalidResponse

        var errorDescription: String? {
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

    // Async stream for messages
    private var messageContinuation: AsyncStream<Data>.Continuation?

    private let logger = Logger(subsystem: "com.seeleseek", category: "ServerConnection")

    // MARK: - Configuration

    static let defaultHost = "server.slsknet.org"
    static let defaultPort: UInt16 = 2242

    // MARK: - Initialization

    init(host: String = defaultHost, port: UInt16 = defaultPort) {
        self.host = host
        self.port = port
    }

    // MARK: - Async Message Stream

    /// Async stream of complete message frames from the server
    nonisolated var messages: AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                await self.setMessageContinuation(continuation)
            }
            continuation.onTermination = { @Sendable _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    private func setMessageContinuation(_ continuation: AsyncStream<Data>.Continuation) {
        messageContinuation = continuation
    }

    private func clearContinuation() {
        messageContinuation = nil
    }

    // MARK: - Public Interface

    func setMessageHandler(_ handler: @escaping (UInt32, Data) async -> Void) {
        self.messageHandler = handler
    }

    func setStateHandler(_ handler: @escaping (State) -> Void) {
        self.stateHandler = handler
    }

    func connect() async throws {
        guard case .disconnected = state else {
            logger.warning("Already connected or connecting")
            return
        }

        updateState(.connecting)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let conn = NWConnection(to: endpoint, using: parameters)
        connection = conn

        return try await withCheckedThrowingContinuation { continuation in
            conn.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                Task {
                    await self.handleStateChange(newState, continuation: continuation)
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        updateState(.disconnected)
    }

    func send(_ data: Data) async throws {
        guard let connection, case .connected = state else {
            throw ConnectionError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func login(username: String, password: String) async throws -> LoginResult {
        let message = MessageBuilder.loginMessage(username: username, password: password)
        try await send(message)

        // Wait for login response
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Set up a temporary handler to catch the login response
                let originalHandler = self.messageHandler
                await self.setMessageHandler { code, payload in
                    if code == ServerMessageCode.login.rawValue {
                        if let result = MessageParser.parseLoginResponse(payload) {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(throwing: ConnectionError.invalidResponse)
                        }
                        // Restore original handler
                        await self.setMessageHandler(originalHandler ?? { _, _ in })
                    }
                }

                // Start receiving if not already
                await self.startReceiving()
            }
        }
    }

    func sendPing() async throws {
        try await send(MessageBuilder.pingMessage())
    }

    func setOnlineStatus(_ status: UserStatus) async throws {
        try await send(MessageBuilder.setOnlineStatusMessage(status: status))
    }

    func setSharedFoldersFiles(folders: UInt32, files: UInt32) async throws {
        try await send(MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files))
    }

    func search(query: String, token: UInt32) async throws {
        try await send(MessageBuilder.fileSearchMessage(token: token, query: query))
    }

    func getRoomList() async throws {
        try await send(MessageBuilder.getRoomListMessage())
    }

    func joinRoom(_ roomName: String) async throws {
        try await send(MessageBuilder.joinRoomMessage(roomName: roomName))
    }

    func leaveRoom(_ roomName: String) async throws {
        try await send(MessageBuilder.leaveRoomMessage(roomName: roomName))
    }

    func sendChatMessage(room: String, message: String) async throws {
        try await send(MessageBuilder.sayInChatRoomMessage(roomName: room, message: message))
    }

    func sendPrivateMessage(to username: String, message: String) async throws {
        try await send(MessageBuilder.privateMessageMessage(username: username, message: message))
    }

    func acknowledgePrivateMessage(id: UInt32) async throws {
        try await send(MessageBuilder.acknowledgePrivateMessageMessage(messageId: id))
    }

    // MARK: - Private Methods

    private func handleStateChange(_ newState: NWConnection.State, continuation: CheckedContinuation<Void, Error>?) {
        switch newState {
        case .ready:
            logger.info("Connected to \(self.host):\(self.port)")
            updateState(.connected)
            continuation?.resume()
            Task { await startReceiving() }

        case .failed(let error):
            logger.error("Connection failed: \(error.localizedDescription)")
            updateState(.failed(error))
            continuation?.resume(throwing: ConnectionError.connectionFailed(error.localizedDescription))

        case .cancelled:
            logger.info("Connection cancelled")
            updateState(.disconnected)

        case .waiting(let error):
            logger.warning("Connection waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    private func startReceiving() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task {
                if let data {
                    await self.handleReceivedData(data)
                }

                if isComplete {
                    await self.disconnect()
                } else if error == nil {
                    await self.startReceiving()
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        receiveBuffer.append(data)

        // Process complete messages
        while let (frame, consumed) = MessageParser.parseFrame(from: receiveBuffer) {
            receiveBuffer.removeFirst(consumed)

            // Build complete message with length prefix and code
            var completeMessage = Data()
            completeMessage.appendUInt32(UInt32(frame.payload.count + 4))
            completeMessage.appendUInt32(frame.code)
            completeMessage.append(frame.payload)

            // Yield to async stream
            messageContinuation?.yield(completeMessage)

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
    static func == (lhs: ServerConnection.State, rhs: ServerConnection.State) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): true
        case (.connecting, .connecting): true
        case (.connected, .connected): true
        case (.failed, .failed): true
        default: false
        }
    }
}
