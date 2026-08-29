import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// The status/monitor mirrors are what views observe instead of the live
/// network coordinator. These tests pin the mirror contracts: snapshots
/// apply faithfully, the speed history stays capped, the pool's 1 Hz tick
/// actually feeds the monitor, and the reachability classifier keeps its
/// documented semantics.
@MainActor
@Suite("Network mirror state")
struct NetworkMirrorStateTests {

    @Test("Status snapshot applies all fields")
    func statusSnapshotApplies() {
        let status = NetworkStatusState()
        var s = NetworkStatusSnapshot()
        s.isConnected = true
        s.loggedIn = true
        s.username = "seele"
        s.listenPort = 2234
        s.distributedChildrenCount = 3

        status.apply(s)
        #expect(status.isConnected)
        #expect(status.loggedIn)
        #expect(status.username == "seele")
        #expect(status.listenPort == 2234)
        #expect(status.distributedChildrenCount == 3)

        // Disconnect transition clears back down.
        status.apply(NetworkStatusSnapshot())
        #expect(!status.isConnected)
        #expect(status.username.isEmpty)
    }

    @Test("Client property changes reach the status mirror")
    func clientFeedsStatusMirror() async throws {
        let client = NetworkClient()
        #expect(!client.status.isConnected)
        // The didSet publishes a snapshot into the FIFO status stream;
        // delivery rides the MainActor consumer task, so poll briefly.
        await client.setAcceptDistributedChildrenPreference(false)
        var applied = false
        for _ in 0..<100 {
            if client.status.acceptDistributedChildren == false {
                applied = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(applied)
    }

    @Test("Monitor speed history is capped at 60 samples")
    func monitorSpeedHistoryCap() {
        let monitor = NetworkMonitorState()
        for i in 0..<65 {
            var s = PoolSnapshot()
            s.newSpeedSample = PeerConnectionPool.SpeedSample(
                timestamp: Date(), downloadSpeed: Double(i), uploadSpeed: 0
            )
            monitor.apply(s)
        }
        #expect(monitor.speedHistory.count == 60)
        #expect(monitor.speedHistory.last?.downloadSpeed == 64)
    }

    @Test("Pool 1Hz tick publishes seeded connections into the monitor")
    func poolTickFeedsMonitor() async throws {
        let pool = PeerConnectionPool()
        await pool._seedConnectionForTest(PeerConnectionPool.PeerConnectionInfo(
            id: "test-1", username: "alice", ip: "127.0.0.1", port: 1,
            state: .connected, connectionType: .peer
        ))
        #expect(pool.monitor.connections.isEmpty)

        // The speed-tracking task ticks at 1 Hz; wait out one tick.
        var landed = false
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if pool.monitor.connections["test-1"] != nil {
                landed = true
                break
            }
        }
        #expect(landed)
        #expect(pool.monitor.activeConnections == 1)
    }

    @Test("Reachability classifier semantics")
    func reachabilityClassifier() {
        #expect(NetworkClient.classifyReachability(directInbound: 0, indirectWanted: 0, hasActiveMapping: false) == .unknown)
        #expect(NetworkClient.classifyReachability(directInbound: 0, indirectWanted: 9, hasActiveMapping: false) == .unknown)
        #expect(NetworkClient.classifyReachability(directInbound: 0, indirectWanted: 10, hasActiveMapping: false) == .unreachable)
        #expect(NetworkClient.classifyReachability(directInbound: 5, indirectWanted: 0, hasActiveMapping: false) == .direct)
        #expect(NetworkClient.classifyReachability(directInbound: 5, indirectWanted: 0, hasActiveMapping: true) == .upnpMapped)
        #expect(NetworkClient.classifyReachability(directInbound: 2, indirectWanted: 5, hasActiveMapping: false) == .partial)
    }
}
