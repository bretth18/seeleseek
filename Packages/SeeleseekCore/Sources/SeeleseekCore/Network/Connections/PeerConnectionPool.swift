import Foundation
import Network
import os

/// Errors that can occur during peer connection
public enum PeerConnectionError: Error, LocalizedError {
    case invalidAddress
    case timeout
    case connectionFailed(String)
    case blockedByPolicy

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid peer IP address (multicast or reserved)"
        case .timeout:
            return "Connection timed out"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .blockedByPolicy:
            return "Peer blocked by local policy"
        }
    }
}

/// Manages multiple peer connections with statistics tracking
@Observable
@MainActor
public final class PeerConnectionPool {
    private nonisolated let logger = Logger(subsystem: "com.seeleseek", category: "PeerConnectionPool")

    // MARK: - Connection Tracking

    public private(set) var connections: [String: PeerConnectionInfo] = [:]
    public private(set) var pendingConnections: [UInt32: PendingConnection] = [:]

    // CRITICAL: Store actual PeerConnection objects to keep them alive!
    // Without this, connections get deallocated immediately after creation.
    private var activeConnections_: [String: PeerConnection] = [:]

    // MARK: - Statistics

    public private(set) var totalBytesReceived: UInt64 = 0
    public private(set) var totalBytesSent: UInt64 = 0
    public private(set) var totalConnections: UInt32 = 0
    public private(set) var activeConnections: Int = 0
    public private(set) var connectToPeerCount: Int = 0  // How many ConnectToPeer messages we've received
    public private(set) var pierceFirewallCount: Int = 0  // How many PierceFirewall messages we've received

    // Speed tracking
    public private(set) var currentDownloadSpeed: Double = 0
    public private(set) var currentUploadSpeed: Double = 0
    public private(set) var speedHistory: [SpeedSample] = []
    private var lastSpeedCheck = Date()
    private var lastBytesReceived: UInt64 = 0
    private var lastBytesSent: UInt64 = 0

    // Geographic distribution (when available)
    public private(set) var peerLocations: [PeerLocation] = []

    // MARK: - Event Stream

    public nonisolated let events: AsyncStream<PeerPoolEvent>
    private let eventContinuation: AsyncStream<PeerPoolEvent>.Continuation

    // MARK: - Configuration

    public let maxConnections = 50
    public let maxConnectionsPerIP = 30  // Allow bulk transfers while preventing abuse
    public let connectionTimeout: TimeInterval = 60

    /// If set and returns false for a peer username, the connection is silently refused
    /// (outbound) or dropped before any messages flow (inbound PeerInit). Used to block
    /// bot accounts by username pattern.
    public var peerPermissionChecker: ((String) -> Bool)?

    // SECURITY: Rate limiting configuration
    private let rateLimitWindow: TimeInterval = 60  // 1 minute window
    private let maxConnectionAttemptsPerWindow = 10  // Max attempts per IP per window

    // MARK: - Per-IP Connection Tracking
    private var connectionsPerIP: [String: Int] = [:]
    // SECURITY: Track connection attempts per IP for rate limiting
    private var connectionAttempts: [String: [Date]] = [:]

    // MARK: - Types

    public struct PeerConnectionInfo: Identifiable {
        public let id: String
        public let username: String
        public let ip: String
        public let port: Int
        public var state: PeerConnection.State
        public var connectionType: PeerConnection.ConnectionType
        public var bytesReceived: UInt64 = 0
        public var bytesSent: UInt64 = 0
        public var connectedAt: Date?
        public var lastActivity: Date?
        public var currentSpeed: Double = 0

        public init(id: String, username: String, ip: String, port: Int, state: PeerConnection.State, connectionType: PeerConnection.ConnectionType, bytesReceived: UInt64 = 0, bytesSent: UInt64 = 0, connectedAt: Date? = nil, lastActivity: Date? = nil, currentSpeed: Double = 0) {
            self.id = id; self.username = username; self.ip = ip; self.port = port; self.state = state; self.connectionType = connectionType; self.bytesReceived = bytesReceived; self.bytesSent = bytesSent; self.connectedAt = connectedAt; self.lastActivity = lastActivity; self.currentSpeed = currentSpeed
        }
    }

    public struct PendingConnection {
        public let username: String
        public let token: UInt32
        public let timestamp: Date
        public var attempts: Int = 0

