import Foundation
import Network
import Synchronization
@testable import SeeleseekCore

/// A real `PeerConnection` dialed to a local TCP server. A `reading` server
/// records every byte; a non-reading one never drains its socket, so once
/// `stall()` fills the kernel buffers, every later `send` on the connection
/// stays pending — the backpressure a slow real peer produces.
nonisolated final class LoopbackPeer: Sendable {
    let connection: PeerConnection
    private let listener: NWListener
    private let received: ByteLog

    static func make(username: String, reading: Bool) async throws -> LoopbackPeer {
        let listener = try NWListener(using: .tcp, on: .any)
        let received = ByteLog()
        listener.newConnectionHandler = { server in
            server.start(queue: .global())
            guard reading else { return }
            @Sendable func receiveNext() {
                server.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
                    if let data { received.bytes.withLock { $0.append(data) } }
                    if error == nil, !isComplete { receiveNext() }
                }
            }
            receiveNext()
        }
        listener.start(queue: .global())

        let deadline = Date().addingTimeInterval(2)
        while listener.port == nil || listener.port?.rawValue == 0 {
            guard Date() < deadline else { throw LoopbackError.listenerNotReady }
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = Int(listener.port!.rawValue)

        let connection = PeerConnection(peerInfo: .init(username: username, ip: "127.0.0.1", port: port))
        try await connection.connect()
        return LoopbackPeer(connection: connection, listener: listener, received: received)
    }

    private init(connection: PeerConnection, listener: NWListener, received: ByteLog) {
        self.connection = connection
        self.listener = listener
        self.received = received
    }

    /// Queues more bytes than loopback buffering holds on a server that
    /// never reads, so this connection's later sends stop completing.
    /// `close()` fails the pending send.
    func stall() async {
        let connection = connection
        Task { try? await connection.send(Data(count: 64 << 20)) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    var receivedBytes: Data { received.bytes.withLock { $0 } }

    /// Polls until `expected` appears contiguously in the received stream.
    func waitToReceive(_ expected: Data, timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if receivedBytes.range(of: expected) != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func close() async {
        await connection.disconnect()
        listener.cancel()
    }

    enum LoopbackError: Error { case listenerNotReady }

    private final class ByteLog: Sendable {
        let bytes = Mutex(Data())
    }
}
