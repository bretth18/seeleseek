import Testing
import Network
import Foundation
@testable import seeleseek

/// Tests for the network layer - protocol encoding, message parsing, and local connections
@Suite("Network Tests")
struct NetworkTests {

    // MARK: - Protocol Message Tests

    @Test("Login message format")
    func loginMessageFormat() throws {
        let message = MessageBuilder.loginMessage(username: "testuser", password: "testpass")

        #expect(message.count > 10, "Login message should have content")

        let length = message.readUInt32(at: 0)
        #expect(length == UInt32(message.count - 4), "Length prefix should match payload size")

        let code = message.readUInt32(at: 4)
        #expect(code == 1, "Login message code should be 1")
    }

    @Test("File search message format")
    func fileSearchMessageFormat() throws {
        let token: UInt32 = 12345
        let query = "test query"
        let message = MessageBuilder.fileSearchMessage(token: token, query: query)

        let length = message.readUInt32(at: 0)
        #expect(length == UInt32(message.count - 4))

        let code = message.readUInt32(at: 4)
        #expect(code == 26, "FileSearch message code should be 26")

        let readToken = message.readUInt32(at: 8)
        #expect(readToken == token)
    }

    @Test("SetListenPort message format")
    func setListenPortMessageFormat() throws {
        let port: UInt32 = 2244
        let message = MessageBuilder.setListenPortMessage(port: port)

        let code = message.readUInt32(at: 4)
        #expect(code == 2, "SetListenPort message code should be 2")

        let readPort = message.readUInt32(at: 8)
        #expect(readPort == port)
    }

    @Test("PierceFirewall message format")
    func pierceFirewallMessageFormat() throws {
        let token: UInt32 = 99999

        var message = Data()
        message.appendUInt32(5) // length: 1 byte code + 4 byte token
        message.appendUInt8(0)  // PierceFirewall code
        message.appendUInt32(token)

        #expect(message.count == 9)
        #expect(message.readByte(at: 4) == 0)
        #expect(message.readUInt32(at: 5) == token)
    }

    // MARK: - Data Extension Tests

    @Test("Data read/write roundtrip")
    func dataReadWrite() throws {
        var data = Data()

        // Test UInt8
        data.appendUInt8(255)
        #expect(data.readByte(at: 0) == 255)

        // Test UInt16
        data.appendUInt16(0xABCD)
        #expect(data.readUInt16(at: 1) == 0xABCD)

        // Test UInt32
        data.appendUInt32(0x12345678)
        #expect(data.readUInt32(at: 3) == 0x12345678)

        // Test UInt64
        data.appendUInt64(0x123456789ABCDEF0)
        #expect(data.readUInt64(at: 7) == 0x123456789ABCDEF0)

        // Test String
        var strData = Data()
        strData.appendString("hello")
        #expect(strData.readUInt32(at: 0) == 5) // length prefix
        let readStr = strData.readString(at: 0)
        #expect(readStr?.string == "hello")
    }

    @Test("Little-endian encoding")
    func littleEndianEncoding() throws {
        var data = Data()
        data.appendUInt32(0x01020304)

        // Little endian: least significant byte first
        #expect(data[0] == 0x04)
        #expect(data[1] == 0x03)
        #expect(data[2] == 0x02)
        #expect(data[3] == 0x01)
    }

    // MARK: - Local Loopback Connection Tests

    @Test("Listener starts on available port")
    func listenerStartsOnAvailablePort() async throws {
        let listener = ListenerService()

        let ports = try await listener.start()

        #expect(ports.port > 0, "Should bind to a port")
        #expect(ports.obfuscatedPort == ports.port + 1, "Obfuscated port should be port + 1")

        await listener.stop()
    }

