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
        let (matched, ambiguous) = DownloadManager.matchPendingDownload(request: request, pending: pending)
        #expect(matched == 42)
        #expect(ambiguous == false)
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
        let (matched, ambiguous) = DownloadManager.matchPendingDownload(request: request, pending: pending)
        #expect(matched == 2)
        #expect(ambiguous == false)
    }

    @Test("Ambiguous same-filename fallback refuses to guess")
    func transferRoutingRefusesAmbiguousFallback() {
        let pending: [UInt32: DownloadManager.PendingDownload] = [
            1: .init(transferId: UUID(), username: "alice", filename: "shared.flac", size: 1000),
            2: .init(transferId: UUID(), username: "bob",   filename: "shared.flac", size: 1000)
        ]
        // request.username is empty (reused-connection path) — can't disambiguate.
        let request = TransferRequest(
            direction: .upload, token: 999, filename: "shared.flac", size: 1000, username: ""
        )
        let (matched, ambiguous) = DownloadManager.matchPendingDownload(request: request, pending: pending)
        #expect(matched == nil)
        #expect(ambiguous == true)
    }

    @Test("Single filename candidate still resolves via loose fallback")
    func transferRoutingResolvesUniqueFilename() {
        let pending: [UInt32: DownloadManager.PendingDownload] = [
            5: .init(transferId: UUID(), username: "alice", filename: "only.flac", size: 1000)
        ]
        let request = TransferRequest(
            direction: .upload, token: 999, filename: "only.flac", size: 1000, username: ""
        )
        let (matched, ambiguous) = DownloadManager.matchPendingDownload(request: request, pending: pending)
        #expect(matched == 5)
        #expect(ambiguous == false)
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
}