        public init(username: String, token: UInt32, timestamp: Date, attempts: Int = 0) {
            self.username = username; self.token = token; self.timestamp = timestamp; self.attempts = attempts
        }
    }

    public struct SpeedSample: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let downloadSpeed: Double
        public let uploadSpeed: Double

        public init(timestamp: Date, downloadSpeed: Double, uploadSpeed: Double) {
            self.timestamp = timestamp; self.downloadSpeed = downloadSpeed; self.uploadSpeed = uploadSpeed
        }
    }

    public struct PeerLocation: Identifiable {
        public let id = UUID()
        public let username: String
        public let country: String
        public let latitude: Double
        public let longitude: Double

        public init(username: String, country: String, latitude: Double, longitude: Double) {
            self.username = username; self.country = country; self.latitude = latitude; self.longitude = longitude
        }
    }

    // MARK: - Initialization

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PeerPoolEvent.self)
        self.events = stream
        self.eventContinuation = continuation
        // Start speed tracking timer
        startSpeedTracking()
        // Start periodic cleanup of stale connections
        startCleanupTimer()
    }

    private func startCleanupTimer() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                cleanupStaleConnections()
            }
        }
    }

    // MARK: - Configuration

    // MARK: - IP Validation

    /// Check if an IP address is valid for peer connections
    /// Rejects multicast, broadcast, loopback, and other reserved addresses
    static func isValidPeerIP(_ ip: String) -> Bool {
        // Parse IP address into octets
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }

        let first = octets[0]

        // Reject multicast (224.0.0.0 - 239.255.255.255)
        if first >= 224 && first <= 239 {
            return false
        }

        // Reject broadcast (255.255.255.255)
        if octets.allSatisfy({ $0 == 255 }) {
            return false
        }

        // Reject loopback (127.x.x.x)
        if first == 127 {
            return false
        }

        // Reject 0.0.0.0
        if octets.allSatisfy({ $0 == 0 }) {
            return false
        }

        // Reject reserved (240.0.0.0 - 255.255.255.254)
        if first >= 240 {
            return false
        }

        return true
    }

    // MARK: - Connection Management

    /// Our username for PeerInit messages
    public var ourUsername: String = ""

    /// Our listen port for NAT traversal (bind outgoing connections to same port)
    public var listenPort: UInt16 = 0

    /// Connect to a peer
    /// - Parameters:
    ///   - username: Peer's username
    ///   - ip: Peer's IP address
    ///   - port: Peer's port
    ///   - token: Connection token
    ///   - isIndirect: If true, this is an indirect connection (responding to ConnectToPeer) - don't send PeerInit
    public func connect(to username: String, ip: String, port: Int, token: UInt32, isIndirect: Bool = false) async throws -> PeerConnection {
        // Reject outbound dials to blocked usernames (e.g. bot patterns like `slsk_*`).
        // Most outbound connections here are server-instructed ConnectToPeer responses,
        // which are effectively remote-initiated — we have no reason to dial a blocked user.
        if let checker = peerPermissionChecker, !checker(username) {
            logger.info("Skipping outbound connection to \(username): matches block pattern")
            ActivityLogger.shared?.logInfo(
                "Blocked outbound peer: \(username)",
                detail: "\(ip) — matches block pattern"
            )
            throw PeerConnectionError.blockedByPolicy
        }

        // Validate IP address before attempting connection
        guard Self.isValidPeerIP(ip) else {
            logger.error("Invalid peer IP address: \(ip) for \(username)")
            logger.error("Invalid peer IP address: \(ip) (multicast/reserved) for \(username)")
            throw PeerConnectionError.invalidAddress
        }

        let peerInfo = PeerConnection.PeerInfo(username: username, ip: ip, port: port)
        // Pass listen port for NAT traversal - binding outgoing connections to our listen port
        // can help with NAT hole punching
        let connection = PeerConnection(peerInfo: peerInfo, token: token, localPort: listenPort)

        // Start consuming events BEFORE connecting to avoid missing early events
        let outgoingId = "\(username)-\(token)"
        consumeEvents(from: connection, username: username, connectionId: outgoingId, capturedIP: peerInfo.ip, isIncoming: false)

        try await connection.connect()

        // For DIRECT connections, send PeerInit to identify ourselves
        // For INDIRECT connections (responding to ConnectToPeer), skip PeerInit - caller will send PierceFirewall
        if !isIndirect {
            if !ourUsername.isEmpty {
                try await connection.sendPeerInit(username: ourUsername)
                logger.debug("Sent PeerInit to \(username) as '\(self.ourUsername)'")
            } else {
                logger.warning("ourUsername not set, skipping PeerInit")
            }
        } else {
            logger.debug("Indirect connection to \(username) - skipping PeerInit (will send PierceFirewall)")
        }

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
        logger.info("Outgoing connection stored: \(connectionId)")

        // Log to activity feed
        ActivityLogger.shared?.logPeerConnected(username: username, ip: ip)

        return connection
    }

    public func acceptIncoming(_ nwConnection: NWConnection, obfuscated: Bool) async throws -> PeerConnection {
        // Create with autoStartReceiving = false so we can set up callbacks first
        let connection = PeerConnection(connection: nwConnection, isIncoming: true, autoStartReceiving: false)

        try await connection.accept()

        // We'll know the username after handshake
        // NOTE: Don't start receiving yet - caller must set up callbacks first, then call beginReceiving()
        logger.info("Accepted incoming \(obfuscated ? "obfuscated " : "")connection (receive loop pending)")

        return connection
    }

    // Callback for registering user IPs (for country flags)
    // onUserIPDiscovered replaced by PeerPoolEvent.userIPDiscovered

    /// Handle an incoming connection from the listener service
    public func handleIncomingConnection(_ nwConnection: NWConnection) async {
        // Enforce connection limit to prevent resource exhaustion
        if activeConnections >= maxConnections {
            logger.warning("Connection limit reached (\(self.maxConnections)), rejecting connection from \(String(describing: nwConnection.endpoint))")
            logger.warning("Connection limit reached, rejecting: \(String(describing: nwConnection.endpoint))")
            nwConnection.cancel()
            return
        }

        let peerIP = Self.canonicalIP(from: nwConnection.endpoint)

        // Enforce per-IP connection limit to prevent single peer from exhausting resources
        if !peerIP.isEmpty {
            let ip = peerIP
            let currentCount = connectionsPerIP[ip] ?? 0
            if currentCount >= maxConnectionsPerIP {
                logger.warning("Per-IP limit reached (\(self.maxConnectionsPerIP)) for \(ip), rejecting connection")
                logger.warning("Per-IP limit reached for \(ip), rejecting connection")
                nwConnection.cancel()
                return
            }

            // SECURITY: Rate limiting - check connection attempts in time window
            let now = Date()
            var attempts = connectionAttempts[ip] ?? []

            // Remove old attempts outside the window
            attempts = attempts.filter { now.timeIntervalSince($0) < rateLimitWindow }

            if attempts.count >= maxConnectionAttemptsPerWindow {
                logger.warning("Rate limit exceeded for \(ip) (\(attempts.count) attempts in \(self.rateLimitWindow)s), rejecting")
                logger.warning("Rate limit exceeded for \(ip), rejecting connection")
                nwConnection.cancel()
                return
            }

            // Record this attempt
            attempts.append(now)
            connectionAttempts[ip] = attempts

            // Increment per-IP counter
            connectionsPerIP[ip] = currentCount + 1
        }

        do {
            let connection = try await acceptIncoming(nwConnection, obfuscated: false)

            let connectionId = "incoming-\(UUID().uuidString.prefix(8))"

            let capturedIP = peerIP
            consumeEvents(from: connection, username: "unknown", connectionId: connectionId, capturedIP: capturedIP, isIncoming: true)

            let info = PeerConnectionInfo(
                id: connectionId,
                username: "unknown",
                ip: capturedIP,
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

            // CRITICAL: Start the receive loop AFTER all callbacks are configured
            // This fixes the race condition where F connection data arrives before callbacks are set
            await connection.beginReceiving()

            logger.info("Incoming connection accepted and callbacks configured")
            logger.info("Incoming connection stored: \(connectionId), receive loop started")
        } catch {
            logger.error("Failed to handle incoming connection: \(error.localizedDescription)")
        }
    }

    public func disconnect(username: String) async {
        let keysToRemove = connections.keys.filter { $0.hasPrefix("\(username)-") }
        for key in keysToRemove {
            connections.removeValue(forKey: key)
            if let conn = activeConnections_.removeValue(forKey: key) {
                await conn.disconnect()
            }
        }
        activeConnections = connections.count
    }

    /// Update the username for a connection (used when matching PierceFirewall to pending uploads)
    public func updateConnectionUsername(connection: PeerConnection, username: String) async {
        // Find the connection by checking which key maps to this PeerConnection
        for (key, conn) in activeConnections_ {
            if conn === connection {
                // Found the connection, update its info
                if let info = connections[key] {
                    let newInfo = PeerConnectionInfo(
                        id: info.id,
                        username: username,
                        ip: info.ip,
                        port: info.port,
                        state: info.state,
                        connectionType: info.connectionType,
                        bytesReceived: info.bytesReceived,
                        bytesSent: info.bytesSent,
                        connectedAt: info.connectedAt,
                        lastActivity: info.lastActivity
                    )
                    connections[key] = newInfo
                    logger.debug("Updated connection \(key) username to \(username)")
                }
                break
            }
        }
    }

    public func disconnectAll() async {
        for (_, conn) in activeConnections_ {
            await conn.disconnect()
        }
        activeConnections_.removeAll()
        connections.removeAll()
        pendingConnections.removeAll()
        activeConnections = 0
    }

    /// Get an active connection by ID
    public func getConnection(_ id: String) -> PeerConnection? {
        activeConnections_[id]
    }

    /// Get an active connection by username (first match)
    /// Checks both outgoing connections (keyed by "username-token") and
    /// incoming connections (keyed by "incoming-*" but with username in connection info)
    public func getConnectionForUser(_ username: String) async -> PeerConnection? {
        // First check outgoing connections (direct key match)
        if let key = activeConnections_.keys.first(where: { $0.hasPrefix("\(username)-") }),
           let connection = activeConnections_[key] {
            // CRITICAL: Verify the connection is actually still connected
            let isConnected = await connection.isConnected
            if isConnected {
                return connection
            } else {
                logger.debug("Found stale connection for \(username) (key: \(key)), removing")
                activeConnections_.removeValue(forKey: key)
                connections.removeValue(forKey: key)
            }
        }

        // Then check incoming connections by looking at the username in connection info
        for (key, info) in connections {
            if info.username == username, let connection = activeConnections_[key] {
                // CRITICAL: Verify the connection is actually still connected
                let isConnected = await connection.isConnected
                if isConnected {
                    logger.debug("Found existing incoming connection for \(username) (key: \(key))")
                    return connection
                } else {
                    logger.debug("Found stale incoming connection for \(username) (key: \(key)), removing")
                    activeConnections_.removeValue(forKey: key)
                    connections.removeValue(forKey: key)
                }
            }
        }

        return nil
    }

    // MARK: - Pending Connections

    public func addPendingConnection(username: String, token: UInt32) {
        pendingConnections[token] = PendingConnection(
            username: username,
            token: token,
            timestamp: Date()
        )
    }

    public func resolvePendingConnection(token: UInt32) -> PendingConnection? {
        return pendingConnections.removeValue(forKey: token)
    }

    // MARK: - Diagnostic Counters

    public func incrementConnectToPeerCount() {
        connectToPeerCount += 1
    }

    public func incrementPierceFirewallCount() {
        pierceFirewallCount += 1
    }

    public func cleanupStaleConnections() {
        let timeout = Date().addingTimeInterval(-connectionTimeout)
        let shortTimeout = Date().addingTimeInterval(-10)  // 10s for connections with no activity

        // Remove stale pending connections
        pendingConnections = pendingConnections.filter { $0.value.timestamp > timeout }

        // Find stale connection IDs (30s idle) and ghost connections (10s with no activity)
        var toRemove: [String] = []

        for (id, info) in connections {
            if let lastActivity = info.lastActivity {
                // Regular idle timeout (30s)
                if lastActivity <= timeout {
                    toRemove.append(id)
                }
            } else {
                // Ghost connection - never had activity, close after 10s
                if let connectedAt = info.connectedAt, connectedAt <= shortTimeout {
                    toRemove.append(id)
                }
            }
        }

        // Actually close and remove stale connections
        for id in toRemove {
            // Decrement per-IP counter before removing
            if let info = connections[id] {
                decrementIPCounter(for: info.ip)
            }

            if let conn = activeConnections_[id] {
                Task {
                    await conn.disconnect()
                }
                logger.info("Closed idle connection: \(id)")
                logger.debug("Closed idle connection: \(id)")
            }
            connections.removeValue(forKey: id)
            activeConnections_.removeValue(forKey: id)
        }

        activeConnections = connections.count

        if !toRemove.isEmpty {
            logger.info("Cleaned up \(toRemove.count) stale connections, \(self.activeConnections) active")
        }
    }

    /// Bare host string for use as the per-IP connection-count key.
    /// Must be used symmetrically by increment and decrement sites.
    static func canonicalIP(from endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "" }
        switch host {
        case .ipv4(let addr): return "\(addr)"
        case .ipv6(let addr): return "\(addr)"
        case .name(let name, _): return name
        @unknown default: return ""
        }
    }

    /// Decrement per-IP connection counter (call when removing a connection)
    private func decrementIPCounter(for ip: String) {
        guard !ip.isEmpty else { return }
        if let count = connectionsPerIP[ip] {
            if count <= 1 {
                connectionsPerIP.removeValue(forKey: ip)
            } else {
                connectionsPerIP[ip] = count - 1
            }
        }
    }

    // MARK: - Statistics

    public func updateStatistics(from connection: PeerConnection) async {
        let received = await connection.bytesReceived
        let sent = await connection.bytesSent

        totalBytesReceived += received
        totalBytesSent += sent

        // Update connection info
        let username = connection.peerInfo.username
        if let key = connections.keys.first(where: { $0.hasPrefix("\(username)-") }) {
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

    // MARK: - Event Stream Consumption

    /// Consume events from a PeerConnection's AsyncStream and dispatch them as PeerPoolEvents.
    /// Replaces the old setOn* callback pattern for Swift 6 concurrency safety.
    private func consumeEvents(from connection: PeerConnection, username: String, connectionId: String, capturedIP: String, isIncoming: Bool) {
        Task { [weak self] in
            for await event in connection.events {
                guard let self else { return }
                self.handlePeerEvent(event, connection: connection, username: username, connectionId: connectionId, capturedIP: capturedIP, isIncoming: isIncoming)
            }
        }
    }

    private func handlePeerEvent(_ event: PeerConnectionEvent, connection: PeerConnection, username: String, connectionId: String, capturedIP: String, isIncoming: Bool) {
        switch event {
        case .stateChanged(let state):
            if isIncoming {
                if case .disconnected = state {
                    decrementIPCounter(for: capturedIP)
                    connections.removeValue(forKey: connectionId)
                    activeConnections_.removeValue(forKey: connectionId)
                    activeConnections = connections.count
                }
            } else {
                if let key = connections.keys.first(where: { $0.hasPrefix("\(username)-") }) {
                    connections[key]?.state = state
                    if case .disconnected = state {
                        connections.removeValue(forKey: key)
                        activeConnections_.removeValue(forKey: key)
                        activeConnections = connections.count
                    }
                }
            }

        case .searchReply(let token, let results):
            logger.info("Search results: \(results.count) from \(username) (token=\(token))")
            eventContinuation.yield(.searchResults(token: token, results: results))
            // Close connection after results received
            Task {
                await connection.disconnect()
                if isIncoming {
                    self.decrementIPCounter(for: capturedIP)
                    self.connections.removeValue(forKey: connectionId)
                    self.activeConnections_.removeValue(forKey: connectionId)
                } else if let key = self.connections.keys.first(where: { $0.hasPrefix("\(username)-") }) {
                    self.connections.removeValue(forKey: key)
                    self.activeConnections_.removeValue(forKey: key)
                }
                self.activeConnections = self.connections.count
            }

        case .sharesReceived(let files):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.sharesReceived(username: peerUsername, files: files))

        case .transferRequest(let request):
            eventContinuation.yield(.transferRequest(request))

        case .usernameDiscovered(let discoveredUsername, let token):
            logger.info("Username discovered: \(discoveredUsername) token=\(token)")

            // Reject inbound peers whose username matches a user-configured block pattern.
            // Fires only for PeerInit (remote-initiated direct connections); PierceFirewall
            // connections get their username via setPeerUsername and never hit this path.
            if let checker = peerPermissionChecker, !checker(discoveredUsername) {
                logger.info("Dropping inbound peer connection: \(discoveredUsername) matches block pattern")
                ActivityLogger.shared?.logInfo(
                    "Blocked inbound peer: \(discoveredUsername)",
                    detail: capturedIP.isEmpty ? "matches block pattern" : "\(capturedIP) — matches block pattern"
                )
                decrementIPCounter(for: capturedIP)
                connections.removeValue(forKey: connectionId)
                activeConnections_.removeValue(forKey: connectionId)
                activeConnections = connections.count
                Task { await connection.disconnect() }
                return
            }

            // Register IP for country flag lookup
            if !capturedIP.isEmpty {
                eventContinuation.yield(.userIPDiscovered(username: discoveredUsername, ip: capturedIP))
            }

            // Update the connection info
            if var existingInfo = connections[connectionId] {
                existingInfo = PeerConnectionInfo(
                    id: connectionId,
                    username: discoveredUsername,
                    ip: existingInfo.ip,
                    port: existingInfo.port,
                    state: existingInfo.state,
                    connectionType: existingInfo.connectionType,
                    connectedAt: existingInfo.connectedAt
                )
                connections[connectionId] = existingInfo
            }

            // Check if this matches a pending connection (for downloads)
            if pendingConnections[token] != nil {
                logger.info("Matched incoming connection to pending: \(discoveredUsername) token=\(token)")
                pendingConnections.removeValue(forKey: token)
                eventContinuation.yield(.incomingConnectionMatched(username: discoveredUsername, token: token, connection: connection))
            }

        case .fileTransferConnection(let ftUsername, let token, let fileConnection):
            logger.info("File transfer connection: \(ftUsername) token=\(token)")
            eventContinuation.yield(.fileTransferConnection(username: ftUsername, token: token, connection: fileConnection))

        case .pierceFirewall(let token):
            logger.info("PierceFirewall received: token=\(token)")
            incrementPierceFirewallCount()
            decrementIPCounter(for: capturedIP)
            connections.removeValue(forKey: connectionId)
            activeConnections_.removeValue(forKey: connectionId)
            activeConnections = connections.count
            eventContinuation.yield(.pierceFirewall(token: token, connection: connection))

        case .uploadDenied(let filename, let reason):
            logger.warning("Upload denied: \(filename) - \(reason)")
            eventContinuation.yield(.uploadDenied(filename: filename, reason: reason))

        case .uploadFailed(let filename):
            logger.warning("Upload failed: \(filename)")
            eventContinuation.yield(.uploadFailed(filename: filename))

        case .queueUpload(let peerUsername, let filename):
            logger.info("QueueUpload from \(peerUsername): \(filename)")
            eventContinuation.yield(.queueUpload(username: peerUsername, filename: filename, connection: connection))

        case .transferResponse(let token, let allowed, let filesize, let reason):
            eventContinuation.yield(.transferResponse(token: token, allowed: allowed, filesize: filesize, reason: reason, connection: connection))

        case .folderContentsRequest(let token, let folder):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.folderContentsRequest(username: peerUsername, token: token, folder: folder, connection: connection))

        case .folderContentsResponse(let token, let folder, let files):
            eventContinuation.yield(.folderContentsResponse(token: token, folder: folder, files: files))

        case .placeInQueueRequest(let peerUsername, let filename):
            eventContinuation.yield(.placeInQueueRequest(username: peerUsername, filename: filename, connection: connection))

        case .placeInQueueReply(let filename, let position):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.placeInQueueReply(username: peerUsername, filename: filename, position: position))

        case .sharesRequest:
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.sharesRequest(username: peerUsername, connection: connection))

        case .userInfoRequest:
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.userInfoRequest(username: peerUsername, connection: connection))

        case .userInfoReply(let info):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.userInfoReply(username: peerUsername, info: info))

        case .artworkRequest(let token, let filePath):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.artworkRequest(username: peerUsername, token: token, filePath: filePath, connection: connection))

        case .artworkReply(let token, let imageData):
            eventContinuation.yield(.artworkReply(token: token, imageData: imageData))

        case .message:
            break // Raw messages handled directly by consumers that own the connection
        }
    }

    // MARK: - Analytics

    public var connectionsByType: [PeerConnection.ConnectionType: Int] {
        var result: [PeerConnection.ConnectionType: Int] = [:]
        for conn in connections.values {
            result[conn.connectionType, default: 0] += 1
        }
        return result
    }

    public var averageConnectionDuration: TimeInterval {
        let durations = connections.values.compactMap { info -> TimeInterval? in
            guard let connectedAt = info.connectedAt else { return nil }
            return Date().timeIntervalSince(connectedAt)
        }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    public var topPeersByTraffic: [PeerConnectionInfo] {
        connections.values
            .sorted { ($0.bytesReceived + $0.bytesSent) > ($1.bytesReceived + $1.bytesSent) }
            .prefix(10)
            .map { $0 }
    }
}
