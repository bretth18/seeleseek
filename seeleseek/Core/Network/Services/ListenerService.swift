import Foundation
import Network
import os

/// Listens for incoming peer connections
actor ListenerService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ListenerService")

    private var listener: NWListener?
    private var listeningPort: UInt16 = 0
    private var obfuscatedPort: UInt16 = 0

    // Callback for new connections
    private var _onNewConnection: ((NWConnection, Bool) async -> Void)?

    func setOnNewConnection(_ handler: @escaping (NWConnection, Bool) async -> Void) {
        _onNewConnection = handler
    }

    // MARK: - Port Configuration

    /// Default port range for SoulSeek
    static let defaultPortRange: ClosedRange<UInt16> = 2234...2240
    static let obfuscatedPortOffset: UInt16 = 1

    // MARK: - Public Interface

    var port: UInt16 { listeningPort }
    var obfuscated: UInt16 { obfuscatedPort }

    func start(preferredPort: UInt16? = nil) async throws -> (port: UInt16, obfuscatedPort: UInt16) {
        print("🔊 ListenerService.start() called")

        // Try preferred port first, then scan for available port
        let portsToTry: [UInt16]
        if let preferred = preferredPort {
            portsToTry = [preferred] + Array(Self.defaultPortRange).filter { $0 != preferred }
        } else {
            portsToTry = Array(Self.defaultPortRange)
        }

        print("🔊 Trying ports: \(portsToTry)")

        for port in portsToTry {
            do {
                print("🔊 Trying port \(port)...")
                try await startListener(on: port)
                listeningPort = port
                obfuscatedPort = port + Self.obfuscatedPortOffset

                // Also start obfuscated listener
                try? await startObfuscatedListener(on: obfuscatedPort)

                logger.info("Listening on port \(port) (obfuscated: \(self.obfuscatedPort))")
                print("🟢 LISTENER STARTED on port \(port) (obfuscated: \(self.obfuscatedPort))")
                return (port, obfuscatedPort)
            } catch {
                logger.debug("Port \(port) unavailable: \(error.localizedDescription)")
                print("🟠 Port \(port) unavailable: \(error.localizedDescription)")
                continue
            }
        }

        print("🔴 LISTENER FAILED - no available port")
        throw ListenerError.noAvailablePort
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listeningPort = 0
        obfuscatedPort = 0
        logger.info("Listener stopped")
    }

    // MARK: - Private Methods

    private func startListener(on port: UInt16) async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let newListener = try NWListener(using: parameters)

        // Use nonisolated(unsafe) for the flag since NWListener callbacks are on a different queue
        nonisolated(unsafe) var hasResumed = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            newListener.stateUpdateHandler = { [weak self] state in
                print("🔊 Listener state on port \(port): \(state)")
                guard !hasResumed else { return }

                switch state {
                case .ready:
                    hasResumed = true
                    continuation.resume()
                case .failed(let error):
                    hasResumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                print("🔵 NEW INCOMING CONNECTION on port \(port) from \(connection.endpoint)")
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
        // For now, we'll handle them similarly
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let obfuscatedListener = try NWListener(using: parameters)

        obfuscatedListener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleNewConnection(connection, obfuscated: true)
            }
        }

        obfuscatedListener.start(queue: .global(qos: .userInitiated))
    }

    private func handleNewConnection(_ connection: NWConnection, obfuscated: Bool) async {
        logger.info("New \(obfuscated ? "obfuscated " : "")connection from \(String(describing: connection.endpoint))")
        print("🔵 INCOMING CONNECTION from \(connection.endpoint) (obfuscated: \(obfuscated))")

        if _onNewConnection != nil {
            await _onNewConnection?(connection, obfuscated)
        } else {
            print("⚠️ No connection handler set!")
        }
    }

    // MARK: - Port Scanning

    /// Scans for SoulSeek clients on local network
    static func scanLocalNetwork() async -> [DiscoveredPeer] {
        // This would use Bonjour/mDNS or port scanning
        // For now, return empty - real implementation would scan
        return []
    }
}

// MARK: - Types

enum ListenerError: Error, LocalizedError {
    case noAvailablePort
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAvailablePort:
            return "No available port in range \(ListenerService.defaultPortRange)"
        case .bindFailed(let reason):
            return "Failed to bind: \(reason)"
        }
    }
}

struct DiscoveredPeer {
    let address: String
    let port: UInt16
    let username: String?
}
