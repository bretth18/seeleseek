import XCTest
import Network
@testable import seeleseek

final class PeerProtocolTests: XCTestCase {

    var listener: NWListener?
    var serverConnection: NWConnection?

    override func tearDown() {
        listener?.cancel()
        serverConnection?.cancel()
        super.tearDown()
    }

    // MARK: - Message Format Tests

    func testPierceFirewallMessageFormat() {
        let token: UInt32 = 12345
        let message = MessageBuilder.pierceFirewallMessage(token: token)

        // Expected: [length=5 as uint32][code=0 as uint8][token as uint32]
        // Total: 9 bytes
        XCTAssertEqual(message.count, 9)

        // Check length field (first 4 bytes, little-endian)
        let length = message.readUInt32(at: 0)
        XCTAssertEqual(length, 5) // 1 byte code + 4 bytes token

        // Check code (byte 4)
        let code = message.readByte(at: 4)
        XCTAssertEqual(code, 0) // PierceFirewall code

        // Check token (bytes 5-8, little-endian)
        let parsedToken = message.readUInt32(at: 5)
        XCTAssertEqual(parsedToken, token)

        print("✅ PierceFirewall message format correct: \(message.map { String(format: "%02x", $0) }.joined(separator: " "))")
    }

    func testPeerInitMessageFormat() {
        let username = "testuser"
        let connType = "P"
        let token: UInt32 = 67890
        let message = MessageBuilder.peerInitMessage(username: username, connectionType: connType, token: token)

        // Expected: [length][code=1][username_len][username][type_len][type][token]
        XCTAssertGreaterThan(message.count, 9)

        // Check code
        let code = message.readByte(at: 4)
        XCTAssertEqual(code, 1) // PeerInit code

        print("✅ PeerInit message format correct: \(message.prefix(30).map { String(format: "%02x", $0) }.joined(separator: " "))...")
    }

    func testSearchReplyParsing() {
        // Build a mock SearchReply payload (uncompressed for testing)
        var payload = Data()

        // Username
        let username = "testpeer"
        payload.appendString(username)

        // Token
        let token: UInt32 = 99999
        payload.appendUInt32(token)

        // File count
        payload.appendUInt32(2) // 2 files

        // File 1
        payload.appendUInt8(1) // code
        payload.appendString("Music\\Artist\\Album\\Song1.mp3")
        payload.appendUInt64(5_000_000) // 5 MB
        payload.appendString("mp3")
        payload.appendUInt32(2) // 2 attributes
        payload.appendUInt32(0) // bitrate type
        payload.appendUInt32(320) // 320 kbps
        payload.appendUInt32(1) // duration type
        payload.appendUInt32(240) // 4 minutes

        // File 2
        payload.appendUInt8(1) // code
        payload.appendString("Music\\Artist\\Album\\Song2.flac")
        payload.appendUInt64(30_000_000) // 30 MB
        payload.appendString("flac")
        payload.appendUInt32(1) // 1 attribute
        payload.appendUInt32(1) // duration type
        payload.appendUInt32(300) // 5 minutes

        // Free slots, speed, queue
        payload.appendBool(true)
        payload.appendUInt32(1000000) // 1 MB/s
        payload.appendUInt32(5) // 5 in queue

        // Parse it
        let parsed = MessageParser.parseSearchReply(payload)

        XCTAssertNotNil(parsed, "Failed to parse search reply")
        XCTAssertEqual(parsed?.username, username)
        XCTAssertEqual(parsed?.token, token)
        XCTAssertEqual(parsed?.files.count, 2)
        XCTAssertEqual(parsed?.freeSlots, true)
        XCTAssertEqual(parsed?.uploadSpeed, 1000000)
        XCTAssertEqual(parsed?.queueLength, 5)

        if let file1 = parsed?.files.first {
            XCTAssertTrue(file1.filename.contains("Song1.mp3"))
            XCTAssertEqual(file1.size, 5_000_000)
        }

        print("✅ SearchReply parsing works correctly")
    }

    // MARK: - Integration Test with Local Server

    func testPeerConnectionWithLocalServer() async throws {
        let expectation = XCTestExpectation(description: "Receive search results")

        // Start a local TCP server
        let port: UInt16 = 51234
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        var receivedResults: [SearchResult] = []

        listener.newConnectionHandler = { [weak self] connection in
            self?.serverConnection = connection
            print("🔵 Test server: Client connected")

            connection.stateUpdateHandler = { state in
                print("🔵 Test server connection state: \(state)")
            }

            connection.start(queue: .global())

            // Receive the PierceFirewall message
            connection.receive(minimumIncompleteLength: 9, maximumLength: 100) { data, _, _, error in
                if let data = data {
                    print("🔵 Test server received: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")

                    // Verify it's a valid PierceFirewall
                    let length = data.readUInt32(at: 0)
                    let code = data.readByte(at: 4)
                    let token = data.readUInt32(at: 5)

                    print("🔵 Received PierceFirewall: length=\(length ?? 0), code=\(code ?? 255), token=\(token ?? 0)")

                    // Send back a SearchReply
                    Task {
                        try await Task.sleep(for: .milliseconds(100))
                        let reply = self?.buildSearchReplyMessage(token: token ?? 0)
                        connection.send(content: reply, completion: .contentProcessed { error in
                            if let error = error {
                                print("🔴 Test server send error: \(error)")
                            } else {
                                print("🔵 Test server sent SearchReply")
                            }
                        })
                    }
                }
            }
        }

        listener.stateUpdateHandler = { state in
            print("🔵 Test server state: \(state)")
        }

        listener.start(queue: .global())

        // Wait for listener to be ready
        try await Task.sleep(for: .milliseconds(200))

        // Create a PeerConnection and connect to our local server
        let peerInfo = PeerConnection.PeerInfo(username: "testserver", ip: "127.0.0.1", port: Int(port))
        let peerConnection = PeerConnection(peerInfo: peerInfo, token: 12345)

        // Set up callback to receive results
        await peerConnection.setOnSearchReply { token, results in
            print("✅ Received \(results.count) search results for token \(token)")
            receivedResults = results
            expectation.fulfill()
        }

        // Connect
        try await peerConnection.connect()
        print("✅ Connected to test server")

        // Send PierceFirewall
        try await peerConnection.sendPierceFirewall()
        print("✅ Sent PierceFirewall")

        // Wait for results
        await fulfillment(of: [expectation], timeout: 5.0)

        // Verify results
        XCTAssertGreaterThan(receivedResults.count, 0, "Should have received search results")
        print("✅ Test passed: Received \(receivedResults.count) results")
    }

    // MARK: - Helpers

    private func buildSearchReplyMessage(token: UInt32) -> Data {
        var payload = Data()

        // Username
        payload.appendString("testserver")

        // Token
        payload.appendUInt32(token)

        // File count
        payload.appendUInt32(1)

        // File 1
        payload.appendUInt8(1)
        payload.appendString("Music\\Test\\TestSong.mp3")
        payload.appendUInt64(4_000_000)
        payload.appendString("mp3")
        payload.appendUInt32(1)
        payload.appendUInt32(0) // bitrate type
        payload.appendUInt32(256) // 256 kbps

        // Free slots, speed, queue
        payload.appendBool(true)
        payload.appendUInt32(500000)
        payload.appendUInt32(0)

        // Wrap with message header (4-byte code for peer message)
        var message = Data()
        message.appendUInt32(UInt32(4 + payload.count)) // length
        message.appendUInt32(9) // SearchReply code
        message.append(payload)

        return message
    }
}
