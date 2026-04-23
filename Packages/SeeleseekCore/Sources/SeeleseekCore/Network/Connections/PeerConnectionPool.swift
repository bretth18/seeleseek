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

    /// SeeleSeek client versions discovered via the capability handshake,
    /// keyed by peer username. Separate from `connections` because the
    /// version is a sticky, per-user fact — views that care (profile sheet,
    /// peer info popover) want to observe it without also observing every
    /// connection state/bytes mutation. Written once per SeeleSeek peer
    /// per session; never cleared while the app is running.
    public private(set) var seeleSeekVersions: [String: UInt8] = [:]

    // CRITICAL: Store actual PeerConnection objects to keep them alive!
    // Without this, connections get deallocated immediately after creation.
    private var activeConnections_: [String: PeerConnection] = [:]

    // MARK: - Statistics

    public private(set) var totalBytesReceived: UInt64 = 0
    public private(set) var totalBytesSent: UInt64 = 0

    /// Raw accumulators bumped by every transfer chunk. Not @Observable — the
    /// 1Hz speed tracker rolls these up into `totalBytesReceived`/`Sent` so
    /// SwiftUI isn't invalidated thousands of times per second during transfers.
    @ObservationIgnored private var pendingBytesReceived: UInt64 = 0
    @ObservationIgnored private var pendingBytesSent: UInt64 = 0
    public private(set) var totalConnections: UInt32 = 0
    public private(set) var activeConnections: Int = 0
    public private(set) var connectToPeerCount: Int = 0  // How many ConnectToPeer messages we've received
    public private(set) var pierceFirewallCount: Int = 0  // How many PierceFirewall messages we've received
    /// How many times a peer reached us directly and identified themselves
    /// with PeerInit. This is the definitive "our listen port is reachable"
    /// signal: if this is > 0, at least some peers connected directly to us.
    public private(set) var peerInitCount: Int = 0

    // Speed tracking
    public private(set) var currentDownloadSpeed: Double = 0
    public private(set) var currentUploadSpeed: Double = 0
    public private(set) var speedHistory: [SpeedSample] = []
    private var lastSpeedCheck = Date()
    private var lastBytesReceived: UInt64 = 0
    private var lastBytesSent: UInt64 = 0

    // Owned long-running tasks. Stored so they release `self` when the
    // pool goes away — without `[weak self]` + tracking, the infinite
    // loops inside would retain the pool forever.
    @ObservationIgnored private var speedTrackingTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    /// Per-connection last-activity timestamps, kept out of the observable
    /// `connections` dict. Every inbound peer message used to bump
    /// `connections[id].lastActivity`, which rewrites the dict value and
    /// invalidates every SwiftUI observer of `connections` on every
    /// message — a steady-state re-render storm during normal p2p traffic.
    /// Staleness only matters to the 30s cleanup timer, so observation
    /// buys nothing. Anything that actually wants to display the value
    /// (e.g. PeerInfoPopover) asks via `lastActivity(for:)`.
    @ObservationIgnored private var lastActivities: [String: Date] = [:]

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
        public var currentSpeed: Double = 0
        /// Non-nil only when the peer is a SeeleSeek client and sent our
        /// capability handshake (extension code 10000). Standard Soulseek
        /// peers (Nicotine+, qtoolsoulsync, etc.) never expose client
        /// version peer-to-peer, so this stays nil for them by design.
        /// Please note this obviously could break in the future due
        /// to other clients using the extension code.
        public var seeleSeekVersion: UInt8?

        public init(id: String, username: String, ip: String, port: Int, state: PeerConnection.State, connectionType: PeerConnection.ConnectionType, bytesReceived: UInt64 = 0, bytesSent: UInt64 = 0, connectedAt: Date? = nil, currentSpeed: Double = 0, seeleSeekVersion: UInt8? = nil) {
            self.id = id; self.username = username; self.ip = ip; self.port = port; self.state = state; self.connectionType = connectionType; self.bytesReceived = bytesReceived; self.bytesSent = bytesSent; self.connectedAt = connectedAt; self.currentSpeed = currentSpeed; self.seeleSeekVersion = seeleSeekVersion
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
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.cleanupStaleConnections()
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
        // Outbound P-connections use ephemeral source ports. Binding to our
        // listen port pinned every outbound dial to the same 4-tuple
        // (127.0.0.1:listen → peerIP:peerPort), which the kernel rejects
        // (POSIX EEXIST/17) as soon as a second download to the same peer
        // starts. There's no NAT-hole-punching benefit here either: peers
        // reach us via PierceFirewall on the listen port, not by dialing the
        // ephemeral source port of one of our outbound TCP sessions.
        let connection = PeerConnection(peerInfo: peerInfo, token: token)

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

    /// Handle an incoming connection from the listener service.
    ///
    /// `obfuscated` tracks which listener the connection arrived on. We do
    /// not yet implement the Soulseek obfuscated-stream cipher, so any
    /// connection on the obfuscated port is dropped here rather than being
    /// handled as plain TCP — previously the flag was silently discarded,
    /// which meant cipher bytes fell into the plain-text message parser
    /// and either produced garbage or a dropped connection much later.
    /// Keeping the port bound (but rejecting) lets us track inbound probes
    /// without corrupting the peer protocol.
    public func handleIncomingConnection(_ nwConnection: NWConnection, obfuscated: Bool = false) async {
        if obfuscated {
            logger.info("Rejecting obfuscated inbound connection from \(String(describing: nwConnection.endpoint)) — obfuscation not implemented")
            nwConnection.cancel()
            return
        }

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
            // Inbound timeouts / refused / resets are normal on a
            // public-facing peer (dead peers, NAT tarpits). Debug only.
            logger.debug("Failed to handle incoming connection: \(error.localizedDescription)")
        }
    }

    public func disconnect(username: String) async {
        // Match by the username recorded in PeerConnectionInfo rather than by
        // prefix-on-key. Prefix matching misses incoming connections (keyed
        // "incoming-*") and false-positives when one username is a dash-
        // prefix of another (e.g. "bob-1" matching the key "bob-12-42").
        let keysToRemove = connections.compactMap { (key, info) -> String? in
            info.username == username ? key : nil
        }
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
                        connectedAt: info.connectedAt
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
        lastActivities.removeAll()
        activeConnections = 0
    }

    /// Get an active connection by ID
    public func getConnection(_ id: String) -> PeerConnection? {
        activeConnections_[id]
    }

    /// Get an active connection by username (first match)
    /// Iterates PeerConnectionInfo rather than parsing the key: the key
    /// format differs between outgoing ("username-token") and incoming
    /// ("incoming-*"), and a prefix-match on the outgoing form could also
    /// incorrectly match a different user whose name shares a dash-prefix
    /// (e.g. "bob" matching "bob-1-42").
    public func getConnectionForUser(_ username: String) async -> PeerConnection? {
        let matchingKeys = connections.compactMap { (key, info) -> String? in
            info.username == username ? key : nil
        }

        for key in matchingKeys {
            guard let connection = activeConnections_[key] else { continue }
            let isConnected = await connection.isConnected
            if isConnected {
                return connection
            } else {
                logger.debug("Found stale connection for \(username) (key: \(key)), removing")
                activeConnections_.removeValue(forKey: key)
                connections.removeValue(forKey: key)
            }
        }

        return nil
    }

    // MARK: - Diagnostic Counters

    public func incrementConnectToPeerCount() {
        connectToPeerCount += 1
    }

    public func incrementPierceFirewallCount() {
        pierceFirewallCount += 1
    }

    public func incrementPeerInitCount() {
        peerInitCount += 1
    }

    /// Bump last-activity for the connection that just emitted an event.
    /// Writes to the non-observable `lastActivities` dict so SwiftUI views
    /// observing `connections` don't invalidate on every peer message.
    /// `connectionId` is the dict key for both incoming and outgoing
    /// connections (outgoing keys are `"\(username)-\(token)"`, set in
    /// `connect(...)`), so this is a direct lookup — no prefix scan.
    private func touchActivity(connectionId: String) {
        lastActivities[connectionId] = Date()
    }

    /// Last-activity timestamp for a connection, or nil if the connection
    /// has never emitted an event. Reads the non-observable shadow storage,
    /// so callers won't be invalidated by peer traffic — they get whatever
    /// value is current at the moment of the call. Views that need a
    /// live-updating display (e.g. a TimelineView tick) can poll this.
    public func lastActivity(for connectionId: String) -> Date? {
        lastActivities[connectionId]
    }

    public func cleanupStaleConnections() {
        let idleCutoff = Date().addingTimeInterval(-connectionTimeout)
        // Connections that haven't seen any event yet (no entry in
        // lastActivities) but were created more than 10s ago are considered
        // "stuck handshake" and reaped early. With `touchActivity` writing
        // on every event, a connection only ends up here if it never
        // received a single event — i.e. it never even reached PeerInit.
        let stuckHandshakeCutoff = Date().addingTimeInterval(-10)

        var toRemove: [String] = []
        for (id, info) in connections {
            if let lastActivity = lastActivities[id] {
                if lastActivity <= idleCutoff {
                    toRemove.append(id)
                }
            } else if let connectedAt = info.connectedAt, connectedAt <= stuckHandshakeCutoff {
                toRemove.append(id)
            }
        }

        for id in toRemove {
            if let info = connections[id] {
                decrementIPCounter(for: info.ip)
            }
            if let conn = activeConnections_[id] {
                Task { await conn.disconnect() }
                logger.info("Closed idle connection: \(id)")
            }
            connections.removeValue(forKey: id)
            activeConnections_.removeValue(forKey: id)
            lastActivities.removeValue(forKey: id)
        }

        activeConnections = connections.count

        // Evict rate-limit history for IPs whose most-recent attempt falls
        // outside the window. Without this pass the dict's key set never
        // shrinks — an IP that tries once and never comes back lingers
        // forever. The per-IP filter inside `handleIncomingConnection`
        // only prunes an IP's timestamps when that same IP re-attempts.
        let windowCutoff = Date().addingTimeInterval(-rateLimitWindow)
        connectionAttempts = connectionAttempts.filter { _, timestamps in
            guard let newest = timestamps.last else { return false }
            return newest > windowCutoff
        }

        // GC orphaned lastActivities entries. Disconnect paths don't all
        // clear this shadow — intentionally, to keep `touchActivity` off
        // the observable-mutation hot path. The value is only ever looked
        // up keyed by a live connection id, so orphaned entries are
        // harmless between sweeps; they just need periodic eviction.
        lastActivities = lastActivities.filter { connections[$0.key] != nil }

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

    /// Called by `DownloadManager` on every received file chunk. Cheap — just
    /// bumps a non-observable accumulator. The 1Hz tracker turns it into speed.
    public func recordBytesReceived(_ delta: UInt64) {
        guard delta > 0 else { return }
        pendingBytesReceived &+= delta
    }

    /// Called by `UploadManager` on every sent file chunk.
    public func recordBytesSent(_ delta: UInt64) {
        guard delta > 0 else { return }
        pendingBytesSent &+= delta
    }

    private func startSpeedTracking() {
        speedTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.captureSpeedSample()
            }
        }
    }

    private func captureSpeedSample() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCheck)
        guard elapsed > 0 else { return }

        // Snapshot once — writes (from transfer loops) and this read are both
        // on MainActor, so no further locking is needed.
        let rx = pendingBytesReceived
        let tx = pendingBytesSent

        let downloadDelta = Double(rx &- lastBytesReceived)
        let uploadDelta = Double(tx &- lastBytesSent)

        currentDownloadSpeed = downloadDelta / elapsed
        currentUploadSpeed = uploadDelta / elapsed
        totalBytesReceived = rx
        totalBytesSent = tx

        speedHistory.append(SpeedSample(
            timestamp: now,
            downloadSpeed: currentDownloadSpeed,
            uploadSpeed: currentUploadSpeed
        ))
        if speedHistory.count > 60 {
            speedHistory.removeFirst()
        }

        lastBytesReceived = rx
        lastBytesSent = tx
        lastSpeedCheck = now
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
        // Touch the connection's lastActivity on every event. Without this,
        // `lastActivity` was never set anywhere, so every connection fell
        // into `cleanupStaleConnections`'s "ghost" branch and got killed
        // 10-30s after creation regardless of whether it was being used —
        // forcing the peer to reconnect on every operation.
        touchActivity(connectionId: connectionId)

        switch event {
        case .stateChanged(let state):
            // Use connectionId — the key we assigned when tracking this exact
            // connection — not a prefix scan on username. A prefix scan can
            // match the wrong socket when the same user has multiple
            // concurrent connections (browse + search + direct download),
            // or when one username is a dash-prefix of another
            // (e.g. "bob-1" vs "bob-12").
            connections[connectionId]?.state = state
            if case .disconnected = state {
                if isIncoming {
                    decrementIPCounter(for: capturedIP)
                }
                connections.removeValue(forKey: connectionId)
                activeConnections_.removeValue(forKey: connectionId)
                activeConnections = connections.count
            }

        case .searchReply(let token, let results):
            logger.info("Search results: \(results.count) from \(username) (token=\(token))")
            eventContinuation.yield(.searchResults(token: token, results: results))
            // Close connection after results received
            Task {
                await connection.disconnect()
                if isIncoming {
                    self.decrementIPCounter(for: capturedIP)
                }
                self.connections.removeValue(forKey: connectionId)
                self.activeConnections_.removeValue(forKey: connectionId)
                self.activeConnections = self.connections.count
            }

        case .sharesReceived(let files):
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            eventContinuation.yield(.sharesReceived(username: peerUsername, files: files))

        case .transferRequest(let request):
            eventContinuation.yield(.transferRequest(request, connection: connection))

        case .usernameDiscovered(let discoveredUsername, let token):
            logger.info("Username discovered: \(discoveredUsername) token=\(token)")

            // PeerInit arrives only on remote-initiated direct connections to
            // our listen port, so each one is proof our port is reachable.
            if isIncoming {
                incrementPeerInitCount()
            }

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

        case .fileTransferConnection(let ftUsername, let token, let fileConnection):
            logger.info("File transfer connection: \(ftUsername) token=\(token)")
            // Hand the F-connection off to DownloadManager and stop tracking
            // it here. The pool's cleanupStaleConnections timer otherwise
            // kills the underlying NWConnection 10-30s after handoff —
            // long enough that any transfer that doesn't complete inside
            // that window dies mid-flight — because the pool has no
            // insight into raw file bytes flowing outside its peer-message
            // framing. Same pattern as .pierceFirewall below; both events
            // transfer ownership of the connection from pool to consumer.
            decrementIPCounter(for: capturedIP)
            connections.removeValue(forKey: connectionId)
            activeConnections_.removeValue(forKey: connectionId)
            activeConnections = connections.count
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

        case .seeleSeekVersionDiscovered(let version):
            // Stamp the version onto the live PeerConnectionInfo (for the
            // activity-tab popover, which is already binding to the
            // connection row) AND into the per-username `seeleSeekVersions`
            // dict. The separate dict is what views like UserProfileSheet
            // read: observing it only invalidates on discovery, not on
            // every connection-state or bytes update.
            let peerUsername = connection.peerInfo.username.isEmpty ? username : connection.peerInfo.username
            // Stamp onto the exact PeerConnectionInfo for this socket.
            // Prefix scans on username can hit the wrong row when a user
            // has multiple concurrent connections.
            connections[connectionId]?.seeleSeekVersion = version
            if !peerUsername.isEmpty {
                seeleSeekVersions[peerUsername] = version
            }

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

    // MARK: - Test-only accessors

    internal func _seedConnectionForTest(_ info: PeerConnectionInfo) {
        connections[info.id] = info
        activeConnections = connections.count
    }

    internal func _connectionInfo(id: String) -> PeerConnectionInfo? {
        connections[id]
    }

    internal func _touchActivityForTest(connectionId: String) {
        touchActivity(connectionId: connectionId)
    }

    /// Drive the F-connection handoff branch directly. Real callers reach it
    /// via the pool event stream after a peer's PeerInit type=F.
    internal func _simulateFileTransferHandoffForTest(connectionId: String, ip: String) {
        decrementIPCounter(for: ip)
        connections.removeValue(forKey: connectionId)
        activeConnections_.removeValue(forKey: connectionId)
        activeConnections = connections.count
    }

    /// Drive the outgoing-stateChanged branch of `handlePeerEvent` directly.
    /// Used by tests to prove the handler keys off `connectionId` instead of
    /// scanning for the first key with `"\(username)-"` prefix — when the
    /// same user has multiple concurrent connections, a prefix scan could
    /// mutate the wrong one.
    internal func _simulateOutgoingStateChangedForTest(
        connectionId: String,
        username: String,
        state: PeerConnection.State
    ) {
        connections[connectionId]?.state = state
        if case .disconnected = state {
            connections.removeValue(forKey: connectionId)
            activeConnections_.removeValue(forKey: connectionId)
            activeConnections = connections.count
        }
    }
}
