import Foundation
import Network
import os

/// Errors that can occur during peer connection
enum PeerConnectionError: Error, LocalizedError {
    case invalidAddress
    case timeout
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid peer IP address (multicast or reserved)"
        case .timeout:
            return "Connection timed out"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

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
    private(set) var connectToPeerCount: Int = 0  // How many ConnectToPeer messages we've received
    private(set) var pierceFirewallCount: Int = 0  // How many PierceFirewall messages we've received

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

    var onSearchResults: ((UInt32, [SearchResult]) -> Void)?  // (token, results)
    var onSharesReceived: ((String, [SharedFile]) -> Void)?
    var onTransferRequest: ((TransferRequest) -> Void)?
    var onIncomingConnectionMatched: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, connection)
    var onFileTransferConnection: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, connection)
    var onPierceFirewall: ((UInt32, PeerConnection) async -> Void)?  // (token, connection)
    var onUploadDenied: ((String, String) -> Void)?  // (filename, reason)
    var onUploadFailed: ((String) -> Void)?  // filename
    var onQueueUpload: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection) - peer wants to download from us
    var onTransferResponse: ((UInt32, Bool, UInt64?, PeerConnection) async -> Void)?  // (token, allowed, filesize?, connection)
    var onFolderContentsRequest: ((String, UInt32, String, PeerConnection) async -> Void)?  // (username, token, folder, connection)
    var onFolderContentsResponse: ((UInt32, String, [SharedFile]) -> Void)?  // (token, folder, files)
    var onPlaceInQueueRequest: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection)
    var onSharesRequest: ((String, PeerConnection) async -> Void)?  // (username, connection) - peer wants to browse our shares

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
    private func isValidPeerIP(_ ip: String) -> Bool {
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
    var ourUsername: String = ""

    /// Our listen port for NAT traversal (bind outgoing connections to same port)
    var listenPort: UInt16 = 0

    /// Connect to a peer
    /// - Parameters:
    ///   - username: Peer's username
    ///   - ip: Peer's IP address
    ///   - port: Peer's port
    ///   - token: Connection token
    ///   - isIndirect: If true, this is an indirect connection (responding to ConnectToPeer) - don't send PeerInit
    func connect(to username: String, ip: String, port: Int, token: UInt32, isIndirect: Bool = false) async throws -> PeerConnection {
        // Validate IP address before attempting connection
        guard isValidPeerIP(ip) else {
            logger.error("Invalid peer IP address: \(ip) for \(username)")
            print("❌ Invalid peer IP address: \(ip) (multicast/reserved) for \(username)")
            throw PeerConnectionError.invalidAddress
        }

        let peerInfo = PeerConnection.PeerInfo(username: username, ip: ip, port: port)
        // Pass listen port for NAT traversal - binding outgoing connections to our listen port
        // can help with NAT hole punching
        let connection = PeerConnection(peerInfo: peerInfo, token: token, localPort: listenPort)

        // Set up callbacks BEFORE connecting to avoid race condition where we
        // start receiving data before callbacks are ready
        await setupCallbacks(for: connection, username: username)

        try await connection.connect()

        // For DIRECT connections, send PeerInit to identify ourselves
        // For INDIRECT connections (responding to ConnectToPeer), skip PeerInit - caller will send PierceFirewall
        if !isIndirect {
            if !ourUsername.isEmpty {
                try await connection.sendPeerInit(username: ourUsername)
                print("📤 Sent PeerInit to \(username) as '\(ourUsername)'")
            } else {
                print("⚠️ Warning: ourUsername not set, skipping PeerInit")
            }
        } else {
            print("📤 Indirect connection to \(username) - skipping PeerInit (will send PierceFirewall)")
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
        print("🟢 OUTGOING CONNECTION stored: \(connectionId)")

        // Log to activity feed
        ActivityLog.shared.logPeerConnected(username: username, ip: ip)

        return connection
    }

    func acceptIncoming(_ nwConnection: NWConnection, obfuscated: Bool) async throws -> PeerConnection {
        // Create with autoStartReceiving = false so we can set up callbacks first
        let connection = PeerConnection(connection: nwConnection, isIncoming: true, autoStartReceiving: false)

        try await connection.accept()

        // We'll know the username after handshake
        // NOTE: Don't start receiving yet - caller must set up callbacks first, then call beginReceiving()
        logger.info("Accepted incoming \(obfuscated ? "obfuscated " : "")connection (receive loop pending)")

        return connection
    }

    // Callback for registering user IPs (for country flags)
    var onUserIPDiscovered: ((String, String) -> Void)?

    /// Handle an incoming connection from the listener service
    func handleIncomingConnection(_ nwConnection: NWConnection) async {
        // Enforce connection limit to prevent resource exhaustion
        if activeConnections >= maxConnections {
            logger.warning("Connection limit reached (\(self.maxConnections)), rejecting connection from \(String(describing: nwConnection.endpoint))")
            print("⚠️ Connection limit reached, rejecting: \(nwConnection.endpoint)")
            nwConnection.cancel()
            return
        }

        do {
            let connection = try await acceptIncoming(nwConnection, obfuscated: false)

            let connectionId = "incoming-\(UUID().uuidString.prefix(8))"

            // Extract IP from the connection endpoint for country flag lookup
            var peerIP: String?
            if case .hostPort(let host, _) = nwConnection.endpoint {
                switch host {
                case .ipv4(let addr):
                    peerIP = "\(addr)"
                case .ipv6(let addr):
                    peerIP = "\(addr)"
                case .name(let name, _):
                    peerIP = name
                @unknown default:
                    break
                }
            }

            // Set up ALL callbacks for the incoming connection - this is critical for receiving search results!
            // Capture connectionId to properly clean up THIS specific connection
            await connection.setOnStateChanged { [weak self, connectionId] state in
                guard let self else { return }
                await MainActor.run {
                    self.logger.info("Incoming connection \(connectionId) state changed: \(String(describing: state))")
                    print("🔄 Connection \(connectionId) state: \(state)")

                    // Clean up disconnected connections using the captured connectionId
                    if case .disconnected = state {
                        self.connections.removeValue(forKey: connectionId)
                        self.activeConnections_.removeValue(forKey: connectionId)
                        self.activeConnections = self.connections.count
                        print("🔴 Connection \(connectionId) removed (disconnected)")
                    }
                }
            }

            // IMPORTANT: Set up search reply callback so we receive search results
            await connection.setOnSearchReply { [weak self] token, results in
                await MainActor.run {
                    print("🔴 SEARCH RESULTS: \(results.count) from incoming connection (token=\(token))")
                    self?.logger.info("Received \(results.count) search results from incoming connection")
                    self?.onSearchResults?(token, results)
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

            // CRITICAL: Set up username discovery callback to match incoming connections to pending downloads
            await connection.setOnUsernameDiscovered { [weak self, connectionId, peerIP] username, token in
                guard let self else { return }
                await MainActor.run {
                    print("🔔 Username discovered on incoming connection: \(username) token=\(token)")
                    self.logger.info("Incoming connection identified: \(username) token=\(token)")

                    // Register IP for country flag lookup
                    if let ip = peerIP {
                        self.onUserIPDiscovered?(username, ip)
                    }

                    // Update the connection info with the real username
                    if var existingInfo = self.connections[connectionId] {
                        existingInfo = PeerConnectionInfo(
                            id: connectionId,
                            username: username,
                            ip: existingInfo.ip,
                            port: existingInfo.port,
                            state: existingInfo.state,
                            connectionType: existingInfo.connectionType,
                            connectedAt: existingInfo.connectedAt
                        )
                        self.connections[connectionId] = existingInfo
                    }

                    // Check if this matches a pending connection (for downloads)
                    if self.pendingConnections[token] != nil {
                        print("✅ Matched incoming connection to pending download: \(username) token=\(token)")
                        self.logger.info("Matched incoming connection to pending: \(username) token=\(token)")
                        self.pendingConnections.removeValue(forKey: token)

                        // Notify the download manager
                        Task {
                            await self.onIncomingConnectionMatched?(username, token, connection)
                        }
                    }
                    // Note: Indirect browse connections are now handled via PierceFirewall callback
                }
            }

            // Set up file transfer connection callback
            await connection.setOnFileTransferConnection { [weak self] username, token, fileConnection in
                guard let self else {
                    print("❌ PeerConnectionPool: self is nil in F connection callback!")
                    return
                }
                print("📁 PeerConnectionPool: F connection callback invoked - username='\(username)' token=\(token)")
                self.logger.info("File transfer connection: \(username) token=\(token)")
                if self.onFileTransferConnection != nil {
                    print("📁 PeerConnectionPool: Forwarding to NetworkClient...")
                    await self.onFileTransferConnection?(username, token, fileConnection)
                    print("📁 PeerConnectionPool: Forward complete")
                } else {
                    print("❌ PeerConnectionPool: onFileTransferConnection is nil!")
                }
            }

            // Set up PierceFirewall callback for indirect connections
            await connection.setOnPierceFirewall { [weak self] token in
                guard let self else { return }
                print("🔓 PierceFirewall from incoming connection, token=\(token)")
                self.logger.info("PierceFirewall received: token=\(token)")
                await MainActor.run { self.incrementPierceFirewallCount() }
                await self.onPierceFirewall?(token, connection)
            }

            // Set up upload denied/failed callbacks
            await connection.setOnUploadDenied { [weak self] filename, reason in
                await MainActor.run {
                    print("🚫 Upload denied: \(filename) - \(reason)")
                    self?.onUploadDenied?(filename, reason)
                }
            }

            await connection.setOnUploadFailed { [weak self] filename in
                await MainActor.run {
                    print("❌ Upload failed: \(filename)")
                    self?.onUploadFailed?(filename)
                }
            }

            // Set up QueueUpload callback for incoming connections (peer wants to download from us)
            await connection.setOnQueueUpload { [weak self] peerUsername, filename in
                guard let self else { return }
                print("📥 QueueUpload from incoming connection \(peerUsername): \(filename)")
                await self.onQueueUpload?(peerUsername, filename, connection)
            }

            // Set up TransferResponse callback for incoming connections
            await connection.setOnTransferResponse { [weak self] token, allowed, filesize in
                guard let self else { return }
                print("📨 TransferResponse from incoming: token=\(token) allowed=\(allowed)")
                await self.onTransferResponse?(token, allowed, filesize, connection)
            }

            // Set up FolderContentsRequest callback for incoming connections
            await connection.setOnFolderContentsRequest { [weak self] token, folder in
                guard let self else { return }
                let peerUsername = await connection.getPeerUsername()
                print("📁 FolderContentsRequest from incoming (\(peerUsername)): \(folder)")
                await self.onFolderContentsRequest?(peerUsername, token, folder, connection)
            }

            // Set up FolderContentsResponse callback for incoming connections
            await connection.setOnFolderContentsResponse { [weak self] token, folder, files in
                await MainActor.run {
                    print("📁 FolderContentsResponse from incoming: \(folder) with \(files.count) files")
                    self?.onFolderContentsResponse?(token, folder, files)
                }
            }

            // Set up PlaceInQueueRequest callback for incoming connections
            await connection.setOnPlaceInQueueRequest { [weak self] peerUsername, filename in
                guard let self else { return }
                print("📊 PlaceInQueueRequest from incoming (\(peerUsername)): \(filename)")
                await self.onPlaceInQueueRequest?(peerUsername, filename, connection)
            }

            // Set up SharesRequest callback for incoming connections (peer wants to browse us)
            await connection.setOnSharesRequest { [weak self] conn in
                guard let self else { return }
                let peerUsername = await conn.getPeerUsername()
                print("📂 SharesRequest from incoming (\(peerUsername)): peer wants to browse our shares")
                await self.onSharesRequest?(peerUsername, conn)
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

            // CRITICAL: Start the receive loop AFTER all callbacks are configured
            // This fixes the race condition where F connection data arrives before callbacks are set
            await connection.beginReceiving()

            logger.info("Incoming connection accepted and callbacks configured")
            print("🟢 INCOMING CONNECTION stored: \(connectionId), receive loop started")
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
    /// Checks both outgoing connections (keyed by "username-token") and
    /// incoming connections (keyed by "incoming-*" but with username in connection info)
    func getConnectionForUser(_ username: String) -> PeerConnection? {
        // First check outgoing connections (direct key match)
        if let key = activeConnections_.keys.first(where: { $0.hasPrefix("\(username)-") }) {
            return activeConnections_[key]
        }

        // Then check incoming connections by looking at the username in connection info
        for (key, info) in connections {
            if info.username == username, let connection = activeConnections_[key] {
                print("♻️ Found existing INCOMING connection for \(username) (key: \(key))")
                return connection
            }
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

    // MARK: - Diagnostic Counters

    func incrementConnectToPeerCount() {
        connectToPeerCount += 1
    }

    func incrementPierceFirewallCount() {
        pierceFirewallCount += 1
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

    private func setupCallbacks(for connection: PeerConnection, username: String) async {
        print("🔧 Setting up callbacks for connection to \(username)")

        await connection.setOnSearchReply { [weak self] token, results in
            print("🔔 PeerConnectionPool: Received search reply callback for \(username) - \(results.count) results, token=\(token)")
            await MainActor.run {
                print("🔴 SEARCH RESULTS: \(results.count) from \(username) (token=\(token))")
                if self?.onSearchResults != nil {
                    print("🔔 PeerConnectionPool: Forwarding to NetworkClient callback...")
                    self?.onSearchResults?(token, results)
                } else {
                    print("⚠️ PeerConnectionPool: onSearchResults callback is nil!")
                }
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

        await connection.setOnUploadDenied { [weak self] filename, reason in
            await MainActor.run {
                print("🚫 Upload denied: \(filename) - \(reason)")
                self?.onUploadDenied?(filename, reason)
            }
        }

        await connection.setOnUploadFailed { [weak self] filename in
            await MainActor.run {
                print("❌ Upload failed: \(filename)")
                self?.onUploadFailed?(filename)
            }
        }

        await connection.setOnQueueUpload { [weak self] peerUsername, filename in
            guard let self else { return }
            print("📥 QueueUpload from \(peerUsername): \(filename)")
            await self.onQueueUpload?(peerUsername, filename, connection)
        }

        await connection.setOnTransferResponse { [weak self] token, allowed, filesize in
            guard let self else { return }
            print("📨 TransferResponse: token=\(token) allowed=\(allowed)")
            await self.onTransferResponse?(token, allowed, filesize, connection)
        }

        await connection.setOnFolderContentsRequest { [weak self] token, folder in
            guard let self else { return }
            print("📁 FolderContentsRequest from \(username): \(folder)")
            await self.onFolderContentsRequest?(username, token, folder, connection)
        }

        await connection.setOnFolderContentsResponse { [weak self] token, folder, files in
            await MainActor.run {
                print("📁 FolderContentsResponse: \(folder) with \(files.count) files")
                self?.onFolderContentsResponse?(token, folder, files)
            }
        }

        await connection.setOnPlaceInQueueRequest { [weak self] peerUsername, filename in
            guard let self else { return }
            print("📊 PlaceInQueueRequest from \(peerUsername): \(filename)")
            await self.onPlaceInQueueRequest?(peerUsername, filename, connection)
        }

        // Set up SharesRequest callback (peer wants to browse us)
        await connection.setOnSharesRequest { [weak self] conn in
            guard let self else { return }
            print("📂 SharesRequest from \(username): peer wants to browse our shares")
            await self.onSharesRequest?(username, conn)
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

        print("🔧 Callbacks set up for \(username)")
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
