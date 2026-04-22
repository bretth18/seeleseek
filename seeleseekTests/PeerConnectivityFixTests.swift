import Testing
import Network
import Foundation
@testable import SeeleseekCore

/// Regression tests for the peer-connectivity bug fixes:
///  - obfuscated listener retention
///  - multi-waiter getPeerAddress coalescing
///  - TransferRequest routing ambiguity
///  - outbound NWParameters construction
@Suite("Peer Connectivity Fixes", .serialized)
struct PeerConnectivityFixTests {

    // MARK: - Obfuscated listener retention

    @Test("Obfuscated listener accepts inbound connections after start()")
    func obfuscatedListenerAcceptsInbound() async throws {
        let service = ListenerService()
        let (port, obfuscatedPort) = try await service.start()
        defer { Task { await service.stop() } }

        #expect(port > 0)
        #expect(obfuscatedPort == port + 1)

        // If the obfuscated port couldn't be bound (common in CI when a prior
        // run left it in TIME_WAIT), the retention fix correctly cleans up —
        // but there's nothing left to connect to. Treat that as an environmental
        // skip rather than a test failure of the retention behavior.
        let obfActive = await service.obfuscatedListenerIsActive
        try #require(obfActive, "obfuscated listener could not bind; skipping behavioral test")

        let stream = await service.newConnections
        let reader = Task { () -> (NWConnection, Bool)? in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(3))
            reader.cancel()
        }
        defer { watchdog.cancel() }

        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: obfuscatedPort)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.start(queue: .global())
        defer { conn.cancel() }

        let received = await reader.value
        let unwrapped = try #require(received, "obfuscated listener did not surface the connection within 3s")
        #expect(unwrapped.1 == true, "connection should be flagged obfuscated")
    }

    // MARK: - Multi-waiter getPeerAddress

    @Test("Concurrent peer-address waiters all resume on single response")
    func multiWaiterPeerAddressCoalesces() async throws {
        let client = await NetworkClient()

        let a = Task { try await client._awaitPeerAddressWaiter(for: "alice", timeout: .seconds(5)) }
        let b = Task { try await client._awaitPeerAddressWaiter(for: "alice", timeout: .seconds(5)) }
        let c = Task { try await client._awaitPeerAddressWaiter(for: "alice", timeout: .seconds(5)) }

        try? await Task.sleep(for: .milliseconds(50))
        await client.handlePeerAddressResponse(username: "alice", ip: "10.0.0.1", port: 2345)

        let ra = try await a.value
        let rb = try await b.value
        let rc = try await c.value
        #expect(ra.ip == "10.0.0.1" && ra.port == 2345)
        #expect(rb.ip == "10.0.0.1" && rb.port == 2345)
        #expect(rc.ip == "10.0.0.1" && rc.port == 2345)
    }

    @Test("One waiter timing out does not affect the others")
    func singleWaiterTimesOutWithoutAffectingOthers() async throws {
        let client = await NetworkClient()

        let early = Task { try await client._awaitPeerAddressWaiter(for: "bob", timeout: .seconds(10)) }
        try? await Task.sleep(for: .milliseconds(20))
        let late = Task { try await client._awaitPeerAddressWaiter(for: "bob", timeout: .milliseconds(100)) }

        do {
            _ = try await late.value
            Issue.record("late waiter should have timed out")
        } catch {
            // expected
        }

        await client.handlePeerAddressResponse(username: "bob", ip: "10.0.0.2", port: 1111)
        let result = try await early.value
        #expect(result.ip == "10.0.0.2")
    }

    // MARK: - Transfer routing

    @Test("Token match takes precedence over filename")
    func transferRoutingPrefersToken() {
        let pending: [UInt32: DownloadManager.PendingDownload] = [
            42: .init(transferId: UUID(), username: "alice", filename: "song.flac", size: 1000),
            7:  .init(transferId: UUID(), username: "bob",   filename: "other.flac", size: 1000)
        ]
        let request = TransferRequest(
            direction: .upload, token: 42, filename: "ANY.flac", size: 1000, username: "zzz"
        )
        #expect(DownloadManager.matchPendingDownload(request: request, pending: pending) == 42)
    }

    @Test("(username, filename) wins when token doesn't match")
    func transferRoutingMatchesByUsernameAndFilename() {
        let pending: [UInt32: DownloadManager.PendingDownload] = [
            1: .init(transferId: UUID(), username: "alice", filename: "shared.flac", size: 1000),
            2: .init(transferId: UUID(), username: "bob",   filename: "shared.flac", size: 1000)
        ]
        let request = TransferRequest(
            direction: .upload, token: 999, filename: "shared.flac", size: 1000, username: "bob"
        )
        #expect(DownloadManager.matchPendingDownload(request: request, pending: pending) == 2)
    }

    @Test("Empty request.username refuses to match — caller must normalize")
    func transferRoutingRequiresUsername() {
        // request.username is empty (the connection identification didn't make it
        // into the request payload). The filename-only fallback was removed
        // because it could misroute when two peers happen to be sending the same
        // filename. handlePoolTransferRequest is responsible for filling in the
        // username from the delivering connection's peerInfo before matching.
        let pending: [UInt32: DownloadManager.PendingDownload] = [
            5: .init(transferId: UUID(), username: "alice", filename: "only.flac", size: 1000)
        ]
        let request = TransferRequest(
            direction: .upload, token: 999, filename: "only.flac", size: 1000, username: ""
        )
        #expect(DownloadManager.matchPendingDownload(request: request, pending: pending) == nil)
    }

    // MARK: - Outbound parameters

    @Test("makeOutboundParameters binds to the requested local port")
    func outboundParamsSetLocalEndpoint() throws {
        let remote = NWEndpoint.hostPort(host: .ipv4(.init("1.2.3.4")!), port: 2234)
        let params = PeerConnection.makeOutboundParameters(bindTo: 2234, remoteEndpoint: remote)

        let localEndpoint = try #require(params.requiredLocalEndpoint)
        guard case .hostPort(let host, let port) = localEndpoint else {
            Issue.record("expected hostPort endpoint"); return
        }
        #expect(port.rawValue == 2234)
        if case .ipv4 = host {} else { Issue.record("expected IPv4 bind for IPv4 remote") }
        #expect(params.allowLocalEndpointReuse == true)
    }

    @Test("makeOutboundParameters omits bind when no local port given")
    func outboundParamsUnbound() {
        let remote = NWEndpoint.hostPort(host: .ipv4(.init("1.2.3.4")!), port: 2234)
        let params = PeerConnection.makeOutboundParameters(bindTo: nil, remoteEndpoint: remote)
        #expect(params.requiredLocalEndpoint == nil)
    }

    @Test("makeOutboundParameters matches IPv6 remote with IPv6 bind")
    func outboundParamsIPv6() throws {
        let remote = NWEndpoint.hostPort(host: .ipv6(.init("::1")!), port: 2234)
        let params = PeerConnection.makeOutboundParameters(bindTo: 2234, remoteEndpoint: remote)
        let localEndpoint = try #require(params.requiredLocalEndpoint)
        guard case .hostPort(let host, _) = localEndpoint else {
            Issue.record("expected hostPort"); return
        }
        if case .ipv6 = host {} else { Issue.record("expected IPv6 bind for IPv6 remote") }
    }

    // MARK: - Per-IP counter key symmetry

    @Test("canonicalIP strips port from host:port endpoints")
    func canonicalIPStripsPort() {
        let e1 = NWEndpoint.hostPort(host: .ipv4(.init("192.168.1.5")!), port: 54321)
        let e2 = NWEndpoint.hostPort(host: .ipv4(.init("192.168.1.5")!), port: 65000)
        let k1 = PeerConnectionPool.canonicalIP(from: e1)
        let k2 = PeerConnectionPool.canonicalIP(from: e2)
        // Original bug: increment used "192.168.1.5", decrement used the
        // String(describing:) form which included the port. Symmetry requires
        // both endpoints (same host, different ports) to map to the same key.
        #expect(k1 == k2)
        #expect(k1 == "192.168.1.5")
        #expect(!k1.contains(":"))
    }

    @Test("canonicalIP handles IPv6 endpoints")
    func canonicalIPIPv6() {
        let e = NWEndpoint.hostPort(host: .ipv6(.init("::1")!), port: 1234)
        let key = PeerConnectionPool.canonicalIP(from: e)
        #expect(!key.isEmpty)
        #expect(!key.hasSuffix(":1234"))
    }

    @Test("canonicalIP handles named hosts")
    func canonicalIPNamedHost() {
        let e = NWEndpoint.hostPort(host: .name("example.com", nil), port: 80)
        let key = PeerConnectionPool.canonicalIP(from: e)
        #expect(key == "example.com")
    }

    @Test("isBindFailure recognises EADDRINUSE / EADDRNOTAVAIL only")
    func bindFailureDetection() {
        #expect(PeerConnection.isBindFailure(NWError.posix(.EADDRINUSE)) == true)
        #expect(PeerConnection.isBindFailure(NWError.posix(.EADDRNOTAVAIL)) == true)
        #expect(PeerConnection.isBindFailure(NWError.posix(.ECONNREFUSED)) == false)
        #expect(PeerConnection.isBindFailure(NWError.posix(.ETIMEDOUT)) == false)
    }

    // MARK: - Artwork coalescing

    @Test("Concurrent artwork requests for the same (peer, file) coalesce into one")
    func artworkCoalescesSamePeerSameFile() async {
        let client = await NetworkClient()

        // Two waiters for the SAME (peer, file) key.
        let result1 = LockedResult<Data?>()
        let result2 = LockedResult<Data?>()
        let key1 = await client._registerArtworkWaiterForTest(
            username: "alice", filePath: "Music/foo.mp3"
        ) { result1.set($0) }
        let key2 = await client._registerArtworkWaiterForTest(
            username: "alice", filePath: "Music/foo.mp3"
        ) { result2.set($0) }
        #expect(key1 == key2, "same (peer, file) must produce same coalescing key")

        let count = await client._pendingArtworkWaiterCount(key: key1)
        #expect(count == 2, "both waiters share one pending entry")

        // One delivery fans out to all waiters.
        let payload = Data([0xCA, 0xFE])
        await client._deliverArtworkForTest(key: key1, data: payload)

        #expect(result1.get() == payload)
        #expect(result2.get() == payload)

        let countAfter = await client._pendingArtworkWaiterCount(key: key1)
        #expect(countAfter == 0, "delivery cleans up the coalesced entry")
    }

    @Test("Different (peer, file) keys do NOT coalesce")
    func artworkDoesNotCoalesceDifferentKeys() async {
        let client = await NetworkClient()

        let resultA = LockedResult<Data?>()
        let resultB = LockedResult<Data?>()
        let keyA = await client._registerArtworkWaiterForTest(
            username: "alice", filePath: "Music/a.mp3"
        ) { resultA.set($0) }
        let keyB = await client._registerArtworkWaiterForTest(
            username: "bob", filePath: "Music/a.mp3"
        ) { resultB.set($0) }
        #expect(keyA != keyB, "different peers for same filename must NOT share a key")

        await client._deliverArtworkForTest(key: keyA, data: Data([0x01]))
        #expect(resultA.get() == Data([0x01]))
        #expect(resultB.get() == nil, "delivering A must not trigger B's waiter")

        await client._deliverArtworkForTest(key: keyB, data: Data([0x02]))
        #expect(resultB.get() == Data([0x02]))
    }

    @Test("Late artwork delivery (timeout firing after reply) is a no-op")
    func artworkLateDeliveryIsIdempotent() async {
        let client = await NetworkClient()

        let result = LockedResult<Data?>()
        let key = await client._registerArtworkWaiterForTest(
            username: "alice", filePath: "Music/foo.mp3"
        ) { result.set($0) }

        await client._deliverArtworkForTest(key: key, data: Data([0xFF]))
        #expect(result.get() == Data([0xFF]))

        // A second delivery (e.g. timeout firing late) must not crash or
        // double-call the waiter.
        await client._deliverArtworkForTest(key: key, data: nil)
        // Result still the original payload — nothing was overwritten.
        #expect(result.get() == Data([0xFF]))
    }

    // MARK: - Pool: F-connection handoff (regression for transfers killed mid-flight)

    @Test("Pool removes F-connection from tracking on handoff")
    func poolRemovesFConnectionOnHandoff() async {
        let pool = await PeerConnectionPool()

        let info = await PeerConnectionPool.PeerConnectionInfo(
            id: "incoming-TEST",
            username: "alice",
            ip: "10.0.0.5",
            port: 12345,
            state: .connected,
            connectionType: .peer,
            connectedAt: Date()
        )
        await pool._seedConnectionForTest(info)
        #expect(await pool._connectionInfo(id: "incoming-TEST") != nil,
                "precondition: connection seeded")

        // Simulate the .fileTransferConnection event arriving — the pool
        // must hand the connection off (untrack it) so `cleanupStaleConnections`
        // can't kill it mid-transfer.
        await pool._simulateFileTransferHandoffForTest(connectionId: "incoming-TEST", ip: "10.0.0.5")

        #expect(await pool._connectionInfo(id: "incoming-TEST") == nil,
                "F-connection must be removed from pool tracking after handoff")
    }

    // MARK: - Pool: lastActivity bumped on event

    @Test("touchActivity updates lastActivity so cleanup doesn't reap a live connection")
    func poolTouchActivityKeepsConnectionFresh() async {
        let pool = await PeerConnectionPool()

        // Seed a connection that's been "alive" longer than the 10s
        // stuck-handshake cutoff but with no activity yet.
        let staleConnectedAt = Date().addingTimeInterval(-15)
        let info = await PeerConnectionPool.PeerConnectionInfo(
            id: "alice-42",
            username: "alice",
            ip: "10.0.0.6",
            port: 2234,
            state: .connected,
            connectionType: .peer,
            connectedAt: staleConnectedAt
        )
        await pool._seedConnectionForTest(info)
        #expect(await pool._connectionInfo(id: "alice-42")?.lastActivity == nil,
                "precondition: lastActivity unset")

        // Real wiring: handlePeerEvent calls this on every event.
        await pool._touchActivityForTest(connectionId: "alice-42")

        let after = await pool._connectionInfo(id: "alice-42")
        #expect(after?.lastActivity != nil, "lastActivity must be set after activity")
        // Now run cleanup. The stuck-handshake branch only fires when
        // lastActivity is nil — with our touch, it should be skipped.
        await pool.cleanupStaleConnections()
        #expect(await pool._connectionInfo(id: "alice-42") != nil,
                "live connection must survive cleanup tick")
    }

    // MARK: - DownloadManager: salvage path

    /// These tests use `_evaluatePoolTransferRequestForTest` rather than
    /// `_handlePoolTransferRequestForTest` so the assertion observes the
    /// routing DECISION rather than the side effect. The full
    /// `handlePoolTransferRequest` pipeline calls `handleTransferRequest`
    /// which tries to send TransferReply on the connection and removes
    /// the pending entry on failure — racy to assert against on a
    /// synthetic non-connected PeerConnection.

    @Test("Salvage lifts a transferState entry into pendingDownloads")
    func salvageLiftsTransferStateEntry() async {
        let dm = await DownloadManager()
        let tracking = await MockTransferTracking()
        await dm._setTransferStateForTest(tracking)

        let transferId = UUID()
        await tracking.addDownload(Transfer(
            id: transferId,
            username: "alice",
            filename: "Music/song.mp3",
            size: 5_000_000,
            direction: .download,
            status: .queued
        ))

        let conn = PeerConnection(peerInfo: .init(username: "alice", ip: "10.0.0.7", port: 2234))
        let decision = await dm._evaluatePoolTransferRequestForTest(
            TransferRequest(direction: .upload, token: 999,
                            filename: "Music/song.mp3", size: 5_000_000,
                            username: "alice"),
            connection: conn
        )

        guard case .salvaged(let salvagedToken, let salvagedTransferId) = decision else {
            Issue.record("expected .salvaged, got \(decision)")
            return
        }
        #expect(salvagedTransferId == transferId, "salvaged decision must reference the matching transferState transfer")

        let pending = await dm._pendingDownloadFor(username: "alice", filename: "Music/song.mp3")
        #expect(pending?.transferId == transferId)
        #expect(pending?.size == 5_000_000)
        #expect(pending?.peerIP == "10.0.0.7")
        #expect(pending?.peerPort == 2234)
        #expect(salvagedToken != 0)
    }

    @Test("Salvage refuses to duplicate when a pendingDownload already exists")
    func salvageSkipsWhenPendingExists() async {
        let dm = await DownloadManager()
        let tracking = await MockTransferTracking()
        await dm._setTransferStateForTest(tracking)

        let transferId = UUID()
        await dm._seedPendingDownloadForTest(
            DownloadManager.PendingDownload(
                transferId: transferId,
                username: "alice",
                filename: "Music/song.mp3",
                size: 5_000_000,
                peerIP: "10.0.0.7",
                peerPort: 2234
            ),
            token: 7
        )

        await tracking.addDownload(Transfer(
            id: transferId,
            username: "alice",
            filename: "Music/song.mp3",
            size: 5_000_000,
            direction: .download,
            status: .queued
        ))

        let conn = PeerConnection(peerInfo: .init(username: "alice", ip: "10.0.0.7", port: 2234))
        let decision = await dm._evaluatePoolTransferRequestForTest(
            TransferRequest(direction: .upload, token: 999,
                            filename: "Music/song.mp3", size: 5_000_000,
                            username: "alice"),
            connection: conn
        )

        // Token 999 doesn't match our seed (token 7), but (alice, song.mp3)
        // does — expect a `matched` decision pointing at our seeded token.
        // Critically, NOT a `salvaged` decision creating a duplicate entry.
        #expect(decision == .matched(token: 7))
        let count = await dm._pendingDownloadCount
        #expect(count == 1, "no duplicate pending entry created")
    }

    @Test("Salvage refuses .failed transfers — user gave up; peer offer is stale")
    func salvageRefusesFailedTransfers() async {
        let dm = await DownloadManager()
        let tracking = await MockTransferTracking()
        await dm._setTransferStateForTest(tracking)

        await tracking.addDownload(Transfer(
            id: UUID(),
            username: "alice",
            filename: "Music/song.mp3",
            size: 5_000_000,
            direction: .download,
            status: .failed,
            error: "Manually cancelled by user"
        ))

        let conn = PeerConnection(peerInfo: .init(username: "alice", ip: "10.0.0.7", port: 2234))
        let decision = await dm._evaluatePoolTransferRequestForTest(
            TransferRequest(direction: .upload, token: 999,
                            filename: "Music/song.mp3", size: 5_000_000,
                            username: "alice"),
            connection: conn
        )

        #expect(decision == .dropped, ".failed transfers must NOT be silently re-accepted via salvage")
        let count = await dm._pendingDownloadCount
        #expect(count == 0)
    }
}

// MARK: - Test fixtures

@MainActor
final class MockTransferTracking: TransferTracking, @unchecked Sendable {
    var downloads: [Transfer] = []
    var uploads: [Transfer] = []

    func addDownload(_ transfer: Transfer) { downloads.append(transfer) }
    func addUpload(_ transfer: Transfer) { uploads.append(transfer) }

    func updateTransfer(id: UUID, update: (inout Transfer) -> Void) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            update(&downloads[idx])
        } else if let idx = uploads.firstIndex(where: { $0.id == id }) {
            update(&uploads[idx])
        }
    }

    func getTransfer(id: UUID) -> Transfer? {
        downloads.first(where: { $0.id == id }) ?? uploads.first(where: { $0.id == id })
    }
}

/// Thread-safe single-value sink for capturing async callback results from tests.
final class LockedResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}
