import Foundation

/// The pool's statistics as one value, yielded by its 1 Hz speed-tracking
/// tick — one MainActor observation write per second regardless of peer
/// traffic volume.
public struct PoolSnapshot: Sendable {
    public var connections: [String: PeerConnectionPool.PeerConnectionInfo] = [:]
    public var extendedClientInfoByUser: [String: ExtendedClientInfo] = [:]
    public var lastActivities: [String: Date] = [:]
    public var totalBytesReceived: UInt64 = 0
    public var totalBytesSent: UInt64 = 0
    public var totalConnections: UInt32 = 0
    public var activeConnections = 0
    public var connectToPeerCount = 0
    public var pierceFirewallCount = 0
    public var peerInitCount = 0
    public var currentDownloadSpeed: Double = 0
    public var currentUploadSpeed: Double = 0
    /// The tick's new sample; the mirror appends it to its own capped
    /// history so the snapshot doesn't ship sixty samples per second.
    public var newSpeedSample: PeerConnectionPool.SpeedSample?
    public var peerLocations: [PeerConnectionPool.PeerLocation] = []

    public init() {}
}

/// What the diagnostics and network-monitor views observe. Fed two ways:
/// the full snapshot at 1 Hz, and eager per-discovery `applyClientInfo`
/// updates so capability-gated UI (browse-row artwork buttons, peer
/// popovers) doesn't wait out the tick.
@Observable
@MainActor
public final class NetworkMonitorState {
    public private(set) var connections: [String: PeerConnectionPool.PeerConnectionInfo] = [:]
    public private(set) var extendedClientInfoByUser: [String: ExtendedClientInfo] = [:]
    public private(set) var totalBytesReceived: UInt64 = 0
    public private(set) var totalBytesSent: UInt64 = 0
    public private(set) var totalConnections: UInt32 = 0
    public private(set) var activeConnections = 0
    public private(set) var connectToPeerCount = 0
    public private(set) var pierceFirewallCount = 0
    public private(set) var peerInitCount = 0
    public private(set) var currentDownloadSpeed: Double = 0
    public private(set) var currentUploadSpeed: Double = 0
    public private(set) var speedHistory: [PeerConnectionPool.SpeedSample] = []
    public private(set) var peerLocations: [PeerConnectionPool.PeerLocation] = []

    /// Mirror of the pool's connection cap, for diagnostics display.
    public let maxConnections: Int

    /// Kept out of observation — bumped by every inbound peer message on
    /// the pool side; displayed only on demand (PeerInfoPopover).
    @ObservationIgnored private var lastActivities: [String: Date] = [:]

    public init(maxConnections: Int = 50) {
        self.maxConnections = maxConnections
    }

    /// Whether `username` has advertised `code`, for building UI
    /// synchronously. An affordance only — the send path re-checks the
    /// live socket via `PeerConnection.supports(_:)`.
    public func hasAdvertised(_ code: ExtendedClientInfoCode, by username: String) -> Bool {
        extendedClientInfoByUser[username]?.supports(code) ?? false
    }

    /// Last-activity timestamp for a connection, as of the latest 1 Hz
    /// snapshot. Non-observable — poll from a TimelineView tick if a
    /// live display is needed.
    public func lastActivity(for connectionId: String) -> Date? {
        lastActivities[connectionId]
    }

    public var averageConnectionDuration: TimeInterval {
        let durations = connections.values.compactMap { info -> TimeInterval? in
            guard let connectedAt = info.connectedAt else { return nil }
            return Date().timeIntervalSince(connectedAt)
        }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    public func apply(_ s: PoolSnapshot) {
        if connections != s.connections { connections = s.connections }
        if extendedClientInfoByUser != s.extendedClientInfoByUser {
            extendedClientInfoByUser = s.extendedClientInfoByUser
        }
        lastActivities = s.lastActivities
        if totalBytesReceived != s.totalBytesReceived { totalBytesReceived = s.totalBytesReceived }
        if totalBytesSent != s.totalBytesSent { totalBytesSent = s.totalBytesSent }
        if totalConnections != s.totalConnections { totalConnections = s.totalConnections }
        if activeConnections != s.activeConnections { activeConnections = s.activeConnections }
        if connectToPeerCount != s.connectToPeerCount { connectToPeerCount = s.connectToPeerCount }
        if pierceFirewallCount != s.pierceFirewallCount { pierceFirewallCount = s.pierceFirewallCount }
        if peerInitCount != s.peerInitCount { peerInitCount = s.peerInitCount }
        if currentDownloadSpeed != s.currentDownloadSpeed { currentDownloadSpeed = s.currentDownloadSpeed }
        if currentUploadSpeed != s.currentUploadSpeed { currentUploadSpeed = s.currentUploadSpeed }
        if peerLocations != s.peerLocations { peerLocations = s.peerLocations }
        if let sample = s.newSpeedSample {
            speedHistory.append(sample)
            if speedHistory.count > 60 {
                speedHistory.removeFirst()
            }
        }
    }

    /// Eager capability-discovery update between snapshot ticks.
    public func applyClientInfo(username: String, info: ExtendedClientInfo) {
        extendedClientInfoByUser[username] = info
    }
}
