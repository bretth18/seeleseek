import Foundation
import Network
import os
import Synchronization

/// Listens for incoming peer connections
public actor ListenerService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ListenerService")

    private var listener: NWListener?
    private var obfuscatedListener: NWListener?
    private var listeningPort: UInt16 = 0
    private var obfuscatedPort: UInt16 = 0

    // Stream for new connections — recreated on each start() for clean reconnect lifecycle
    public private(set) var newConnections: AsyncStream<(NWConnection, Bool)>
    private var connectionContinuation: AsyncStream<(NWConnection, Bool)>.Continuation

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: (NWConnection, Bool).self)
        self.newConnections = stream
        self.connectionContinuation = continuation
    }

    // MARK: - Port Configuration

    /// Default port range for SoulSeek
    static let defaultPortRange: ClosedRange<UInt16> = 2234...2240
    static let obfuscatedPortOffset: UInt16 = 1

    // MARK: - Public Interface

    public var port: UInt16 { listeningPort }
    public var obfuscated: UInt16 { obfuscatedPort }

    /// True iff the obfuscated listener is currently retained and running.
    /// Exposed for regression tests of the retention fix.
    internal var obfuscatedListenerIsActive: Bool { obfuscatedListener != nil }

    /// Start the listener.
    ///
    /// - Parameters:
    ///   - preferredPort: Try this port first. If nil, scan `defaultPortRange`.
    ///   - fallbackToDefaultRange: When true (production default), falls back to
    ///     scanning `defaultPortRange` if `preferredPort` is busy. Tests pass
    ///     `false` with a high-entropy random port so concurrent test suites
    ///     don't contend on the fixed 2234-2240 range.
    public func start(
        preferredPort: UInt16? = nil,
        fallbackToDefaultRange: Bool = true
    ) async throws -> (port: UInt16, obfuscatedPort: UInt16) {
        logger.info("ListenerService.start() called")

        // Try preferred port first, then scan for available port
        let portsToTry: [UInt16]
        if let preferred = preferredPort {
            if fallbackToDefaultRange {
                portsToTry = [preferred] + Array(Self.defaultPortRange).filter { $0 != preferred }
            } else {
                portsToTry = [preferred]
            }
        } else {
            portsToTry = Array(Self.defaultPortRange)
        }

        logger.debug("Trying ports: \(portsToTry)")

        for port in portsToTry {
            do {
                logger.debug("Trying port \(port)...")
                try await startListener(on: port)
                listeningPort = port
                obfuscatedPort = port + Self.obfuscatedPortOffset

                do {
                    try await startObfuscatedListener(on: obfuscatedPort)
                } catch {
                    // Obfuscated port unavailable for this pair — tear down the
                    // main listener and try the next port.
                    logger.debug("Obfuscated port \(self.obfuscatedPort) unavailable: \(error.localizedDescription); trying next pair")
                    listener?.cancel()
                    listener = nil
                    listeningPort = 0
                    obfuscatedPort = 0
                    continue
                }

                logger.info("Listening on port \(port) (obfuscated: \(self.obfuscatedPort))")
                return (port, obfuscatedPort)
            } catch {
                logger.debug("Port \(port) unavailable: \(error.localizedDescription)")
                continue
            }
        }

        logger.error("Listener failed - no available port")
        throw ListenerError.noAvailablePort
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        obfuscatedListener?.cancel()
        obfuscatedListener = nil
        listeningPort = 0
        obfuscatedPort = 0
        // Finish the old stream and create a fresh one for next start()
        connectionContinuation.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: (NWConnection, Bool).self)
        newConnections = stream
        connectionContinuation = continuation
        logger.info("Listener stopped")
    }

    // MARK: - Private Methods

    private func startListener(on port: UInt16) async throws {
        // Force IPv4 only (like Nicotine+) - many routers only forward IPv4
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        // Require IPv4 by setting protocol options
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true  // Disable Nagle's algorithm for lower latency
        }

        // Explicitly bind to IPv4 any address
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.bindFailed("Invalid port \(port)")
        }

        // Force IPv4 binding
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: nwPort
        )

        let newListener = try NWListener(using: parameters)
        logger.debug("Created IPv4 listener for port \(port)")

        let hasResumed = Mutex(false)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            newListener.stateUpdateHandler = { state in
                // logger state changes handled via NWListener callbacks

                switch state {
                case .ready:
                    guard hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume()
                case .failed(let error):
                    guard hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                // Incoming connection logged in handleNewConnection
                Task {
                    await self?.handleNewConnection(connection, obfuscated: false)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
        }

        self.listener = newListener
    }

    private func startObfuscatedListener(on port: UInt16) async throws {
        // Obfuscated connections use a slightly different protocol
        // Force IPv4 only (like Nicotine+)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.bindFailed("Invalid obfuscated port \(port)")
        }

        // Force IPv4 binding
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: nwPort
        )

        let newListener = try NWListener(using: parameters)
        let hasResumed = Mutex(false)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume()
                case .failed(let error):
                    let shouldResume = hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    })
                    if shouldResume {
                        continuation.resume(throwing: error)
                    } else {
                        Task { [weak self] in
                            await self?.handleObfuscatedListenerFailure(error)
                        }
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handleNewConnection(connection, obfuscated: true)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
        }

        self.obfuscatedListener = newListener
    }

    private func handleObfuscatedListenerFailure(_ error: Error) {
        logger.error("Obfuscated listener failed: \(error.localizedDescription)")
        obfuscatedListener?.cancel()
        obfuscatedListener = nil
    }

    private func handleNewConnection(_ connection: NWConnection, obfuscated: Bool) {
        logger.info("Incoming connection from \(String(describing: connection.endpoint)) (obfuscated: \(obfuscated))")
        connectionContinuation.yield((connection, obfuscated))
    }
}

// MARK: - Types

enum ListenerError: Error, LocalizedError {
    case noAvailablePort
    case bindFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAvailablePort:
            return "No available port in range \(ListenerService.defaultPortRange)"
        case .bindFailed(let reason):
            return "Failed to bind: \(reason)"
        }
    }
}

