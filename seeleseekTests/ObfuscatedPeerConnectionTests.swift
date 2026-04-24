import Testing
import Foundation
import Network
@testable import SeeleseekCore

/// End-to-end integration tests for the ROTATED obfuscated peer protocol.
/// The codec itself is unit-tested in ObfuscationCodecTests; these tests
/// exercise the full PeerConnection send/receive paths wrapped around the
/// codec, over real loopback TCP.
@Suite("Obfuscated Peer Connection E2E", .serialized)
struct ObfuscatedPeerConnectionTests {

    // MARK: - Send path
    //
    // Assert that a PeerConnection flagged isObfuscated=true produces wire
    // bytes that decode back to the exact plain payload a non-obfuscated peer
    // would have sent. Anything less and the wire format has drifted.

    @Test("Obfuscated send: PierceFirewall wire bytes decode to the plain payload")
    func obfuscatedSendDecodesThroughCodec() async throws {
        let listener = try NWListener(using: .tcp, on: .any)

        let receivedActor = BytesCollector()
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            Self.drainLoop(conn: conn, into: receivedActor)
        }
        let boundPort = await Self.waitForReady(listener: listener)
        defer { listener.cancel() }

        let peerInfo = PeerConnection.PeerInfo(username: "", ip: "127.0.0.1", port: Int(boundPort))
        let sender = PeerConnection(peerInfo: peerInfo, token: 54321, isObfuscated: true)
        try await sender.connect()
        try await sender.sendPierceFirewall()

        // Wait for bytes to arrive. We keep the polling tight to keep the test
        // snappy under normal conditions but cap it so a silent wire surfaces
        // as a clear timeout rather than an infinite hang.
        let minWireBytes = 4 + 4 + 5 // key + enc(len) + enc(code+token)
        let bytes = try await receivedActor.waitForAtLeast(minWireBytes, timeout: .seconds(3))