    @Test("Local peer connection")
    func localPeerConnection() async throws {
        let listener = ListenerService()
        var incomingConnection: NWConnection?

        await listener.setOnNewConnection { connection, _ in
            incomingConnection = connection
        }

        let ports = try await listener.start()

        // Connect to ourselves
        let peerInfo = PeerConnection.PeerInfo(username: "localtest", ip: "127.0.0.1", port: Int(ports.port))
        let peer = PeerConnection(peerInfo: peerInfo, token: 12345)

        try await peer.connect()

        // Give time for incoming connection to be received
        try await Task.sleep(for: .milliseconds(100))

        #expect(incomingConnection != nil, "Should receive incoming connection")

        await peer.disconnect()
        await listener.stop()
    }

    @Test("PierceFirewall handshake")
    func pierceFirewallHandshake() async throws {
        let listener = ListenerService()
        var receivedData: Data?

        let ports = try await listener.start()

        await confirmation("Receive PierceFirewall") { confirm in
            await listener.setOnNewConnection { connection, _ in
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                            receivedData = data
                            confirm()
                        }
                    }
                }
                connection.start(queue: .global())
            }

            let peerInfo = PeerConnection.PeerInfo(username: "handshaketest", ip: "127.0.0.1", port: Int(ports.port))
            let peer = PeerConnection(peerInfo: peerInfo, token: 54321)

            try? await peer.connect()
            try? await peer.sendPierceFirewall()

            // Wait for data to arrive
            try? await Task.sleep(for: .seconds(3))

            await peer.disconnect()
        }

        // Verify PierceFirewall message format
        #expect(receivedData != nil)
        if let data = receivedData {
            #expect(data.count >= 9, "PierceFirewall should be at least 9 bytes")
            let code = data.readByte(at: 4)
            #expect(code == 0, "PierceFirewall code should be 0")
            let token = data.readUInt32(at: 5)
            #expect(token == 54321, "Token should match")
        }

        await listener.stop()
    }

    // MARK: - Search Reply Parsing Tests

    @Test("Search reply parsing")
    func searchReplyParsing() throws {
        // Build a mock SearchReply message
        var payload = Data()

        // Username
        payload.appendString("testpeer")

        // Token
        payload.appendUInt32(12345)

        // File count
        payload.appendUInt32(2)

        // File 1
        payload.appendUInt8(1) // code
        payload.appendString("Music\\Artist\\Album\\Song.mp3")
        payload.appendUInt64(5_000_000) // size
        payload.appendString("mp3") // extension
        payload.appendUInt32(2) // attribute count
        payload.appendUInt32(0) // bitrate type
        payload.appendUInt32(320) // bitrate value
        payload.appendUInt32(1) // duration type
        payload.appendUInt32(240) // duration value

        // File 2
        payload.appendUInt8(1)
        payload.appendString("Music\\Artist\\Album\\Song2.flac")
        payload.appendUInt64(30_000_000)
        payload.appendString("flac")
        payload.appendUInt32(1)
        payload.appendUInt32(1) // duration
        payload.appendUInt32(300)

        // Free slots, speed, queue
        payload.appendBool(true)
        payload.appendUInt32(2_000_000)
        payload.appendUInt32(5)

        // Now parse it
        var offset = 0

        // Username
        guard let username = payload.readString(at: offset) else {
            Issue.record("Failed to read username")
            return
        }
        #expect(username.string == "testpeer")
        offset += username.bytesConsumed

        // Token
        let token = payload.readUInt32(at: offset)
        #expect(token == 12345)
        offset += 4

        // File count
        let fileCount = payload.readUInt32(at: offset)
        #expect(fileCount == 2)
    }

    // MARK: - Performance Tests

    @Test("Message builder throughput")
    func messageBuilderPerformance() throws {
        for _ in 0..<1000 {
            _ = MessageBuilder.fileSearchMessage(token: UInt32.random(in: 0...UInt32.max), query: "test query string")
        }
    }

    @Test("Data extension throughput")
    func dataExtensionPerformance() throws {
        var data = Data()
        for i in 0..<1000 {
            data.appendUInt32(UInt32(i))
            data.appendString("test string \(i)")
        }
    }
}
