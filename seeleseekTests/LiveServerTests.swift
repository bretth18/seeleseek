import Testing
import Network
import Foundation
@testable import seeleseek

/// Live tests against the real SoulSeek server
/// These tests require network access and a valid account
@Suite("Live Server Tests", .serialized)
struct LiveServerTests {

    /// Test the full search flow against the real server
    @Test("Real server search flow")
    func realServerSearch() async throws {
        // Use test credentials - create a throwaway account for testing
        let username = "seeleseek_test_\(Int.random(in: 1000...9999))"
        let password = "testpass123"

        print("Starting live server test with username: \(username)")

        // Create server connection
        let serverConn = ServerConnection(host: "server.slsknet.org", port: 2242)

        print("Connecting to server...")
        try await serverConn.connect()
        print("Connected to server")

        // Send login
        let loginMsg = MessageBuilder.loginMessage(username: username, password: password)
        print("Sending login...")
        try await serverConn.send(loginMsg)

        // Wait for login response
        var loggedIn = false
        var serverIP: String?

        for try await data in serverConn.messages {
            guard let code = data.readUInt32(at: 4) else { continue }

            if code == 1 { // Login response
                let success = data.readByte(at: 8)
                print("Login response: success=\(success ?? 0)")

                if success == 1 {
                    loggedIn = true
                    // Parse IP
                    var offset = 9
                    if let (_, greetingLen) = data.readString(at: offset) {
                        offset += greetingLen
                        if let ip = data.readUInt32(at: offset) {
                            let b1 = ip & 0xFF
                            let b2 = (ip >> 8) & 0xFF
                            let b3 = (ip >> 16) & 0xFF
                            let b4 = (ip >> 24) & 0xFF
                            serverIP = "\(b1).\(b2).\(b3).\(b4)"
                            print("Server reports our IP: \(serverIP!)")
                        }
                    }
                } else {
                    // New account might fail - that's OK for this test
                    print("Login failed (expected for new account)")
                }
                break
            }
        }

        if !loggedIn {
            print("Could not log in - skipping rest of test")
            await serverConn.disconnect()
            return
        }

        // Send SetListenPort
        let portMsg = MessageBuilder.setListenPortMessage(port: 2234)
        try await serverConn.send(portMsg)
        print("Sent SetListenPort: 2234")

        // Send SetOnlineStatus
        let statusMsg = MessageBuilder.setOnlineStatusMessage(status: .online)
        try await serverConn.send(statusMsg)
        print("Sent SetOnlineStatus: online")

        // Send FileSearch
        let token = UInt32.random(in: 1..<0x8000_0000)
        let searchMsg = MessageBuilder.fileSearchMessage(token: token, query: "test")
        try await serverConn.send(searchMsg)
        print("Sent FileSearch: 'test' token=\(token)")

        // Listen for responses
        var connectToPeerCount = 0

        print("Waiting for responses...")

        // Collect messages for 10 seconds
        let deadline = Date().addingTimeInterval(10)

        for try await data in serverConn.messages {
            if Date() > deadline { break }

            guard let code = data.readUInt32(at: 4) else { continue }

            switch code {
            case 18: // ConnectToPeer
                connectToPeerCount += 1
                if connectToPeerCount <= 5 {
                    var offset = 8
                    if let (peerUsername, len) = data.readString(at: offset) {
                        offset += len
                        if let (connType, typeLen) = data.readString(at: offset) {
                            offset += typeLen
                            if let ip = data.readUInt32(at: offset) {
                                offset += 4
                                if let port = data.readUInt32(at: offset) {
                                    let b1 = ip & 0xFF
                                    let b2 = (ip >> 8) & 0xFF
                                    let b3 = (ip >> 16) & 0xFF
                                    let b4 = (ip >> 24) & 0xFF
                                    print("ConnectToPeer #\(connectToPeerCount): \(peerUsername) type=\(connType) ip=\(b1).\(b2).\(b3).\(b4) port=\(port)")
                                }
                            }
                        }
                    }
                }

            case 102: // EmbeddedMessage (distributed search)
                print("EmbeddedMessage received")

            default:
                if code != 32 { // Skip pings
                    print("Message code: \(code)")
                }
            }
        }

        print("Test complete:")
        print("   - ConnectToPeer messages: \(connectToPeerCount)")
        print("   - Server IP: \(serverIP ?? "unknown")")

        await serverConn.disconnect()

        #expect(connectToPeerCount > 0, "Should receive at least one ConnectToPeer")
    }

    /// Test that we can establish an incoming connection on our listen port
    @Test("Listener accepts connections")
    func listenerAcceptsConnections() async throws {
        let listener = ListenerService()

        let ports = try await listener.start()
        print("Listening on port \(ports.port)")

        // Connect to ourselves to verify listener works
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: ports.port)!)
        let conn = NWConnection(to: endpoint, using: .tcp)

        await confirmation("Receive connection") { confirm in
            await listener.setOnNewConnection { _, _ in
                print("Received incoming connection!")
                confirm()
            }

            conn.start(queue: .global())

            // Give time for connection to establish
            try? await Task.sleep(for: .seconds(3))
        }

        conn.cancel()
        await listener.stop()
    }
}