        // Decode. The payload must match the plain PierceFirewall body that
        // MessageBuilder would have produced (without the length prefix).
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: bytes))
        let plainWire = MessageBuilder.pierceFirewallMessage(token: 54321)
        let expectedPayload = Data(plainWire.dropFirst(4))
        #expect(decoded.payload == expectedPayload,
                "obfuscated send produced wire bytes that don't match the plain PierceFirewall payload")

        await sender.disconnect()
    }

    // MARK: - Receive path
    //
    // Feed a PeerConnection obfuscated wire bytes crafted by the codec, verify
    // the connection emits the matching high-level event. This proves the
    // receive-side decode + existing message framing work together.

    @Test("Obfuscated receive: a codec-encoded PierceFirewall surfaces as a .pierceFirewall event")
    func obfuscatedReceiveEmitsEvent() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let inboundStream = AsyncStream<NWConnection> { cont in
            listener.newConnectionHandler = { cont.yield($0) }
        }
        let boundPort = await Self.waitForReady(listener: listener)
        defer { listener.cancel() }

        // Raw sender; we'll handcraft the wire.
        let senderNW = NWConnection(
            to: .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: boundPort)!),
            using: .tcp
        )
        senderNW.start(queue: .global())
        defer { senderNW.cancel() }

        var iter = inboundStream.makeAsyncIterator()
        let inboundNW = try #require(await iter.next(), "listener did not surface inbound connection")

        let receiver = PeerConnection(
            connection: inboundNW,
            isIncoming: true,
            autoStartReceiving: true,
            isObfuscated: true
        )

        // Kick off accept so the receive loop starts; accept resumes when NWConnection
        // hits .ready, then the startReceiving() receive loop runs.
        let accepted = Task { try await receiver.accept() }

        // Watch for a PierceFirewall event.
        let eventTask = Task { () -> UInt32? in
            for await event in receiver.events {
                if case .pierceFirewall(let token) = event {
                    return token
                }
            }
            return nil
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(3))
            eventTask.cancel()
        }
        defer { watchdog.cancel() }

        // Wait until accept resolves so the receive loop is live before we
        // push wire bytes (avoids a race where bytes land before startReceiving
        // has armed the first receive call — NWConnection buffers them, but
        // relying on that is fragile).
        try await accepted.value

        // Build and send a PierceFirewall wire message through the codec.
        let plainWire = MessageBuilder.pierceFirewallMessage(token: 98765)
        let payload = Data(plainWire.dropFirst(4))
        let obfuscated = ObfuscationCodec.encodeMessage(payload: payload)
        try await Self.sendAll(senderNW, obfuscated)

        let token = try #require(await eventTask.value, "receiver never emitted .pierceFirewall event")
        #expect(token == 98765)
    }

    // MARK: - Bidirectional
    //
    // Mixed-fleet sanity: a plain PeerConnection talks to a plain raw listener,
    // and an obfuscated PeerConnection on a different socket talks to a raw
    // listener decoding via the codec. Verifies the two paths don't cross-
    // contaminate state (single process, concurrent, distinct sockets).

    @Test("Mixed fleet: plain and obfuscated PeerConnections operate independently")
    func mixedPlainAndObfuscatedFleetBehaveIndependently() async throws {
        let plainListener = try NWListener(using: .tcp, on: .any)
        let obfListener = try NWListener(using: .tcp, on: .any)

        let plainCollector = BytesCollector()
        let obfCollector = BytesCollector()
        plainListener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            Self.drainLoop(conn: conn, into: plainCollector)
        }
        obfListener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            Self.drainLoop(conn: conn, into: obfCollector)
        }
        let plainPort = await Self.waitForReady(listener: plainListener)
        let obfPort = await Self.waitForReady(listener: obfListener)
        defer { plainListener.cancel(); obfListener.cancel() }

        let plainSender = PeerConnection(
            peerInfo: .init(username: "", ip: "127.0.0.1", port: Int(plainPort)),
            token: 111,
            isObfuscated: false
        )
        let obfSender = PeerConnection(
            peerInfo: .init(username: "", ip: "127.0.0.1", port: Int(obfPort)),
            token: 222,
            isObfuscated: true
        )

        try await plainSender.connect()
        try await obfSender.connect()

        try await plainSender.sendPierceFirewall()
        try await obfSender.sendPierceFirewall()

        let plainBytes = try await plainCollector.waitForAtLeast(9, timeout: .seconds(3))
        let obfBytes = try await obfCollector.waitForAtLeast(13, timeout: .seconds(3))

        // Plain listener sees the MessageBuilder output verbatim.
        #expect(plainBytes.prefix(9) == MessageBuilder.pierceFirewallMessage(token: 111))

        // Obfuscated listener sees wire bytes that decode to the plain payload.
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: obfBytes))
        let expectedObf = Data(MessageBuilder.pierceFirewallMessage(token: 222).dropFirst(4))
        #expect(decoded.payload == expectedObf)

        await plainSender.disconnect()
        await obfSender.disconnect()
    }

    // MARK: - Helpers

    /// Thread-safe append-only bytes accumulator for raw NWConnection receivers.
    actor BytesCollector {
        private var buffer = Data()

        func append(_ data: Data) { buffer.append(data) }
        func snapshot() -> Data { buffer }

        /// Poll until at least `count` bytes are buffered, or throw on timeout.
        func waitForAtLeast(_ count: Int, timeout: Duration) async throws -> Data {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while buffer.count < count {
                if ContinuousClock.now >= deadline {
                    throw CollectorError.timeout(collected: buffer.count, expected: count)
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            return buffer
        }

        enum CollectorError: Error {
            case timeout(collected: Int, expected: Int)
        }
    }

    nonisolated static func drainLoop(conn: NWConnection, into collector: BytesCollector) {
        func next() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                if let data, !data.isEmpty {
                    Task { await collector.append(data) }
                }
                if !isComplete {
                    next()
                }
            }
        }
        next()
    }

    nonisolated static func waitForReady(listener: NWListener) async -> UInt16 {
        await withCheckedContinuation { (cont: CheckedContinuation<UInt16, Never>) in
            listener.stateUpdateHandler = { state in
                if case .ready = state, let p = listener.port {
                    cont.resume(returning: p.rawValue)
                }
            }
            listener.start(queue: .global())
        }
    }

    nonisolated static func sendAll(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }
}
