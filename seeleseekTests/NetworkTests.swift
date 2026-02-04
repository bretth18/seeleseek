import XCTest
import Network
@testable import seeleseek

/// Tests for the network layer - protocol encoding, message parsing, and local connections
final class NetworkTests: XCTestCase {

    // MARK: - Protocol Message Tests

    func testLoginMessageFormat() throws {
        let message = MessageBuilder.loginMessage(username: "testuser", password: "testpass")

        // Login message: code 1, then username, password, version, hash, minor version
        XCTAssertGreaterThan(message.count, 10, "Login message should have content")

        // First 4 bytes are length
        let length = message.readUInt32(at: 0)
        XCTAssertEqual(length, UInt32(message.count - 4), "Length prefix should match payload size")

        // Next 4 bytes are message code (1 for login)
        let code = message.readUInt32(at: 4)
        XCTAssertEqual(code, 1, "Login message code should be 1")
    }

    func testFileSearchMessageFormat() throws {
        let token: UInt32 = 12345
        let query = "test query"
        let message = MessageBuilder.fileSearch(token: token, query: query)

        let length = message.readUInt32(at: 0)
        XCTAssertEqual(length, UInt32(message.count - 4))

        let code = message.readUInt32(at: 4)
        XCTAssertEqual(code, 26, "FileSearch message code should be 26")

        // Token at offset 8
        let readToken = message.readUInt32(at: 8)
        XCTAssertEqual(readToken, token)
    }

    func testSetListenPortMessageFormat() throws {
        let port: UInt32 = 2244
        let obfuscatedPort: UInt32 = 2245
        let message = MessageBuilder.setListenPortMessage(port: port, obfuscatedPort: obfuscatedPort)

        let code = message.readUInt32(at: 4)
        XCTAssertEqual(code, 2, "SetListenPort message code should be 2")

        let readPort = message.readUInt32(at: 8)
        XCTAssertEqual(readPort, port)
    }

    func testPierceFirewallMessageFormat() throws {
        let token: UInt32 = 99999

        var message = Data()
        message.appendUInt32(5) // length: 1 byte code + 4 byte token
        message.appendUInt8(0)  // PierceFirewall code
        message.appendUInt32(token)

        XCTAssertEqual(message.count, 9)
        XCTAssertEqual(message.readByte(at: 4), 0)
        XCTAssertEqual(message.readUInt32(at: 5), token)
    }

    // MARK: - Data Extension Tests

    func testDataReadWrite() throws {
        var data = Data()

        // Test UInt8
        data.appendUInt8(255)
        XCTAssertEqual(data.readByte(at: 0), 255)

        // Test UInt16
        data.appendUInt16(0xABCD)
        XCTAssertEqual(data.readUInt16(at: 1), 0xABCD)

        // Test UInt32
        data.appendUInt32(0x12345678)
        XCTAssertEqual(data.readUInt32(at: 3), 0x12345678)

        // Test UInt64
        data.appendUInt64(0x123456789ABCDEF0)
        XCTAssertEqual(data.readUInt64(at: 7), 0x123456789ABCDEF0)

        // Test String
        var strData = Data()
        strData.appendString("hello")
        XCTAssertEqual(strData.readUInt32(at: 0), 5) // length prefix
        let readStr = strData.readString(at: 0)
        XCTAssertEqual(readStr?.string, "hello")
    }

    func testLittleEndianEncoding() throws {
        var data = Data()
        data.appendUInt32(0x01020304)

        // Little endian: least significant byte first
        XCTAssertEqual(data[0], 0x04)
        XCTAssertEqual(data[1], 0x03)
        XCTAssertEqual(data[2], 0x02)
        XCTAssertEqual(data[3], 0x01)
    }

    // MARK: - Local Loopback Connection Tests

    func testListenerStartsOnAvailablePort() async throws {
        let listener = ListenerService()

        let ports = try await listener.start()

        XCTAssertGreaterThan(ports.port, 0, "Should bind to a port")
        XCTAssertEqual(ports.obfuscatedPort, ports.port + 1, "Obfuscated port should be port + 1")

        await listener.stop()
    }

    func testLocalPeerConnection() async throws {
        // Start a local listener
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

        XCTAssertNotNil(incomingConnection, "Should receive incoming connection")

        await peer.disconnect()
        await listener.stop()
    }

    func testPierceFirewallHandshake() async throws {
        // This tests the full handshake sequence
        let listener = ListenerService()
        let expectation = XCTestExpectation(description: "Receive PierceFirewall")
        var receivedData: Data?

        await listener.setOnNewConnection { connection, _ in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        receivedData = data
                        expectation.fulfill()
                    }
                }
            }
            connection.start(queue: .global())
        }

        let ports = try await listener.start()

        let peerInfo = PeerConnection.PeerInfo(username: "handshaketest", ip: "127.0.0.1", port: Int(ports.port))
        let peer = PeerConnection(peerInfo: peerInfo, token: 54321)

        try await peer.connect()
        try await peer.sendPierceFirewall()

        await fulfillment(of: [expectation], timeout: 5.0)

        // Verify PierceFirewall message format
        XCTAssertNotNil(receivedData)
        if let data = receivedData {
            XCTAssertGreaterThanOrEqual(data.count, 9, "PierceFirewall should be at least 9 bytes")
            let code = data.readByte(at: 4)
            XCTAssertEqual(code, 0, "PierceFirewall code should be 0")
            let token = data.readUInt32(at: 5)
            XCTAssertEqual(token, 54321, "Token should match")
        }

        await peer.disconnect()
        await listener.stop()
    }

    // MARK: - Search Reply Parsing Tests

    func testSearchReplyParsing() throws {
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
            XCTFail("Failed to read username")
            return
        }
        XCTAssertEqual(username.string, "testpeer")
        offset += username.bytesConsumed

        // Token
        let token = payload.readUInt32(at: offset)
        XCTAssertEqual(token, 12345)
        offset += 4

        // File count
        let fileCount = payload.readUInt32(at: offset)
        XCTAssertEqual(fileCount, 2)
    }
}

// MARK: - Performance Tests

extension NetworkTests {
    func testMessageBuilderPerformance() throws {
        measure {
            for _ in 0..<1000 {
                _ = MessageBuilder.fileSearch(token: UInt32.random(in: 0...UInt32.max), query: "test query string")
            }
        }
    }

    func testDataExtensionPerformance() throws {
        measure {
            var data = Data()
            for i in 0..<1000 {
                data.appendUInt32(UInt32(i))
                data.appendString("test string \(i)")
            }
        }
    }
}
