import Testing
import Foundation
import Network
@testable import SeeleseekCore

/// STUN servers are queried concurrently and the first answer wins. Each
/// query times out after 2 s, so these timings separate a race from a
/// sequential fallback, and a cancelled loser from one that holds the
/// task group open until its own timeout.
@Suite("STUN server race", .serialized, .timeLimit(.minutes(1)))
struct STUNRaceTests {

    @Test("A silent server ahead in the list neither delays nor blocks a responsive server's answer")
    func silentServerDoesNotDelayAnswer() async throws {
        let silent = try await STUNStub.make(reflexiveIP: nil)
        let responsive = try await STUNStub.make(reflexiveIP: (203, 0, 113, 7))
        defer { silent.close(); responsive.close() }

        let start = ContinuousClock.now
        let ip = try await NATService().getExternalIPSTUN(servers: [
            ("127.0.0.1", silent.port), ("127.0.0.1", responsive.port),
        ])

        #expect(ip == "203.0.113.7")
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test("When every server is silent, discovery fails after one timeout, not one per server")
    func allSilentFailsAfterOneTimeout() async throws {
        let stubs = [try await STUNStub.make(reflexiveIP: nil), try await STUNStub.make(reflexiveIP: nil)]
        defer { stubs.forEach { $0.close() } }

        let start = ContinuousClock.now
        await #expect(throws: NATError.self) {
            try await NATService().getExternalIPSTUN(servers: stubs.map { ("127.0.0.1", $0.port) })
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}

/// Local UDP server answering STUN Binding Requests with a fixed
/// XOR-MAPPED-ADDRESS, or never answering when `reflexiveIP` is nil.
private nonisolated struct STUNStub {
    let listener: NWListener
    let port: UInt16

    static func make(reflexiveIP: (UInt8, UInt8, UInt8, UInt8)?) async throws -> STUNStub {
        let listener = try NWListener(using: .udp, on: .any)
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            guard let ip = reflexiveIP else { return }
            conn.receiveMessage { request, _, _, _ in
                guard let request, request.count >= 20 else { return }
                conn.send(content: bindingResponse(transactionID: request[8..<20], ip: ip), completion: .idempotent)
            }
        }
        listener.start(queue: .global())
        let deadline = Date().addingTimeInterval(2)
        while (listener.port?.rawValue ?? 0) == 0 {
            guard Date() < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
        return STUNStub(listener: listener, port: listener.port!.rawValue)
    }

    func close() { listener.cancel() }

    private static func bindingResponse(transactionID: Data, ip: (UInt8, UInt8, UInt8, UInt8)) -> Data {
        func be16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
        func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
        let cookie: UInt32 = 0x2112A442
        let addr = UInt32(ip.0) << 24 | UInt32(ip.1) << 16 | UInt32(ip.2) << 8 | UInt32(ip.3)
        let attribute = be16(0x0020) + be16(8) + Data([0x00, 0x01]) + be16(40000 ^ 0x2112) + be32(addr ^ cookie)
        return be16(0x0101) + be16(UInt16(attribute.count)) + be32(cookie) + transactionID + attribute
    }
}
