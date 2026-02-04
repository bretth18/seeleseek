import Foundation
import Network

/// Simple protocol test that can be triggered from the app
class ProtocolTest {

    @MainActor
    static func runLocalServerTest() async {
        print("🧪 Starting local protocol test...")

        do {
            // Start a local TCP server on a random high port
            let port: UInt16 = 51234
            let serverTask = Task {
                await runTestServer(port: port)
            }

            // Give server time to start
            try await Task.sleep(for: .milliseconds(200))

            // Create a PeerConnection and connect to our local server
            let peerInfo = PeerConnection.PeerInfo(username: "testserver", ip: "127.0.0.1", port: Int(port))
            let peerConnection = PeerConnection(peerInfo: peerInfo, token: 12345)

            var receivedResults: [SearchResult] = []
            let resultsContinuation = AsyncStream<[SearchResult]>.makeStream()

            // Set up callback to receive results
            await peerConnection.setOnSearchReply { token, results in
                print("🧪 ✅ Received \(results.count) search results for token \(token)")
                for result in results.prefix(3) {
                    print("🧪   - \(result.filename) (\(result.formattedSize))")
                }
                resultsContinuation.continuation.yield(results)
                resultsContinuation.continuation.finish()
            }

            // Connect
            print("🧪 Connecting to local test server...")
            try await peerConnection.connect()
            print("🧪 ✅ Connected")

            // Send PierceFirewall
            print("🧪 Sending PierceFirewall...")
            try await peerConnection.sendPierceFirewall()
            print("🧪 ✅ PierceFirewall sent")

            // Wait for results (with timeout)
            print("🧪 Waiting for search results...")

            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(5))
                return [SearchResult]()
            }

            for await results in resultsContinuation.stream {
                receivedResults = results
                break
            }

            timeoutTask.cancel()
            serverTask.cancel()

            if receivedResults.isEmpty {
                print("🧪 ❌ TEST FAILED: No results received")
            } else {
                print("🧪 ✅ TEST PASSED: Protocol working correctly!")
                print("🧪 Received \(receivedResults.count) results")
            }

        } catch {
            print("🧪 ❌ TEST FAILED: \(error)")
        }
    }

    private static func runTestServer(port: UInt16) async {
        print("🧪 Starting test server on port \(port)...")

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            print("🧪 ❌ Failed to create listener")
            return
        }

        let serverReady = AsyncStream<Void>.makeStream()

        listener.stateUpdateHandler = { state in
            print("🧪 Server state: \(state)")
            if case .ready = state {
                serverReady.continuation.yield()
            }
        }

        listener.newConnectionHandler = { connection in
            print("🧪 Server: Client connected!")
            handleTestClient(connection)
        }

        listener.start(queue: .global())

        // Wait for ready or cancellation
        for await _ in serverReady.stream {
            break
        }

        // Keep running until cancelled
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }

        listener.cancel()
    }

    private static func handleTestClient(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            print("🧪 Server connection state: \(state)")
        }

        connection.start(queue: .global())

        // Receive the PierceFirewall message
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
            if let error = error {
                print("🧪 Server receive error: \(error)")
                return
            }

            guard let data = data else {
                print("🧪 Server: No data received")
                return
            }

            print("🧪 Server received \(data.count) bytes: \(data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")

            // Parse PierceFirewall
            if data.count >= 9 {
                let length = data.readUInt32(at: 0)
                let code = data.readByte(at: 4)
                let token = data.readUInt32(at: 5)
                print("🧪 Server: Received PierceFirewall - length=\(length ?? 0), code=\(code ?? 255), token=\(token ?? 0)")

                // Send SearchReply after a short delay
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    let reply = buildSearchReplyMessage(token: token ?? 0)
                    print("🧪 Server: Sending SearchReply (\(reply.count) bytes)")
                    connection.send(content: reply, completion: .contentProcessed { error in
                        if let error = error {
                            print("🧪 Server send error: \(error)")
                        } else {
                            print("🧪 Server: SearchReply sent successfully")
                        }
                    })
                }
            }
        }
    }

    private static func buildSearchReplyMessage(token: UInt32) -> Data {
        var payload = Data()

        // Username
        payload.appendString("testserver")

        // Token
        payload.appendUInt32(token)

        // File count
        payload.appendUInt32(3)

        // File 1
        payload.appendUInt8(1)
        payload.appendString("Music\\Test Artist\\Test Album\\Test Song 1.mp3")
        payload.appendUInt64(4_500_000)
        payload.appendString("mp3")
        payload.appendUInt32(2)
        payload.appendUInt32(0) // bitrate
        payload.appendUInt32(320)
        payload.appendUInt32(1) // duration
        payload.appendUInt32(235)

        // File 2
        payload.appendUInt8(1)
        payload.appendString("Music\\Test Artist\\Test Album\\Test Song 2.flac")
        payload.appendUInt64(25_000_000)
        payload.appendString("flac")
        payload.appendUInt32(1)
        payload.appendUInt32(1)
        payload.appendUInt32(248)

        // File 3
        payload.appendUInt8(1)
        payload.appendString("Music\\Another Artist\\Great Album\\Amazing Track.mp3")
        payload.appendUInt64(8_200_000)
        payload.appendString("mp3")
        payload.appendUInt32(2)
        payload.appendUInt32(0)
        payload.appendUInt32(256)
        payload.appendUInt32(1)
        payload.appendUInt32(312)

        // Free slots, speed, queue
        payload.appendBool(true)
        payload.appendUInt32(1_500_000) // 1.5 MB/s
        payload.appendUInt32(2)

        // Wrap with message header (4-byte code for peer message after handshake)
        var message = Data()
        message.appendUInt32(UInt32(4 + payload.count)) // length (code + payload)
        message.appendUInt32(9) // SearchReply peer message code
        message.append(payload)

        print("🧪 Built SearchReply: \(message.count) bytes, header: \(message.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")

        return message
    }
}
