import Foundation
import Network
import os

/// Manages multiple peer connections with statistics tracking
@Observable
@MainActor
final class PeerConnectionPool {
    private let logger = Logger(subsystem: "com.seeleseek", category: "PeerConnectionPool")

    // MARK: - Connection Tracking

    private(set) var connections: [String: PeerConnectionInfo] = [:]
    private(set) var pendingConnections: [UInt32: PendingConnection] = [:]

    // CRITICAL: Store actual PeerConnection objects to keep them alive!
    // Without this, connections get deallocated immediately after creation.
    private var activeConnections_: [String: PeerConnection] = [:]

    // MARK: - Statistics

    private(set) var totalBytesReceived: UInt64 = 0
    private(set) var totalBytesSent: UInt64 = 0
    private(set) var totalConnections: UInt32 = 0
    private(set) var activeConnections: Int = 0

    // Speed tracking
    private(set) var currentDownloadSpeed: Double = 0
    private(set) var currentUploadSpeed: Double = 0
    private(set) var speedHistory: [SpeedSample] = []
    private var lastSpeedCheck = Date()
    private var lastBytesReceived: UInt64 = 0
    private var lastBytesSent: UInt64 = 0

    // Geographic distribution (when available)
    private(set) var peerLocations: [PeerLocation] = []

    // MARK: - Callbacks

    var onSearchResults: (([SearchResult]) -> Void)?
    var onSharesReceived: ((String, [SharedFile]) -> Void)?
    var onTransferRequest: ((TransferRequest) -> Void)?

    // MARK: - Configuration

    let maxConnections = 50
    let connectionTimeout: TimeInterval = 30

    // MARK: - Types

    struct PeerConnectionInfo: Identifiable {
        let id: String
        let username: String
        let ip: String
        let port: Int
        var state: PeerConnection.State
        var connectionType: PeerConnection.ConnectionType
        var bytesReceived: UInt64 = 0
        var bytesSent: UInt64 = 0
        var connectedAt: Date?
        var lastActivity: Date?
        var currentSpeed: Double = 0
    }

    struct PendingConnection {
        let username: String
        let token: UInt32
        let timestamp: Date
        var attempts: Int = 0
    }

