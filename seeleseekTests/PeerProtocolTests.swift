import Testing
import Network
import Foundation
@testable import seeleseek

@Suite("Peer Protocol Tests", .serialized)
struct PeerProtocolTests {

    // MARK: - Message Format Tests

    @Test("PierceFirewall message format")
    func pierceFirewallMessageFormat() {
        let token: UInt32 = 12345
        let message = MessageBuilder.pierceFirewallMessage(token: token)

        // Expected: [length=5 as uint32][code=0 as uint8][token as uint32]
        // Total: 9 bytes
        #expect(message.count == 9)

        // Check length field (first 4 bytes, little-endian)
        let length = message.readUInt32(at: 0)
        #expect(length == 5) // 1 byte code + 4 bytes token

        // Check code (byte 4)
        let code = message.readByte(at: 4)
        #expect(code == 0) // PierceFirewall code

        // Check token (bytes 5-8, little-endian)
        let parsedToken = message.readUInt32(at: 5)
        #expect(parsedToken == token)

        print("PierceFirewall message format correct: \(message.map { String(format: "%02x", $0) }.joined(separator: " "))")
    }

    @Test("PeerInit message format")
    func peerInitMessageFormat() {
        let username = "testuser"
        let connType = "P"
        let token: UInt32 = 67890
        let message = MessageBuilder.peerInitMessage(username: username, connectionType: connType, token: token)

        // Expected: [length][code=1][username_len][username][type_len][type][token]
        #expect(message.count > 9)

        // Check code
        let code = message.readByte(at: 4)
        #expect(code == 1) // PeerInit code

        print("PeerInit message format correct: \(message.prefix(30).map { String(format: "%02x", $0) }.joined(separator: " "))...")
    }

    @Test("Search reply parsing")
    func searchReplyParsing() {
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

        #expect(parsed != nil, "Failed to parse search reply")
        #expect(parsed?.username == username)
        #expect(parsed?.token == token)
        #expect(parsed?.files.count == 2)
        #expect(parsed?.freeSlots == true)
        #expect(parsed?.uploadSpeed == 1000000)
        #expect(parsed?.queueLength == 5)

        if let file1 = parsed?.files.first {
            #expect(file1.filename.contains("Song1.mp3"))
            #expect(file1.size == 5_000_000)
        }
    }

    // MARK: - Integration Test with Local Server

    @Test("Peer connection with local server")
    func peerConnectionWithLocalServer() async throws {
        // Start a local TCP server
        let port: UInt16 = 51234
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        var receivedResults: [SearchResult] = []

        await confirmation("Receive search results") { confirm in
            listener.newConnectionHandler = { connection in
                print("Test server: Client connected")

                connection.stateUpdateHandler = { state in
                    print("Test server connection state: \(state)")
                }

                connection.start(queue: .global())

                // Receive the PierceFirewall message
                connection.receive(minimumIncompleteLength: 9, maximumLength: 100) { data, _, _, error in
                    if let data = data {
                        print("Test server received: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")

                        let length = data.readUInt32(at: 0)
                        let code = data.readByte(at: 4)
                        let token = data.readUInt32(at: 5)

                        print("Received PierceFirewall: length=\(length ?? 0), code=\(code ?? 255), token=\(token ?? 0)")

                        // Send back a SearchReply
                        Task {
                            try await Task.sleep(for: .milliseconds(100))
                            let reply = buildSearchReplyMessage(token: token ?? 0)
                            connection.send(content: reply, completion: .contentProcessed { error in
                                if let error = error {
                                    print("Test server send error: \(error)")
                                } else {
                                    print("Test server sent SearchReply")
                                }
                            })
                        }
                    }
                }
            }

            listener.stateUpdateHandler = { state in
                print("Test server state: \(state)")
            }

            listener.start(queue: .global())

            // Wait for listener to be ready
            try? await Task.sleep(for: .milliseconds(200))

            // Create a PeerConnection and connect to our local server
            let peerInfo = PeerConnection.PeerInfo(username: "testserver", ip: "127.0.0.1", port: Int(port))
            let peerConnection = PeerConnection(peerInfo: peerInfo, token: 12345)

            // Set up callback to receive results
            await peerConnection.setOnSearchReply { token, results in
                print("Received \(results.count) search results for token \(token)")
                receivedResults = results
                confirm()
            }

            // Connect
            try? await peerConnection.connect()
            print("Connected to test server")

            // Send PierceFirewall
            try? await peerConnection.sendPierceFirewall()
            print("Sent PierceFirewall")

            // Wait for results
            try? await Task.sleep(for: .seconds(3))

            await peerConnection.disconnect()
        }

        // Verify results
        #expect(receivedResults.count > 0, "Should have received search results")

        listener.cancel()
    }
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