    struct SpeedSample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let downloadSpeed: Double
        let uploadSpeed: Double
    }

    struct PeerLocation: Identifiable {
        let id = UUID()
        let username: String
        let country: String
        let latitude: Double
        let longitude: Double
    }

    // MARK: - Initialization

    init() {
        // Start speed tracking timer
        startSpeedTracking()
    }

    // MARK: - Configuration

    // MARK: - Connection Management

    func connect(to username: String, ip: String, port: Int, token: UInt32) async throws -> PeerConnection {
        let peerInfo = PeerConnection.PeerInfo(username: username, ip: ip, port: port)
        let connection = PeerConnection(peerInfo: peerInfo, token: token)

        // Set up callbacks BEFORE connecting to avoid race condition where we
        // start receiving data before callbacks are ready
        await setupCallbacks(for: connection, username: username)

        try await connection.connect()

        let connectionId = "\(username)-\(token)"
        let info = PeerConnectionInfo(
            id: connectionId,
            username: username,
            ip: ip,
            port: port,
            state: .connected,
            connectionType: .peer,
            connectedAt: Date()
        )
        connections[info.id] = info

        // CRITICAL: Store the actual PeerConnection to keep it alive!
        activeConnections_[connectionId] = connection

        activeConnections = connections.count
        totalConnections += 1

        logger.info("Connected to peer \(username) at \(ip):\(port)")
        print("🟢 OUTGOING CONNECTION stored: \(connectionId)")

        // Log to activity feed
        ActivityLog.shared.logPeerConnected(username: username, ip: ip)

        return connection
    }

    func acceptIncoming(_ nwConnection: NWConnection, obfuscated: Bool) async throws -> PeerConnection {
        let connection = PeerConnection(connection: nwConnection, isIncoming: true)

        try await connection.accept()

        // We'll know the username after handshake
        logger.info("Accepted incoming \(obfuscated ? "obfuscated " : "")connection")

        return connection
    }

    /// Handle an incoming connection from the listener service
    func handleIncomingConnection(_ nwConnection: NWConnection) async {
        do {
            let connection = try await acceptIncoming(nwConnection, obfuscated: false)

            let connectionId = "incoming-\(UUID().uuidString.prefix(8))"

            // Set up ALL callbacks for the incoming connection - this is critical for receiving search results!
            await connection.setOnStateChanged { [weak self, connectionId] state in
                await MainActor.run {
                    self?.logger.info("Incoming connection \(connectionId) state changed: \(String(describing: state))")
                    print("🔄 Connection \(connectionId) state: \(state)")
                    if let key = self?.connections.keys.first(where: { $0 == connectionId }) {
                        self?.connections[key]?.state = state
                    }
                    // Clean up disconnected connections
                    if case .disconnected = state {
                        self?.connections.removeValue(forKey: connectionId)
                        self?.activeConnections_.removeValue(forKey: connectionId)
                        self?.activeConnections = self?.connections.count ?? 0
                        print("🔴 Connection \(connectionId) removed (disconnected)")
                    }
                }
            }

            // IMPORTANT: Set up search reply callback so we receive search results
            await connection.setOnSearchReply { [weak self] results in
                await MainActor.run {
                    print("🔴 SEARCH RESULTS: \(results.count) from incoming connection")
                    self?.logger.info("Received \(results.count) search results from incoming connection")
                    self?.onSearchResults?(results)
                }
            }

            await connection.setOnSharesReceived { [weak self] files in
                await MainActor.run {
                    self?.onSharesReceived?("unknown", files)
                }
            }

            await connection.setOnTransferRequest { [weak self] request in
                await MainActor.run {
                    self?.onTransferRequest?(request)
                }
            }

            // Track the connection (username will be determined after handshake)
            let info = PeerConnectionInfo(
                id: connectionId,
                username: "unknown",
                ip: String(describing: nwConnection.endpoint),
                port: 0,
                state: .connected,
                connectionType: .peer,
                connectedAt: Date()
            )
            connections[info.id] = info

            // CRITICAL: Store the actual PeerConnection to keep it alive!
            activeConnections_[connectionId] = connection

            activeConnections = connections.count
            totalConnections += 1

            logger.info("Incoming connection accepted and callbacks configured")
            print("🟢 INCOMING CONNECTION stored: \(connectionId)")
        } catch {
            logger.error("Failed to handle incoming connection: \(error.localizedDescription)")
        }
    }

    func disconnect(username: String) async {
        let keysToRemove = connections.keys.filter { $0.hasPrefix("\(username)-") }
        for key in keysToRemove {
            connections.removeValue(forKey: key)
            if let conn = activeConnections_.removeValue(forKey: key) {
                await conn.disconnect()
            }
        }
        activeConnections = connections.count
    }

    func disconnectAll() async {
        for (_, conn) in activeConnections_ {
            await conn.disconnect()
        }
        activeConnections_.removeAll()
        connections.removeAll()
        pendingConnections.removeAll()
        activeConnections = 0
    }

    /// Get an active connection by ID
    func getConnection(_ id: String) -> PeerConnection? {
        activeConnections_[id]
    }

    /// Get an active connection by username (first match)
    func getConnectionForUser(_ username: String) -> PeerConnection? {
        if let key = activeConnections_.keys.first(where: { $0.hasPrefix("\(username)-") }) {
            return activeConnections_[key]
        }
        return nil
    }

    // MARK: - Pending Connections

    func addPendingConnection(username: String, token: UInt32) {
        pendingConnections[token] = PendingConnection(
            username: username,
            token: token,
            timestamp: Date()
        )
    }

    func resolvePendingConnection(token: UInt32) -> PendingConnection? {
        return pendingConnections.removeValue(forKey: token)
    }

    func cleanupStaleConnections() {
        let timeout = Date().addingTimeInterval(-connectionTimeout)

        // Remove stale pending connections
        pendingConnections = pendingConnections.filter { $0.value.timestamp > timeout }

        // Find stale connection IDs
        let staleIds = connections.filter { info in
            if let lastActivity = info.value.lastActivity {
                return lastActivity <= timeout
            }
            return false
        }.keys

        // Remove stale active connections and their PeerConnection objects
        for id in staleIds {
            connections.removeValue(forKey: id)
            activeConnections_.removeValue(forKey: id)
            logger.debug("Cleaned up stale connection: \(id)")
        }

        activeConnections = connections.count
    }

    // MARK: - Statistics

    func updateStatistics(from connection: PeerConnection) async {
        let received = await connection.bytesReceived
        let sent = await connection.bytesSent

        totalBytesReceived += received
        totalBytesSent += sent

        // Update connection info
        if let username = await connection.peerInfo.username as String?,
           let key = connections.keys.first(where: { $0.hasPrefix("\(username)-") }) {
            connections[key]?.bytesReceived = received
            connections[key]?.bytesSent = sent
            connections[key]?.lastActivity = await connection.lastActivityAt
        }
    }

    private func startSpeedTracking() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(1))

                let now = Date()
                let elapsed = now.timeIntervalSince(lastSpeedCheck)

                if elapsed > 0 {
                    let downloadDelta = Double(totalBytesReceived - lastBytesReceived)
                    let uploadDelta = Double(totalBytesSent - lastBytesSent)

                    currentDownloadSpeed = downloadDelta / elapsed
                    currentUploadSpeed = uploadDelta / elapsed

                    let sample = SpeedSample(
                        timestamp: now,
                        downloadSpeed: currentDownloadSpeed,
                        uploadSpeed: currentUploadSpeed
                    )
                    speedHistory.append(sample)

                    // Keep last 60 samples (1 minute at 1 sample/second)
                    if speedHistory.count > 60 {
                        speedHistory.removeFirst()
                    }

                    lastBytesReceived = totalBytesReceived
                    lastBytesSent = totalBytesSent
                    lastSpeedCheck = now
                }
            }
        }
    }

    // MARK: - Callbacks Setup

    private func setupCallbacks(for connection: PeerConnection, username: String) async {
        await connection.setOnSearchReply { [weak self] results in
            await MainActor.run {
                print("🔴 SEARCH RESULTS: \(results.count) from outgoing connection to \(username)")
                self?.onSearchResults?(results)
            }
        }

        await connection.setOnSharesReceived { [weak self] files in
            await MainActor.run {
                self?.onSharesReceived?(username, files)
            }
        }

        await connection.setOnTransferRequest { [weak self] request in
            await MainActor.run {
                self?.onTransferRequest?(request)
            }
        }

        await connection.setOnStateChanged { [weak self] state in
            await MainActor.run {
                if let key = self?.connections.keys.first(where: { $0.hasPrefix("\(username)-") }) {
                    self?.connections[key]?.state = state
                    print("🔄 Outgoing connection to \(username) state: \(state)")

                    // Clean up disconnected connections
                    if case .disconnected = state {
                        self?.connections.removeValue(forKey: key)
                        self?.activeConnections_.removeValue(forKey: key)
                        self?.activeConnections = self?.connections.count ?? 0
                        print("🔴 Connection to \(username) removed (disconnected)")
                    }
                }
            }
        }
    }

    // MARK: - Analytics

    var connectionsByType: [PeerConnection.ConnectionType: Int] {
        var result: [PeerConnection.ConnectionType: Int] = [:]
        for conn in connections.values {
            result[conn.connectionType, default: 0] += 1
        }
        return result
    }

    var averageConnectionDuration: TimeInterval {
        let durations = connections.values.compactMap { info -> TimeInterval? in
            guard let connectedAt = info.connectedAt else { return nil }
            return Date().timeIntervalSince(connectedAt)
        }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var topPeersByTraffic: [PeerConnectionInfo] {
        connections.values
            .sorted { ($0.bytesReceived + $0.bytesSent) > ($1.bytesReceived + $1.bytesSent) }
            .prefix(10)
            .map { $0 }
    }
}
