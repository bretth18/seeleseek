import Testing
import Foundation
import Network
@testable import seeleseek

/// Tests to verify bidirectional TCP communication works
@Suite("Bidirectional TCP Communication", .serialized)
struct BidirectionalTests {

    /// Test raw NWConnection bidirectional communication (no PeerConnection)
    @Test("Raw bidirectional NWConnection communication")
    func rawBidirectionalCommunication() async throws {
        // Track received data
        actor ReceivedData {
            var serverReceived = false
            var clientData: Data?
            func setServerReceived() { serverReceived = true }
            func setClientData(_ data: Data) { clientData = data }
        }
        let received = ReceivedData()

        // Create server listener with dynamic port
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)

        listener.newConnectionHandler = { serverConn in
            print("🔵 Server: Client connected")
            serverConn.stateUpdateHandler = { state in
                print("🔵 Server connection state: \(state)")
            }
            serverConn.start(queue: .global())

            // Server receives data from client
            serverConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                if let data = data {
                    print("🔵 Server received \(data.count) bytes: \(String(data: data, encoding: .utf8) ?? "?")")
                    Task { await received.setServerReceived() }

                    // Server sends response back
                    let response = "Hello from server".data(using: .utf8)!
                    serverConn.send(content: response, completion: .contentProcessed { error in
                        if let error = error {
                            print("🔴 Server send error: \(error)")
                        } else {
                            print("🔵 Server sent response")
                        }
                    })
                }
            }
        }

        listener.stateUpdateHandler = { state in
            print("🔵 Server listener state: \(state)")
        }

        listener.start(queue: .global())
        try await Task.sleep(for: .milliseconds(100))

        // Get the assigned port
        guard let port = listener.port else {
            throw TestError.noPort
        }

        // Create client connection
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let clientConn = NWConnection(to: endpoint, using: .tcp)

        clientConn.stateUpdateHandler = { state in
            print("🟢 Client state: \(state)")
            if state == .ready {
                // Set up receive BEFORE sending
                clientConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                    if let data = data {
                        print("🟢 Client received \(data.count) bytes: \(String(data: data, encoding: .utf8) ?? "?")")
                        Task { await received.setClientData(data) }
                    }
                    if let error = error {
                        print("🔴 Client receive error: \(error)")
                    }
                }

                // Send data to server
                let request = "Hello from client".data(using: .utf8)!
                clientConn.send(content: request, completion: .contentProcessed { error in
                    if let error = error {
                        print("🔴 Client send error: \(error)")
                    } else {
                        print("🟢 Client sent request")
                    }
                })
            }
        }

        clientConn.start(queue: .global())

        // Wait for both directions with polling
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            let serverGotIt = await received.serverReceived
            let clientGotIt = await received.clientData != nil
            if serverGotIt && clientGotIt { break }
        }

        let clientData = await received.clientData
        #expect(clientData != nil)
        #expect(String(data: clientData!, encoding: .utf8) == "Hello from server")

        clientConn.cancel()
        listener.cancel()
    }

    /// Test that PeerConnection can receive data sent by a server
    @Test("PeerConnection receives server data")
    func peerConnectionReceivesServerData() async throws {
        actor CallbackState {
            var received = false
            func setReceived() { received = true }
        }
        let state = CallbackState()

        // Create server with dynamic port
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)

        listener.newConnectionHandler = { serverConn in
            print("🔵 Server: Client connected")
            serverConn.start(queue: .global())

            // Wait for connection to be ready, then send data
            serverConn.stateUpdateHandler = { connState in
                print("🔵 Server conn state: \(connState)")
                if connState == .ready {
                    Task {
                        try await Task.sleep(for: .milliseconds(100))

                        // Build a simple peer message (code 9 = SearchReply)
                        var payload = Data()
                        payload.appendString("testpeer")  // username
                        payload.appendUInt32(12345)       // token
                        payload.appendUInt32(0)           // 0 files
                        payload.appendBool(true)          // free slots
                        payload.appendUInt32(100000)      // upload speed
                        payload.appendUInt32(0)           // queue length

                        var message = Data()
                        message.appendUInt32(UInt32(4 + payload.count))  // length
                        message.appendUInt32(9)                           // SearchReply code
                        message.append(payload)

                        print("🔵 Server sending \(message.count) bytes")

                        serverConn.send(content: message, completion: .contentProcessed { error in
                            if let error = error {
                                print("🔴 Server send error: \(error)")
                            } else {
                                print("🔵 Server sent SearchReply")
                            }
                        })
                    }
                }
            }
        }

        listener.start(queue: .global())
        try await Task.sleep(for: .milliseconds(100))

        guard let port = listener.port else {
            throw TestError.noPort
        }

        // Create PeerConnection
        let peerInfo = PeerConnection.PeerInfo(username: "testserver", ip: "127.0.0.1", port: Int(port.rawValue))
        let peer = PeerConnection(peerInfo: peerInfo, token: 12345)

        // Set callback BEFORE connecting
        await peer.setOnSearchReply { token, results in
            print("✅ Callback received! token=\(token), results=\(results.count)")
            Task { await state.setReceived() }
        }

        await peer.setOnMessage { code, data in
            print("📨 Generic message: code=\(code), \(data.count) bytes")
        }

        try await peer.connect()
        print("✅ Connected")

        // Wait for the callback
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if await state.received { break }
        }

        #expect(await state.received, "Should have received data in callback")

        await peer.disconnect()
        listener.cancel()
    }

    /// Test that PierceFirewall + SearchReply sequence works
    @Test("PierceFirewall then SearchReply sequence")
    func pierceFirewallThenSearchReply() async throws {
        actor State {
            var peerConnection: PeerConnection?
            var results: [SearchResult] = []
            var searchReceived = false
            func set(_ conn: PeerConnection) { peerConnection = conn }
            func setResults(_ r: [SearchResult]) {
                results = r
                searchReceived = true
            }
        }
        let state = State()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)

        listener.newConnectionHandler = { incomingConn in
            Task {
                let peerConnection = PeerConnection(connection: incomingConn, isIncoming: true)
                await state.set(peerConnection)

                await peerConnection.setOnSearchReply { token, results in
                    print("✅ SEARCH REPLY RECEIVED! token=\(token), \(results.count) results")
                    Task { await state.setResults(results) }
                }

                await peerConnection.setOnMessage { code, data in
                    print("📨 Message received: code=\(code), \(data.count) bytes")
                }

                try? await peerConnection.accept()
                print("🟢 Connection accepted")
            }
        }

        listener.start(queue: .global())
        try await Task.sleep(for: .milliseconds(200))

        guard let port = listener.port else {
            throw TestError.noPort
        }

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let peerConn = NWConnection(to: endpoint, using: .tcp)
        peerConn.start(queue: .global())
        try await Task.sleep(for: .milliseconds(500))

        // Step 1: Send PierceFirewall
        var pierceFirewall = Data()
        pierceFirewall.appendUInt32(5)        // length = 1 (code) + 4 (token)
        pierceFirewall.appendUInt8(0)         // code = 0 = PierceFirewall
        pierceFirewall.appendUInt32(12345)    // token

        print("📤 PierceFirewall: \(pierceFirewall.map { String(format: "%02x", $0) }.joined(separator: " "))")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peerConn.send(content: pierceFirewall, completion: .contentProcessed { e in
                if let e = e { cont.resume(throwing: e) } else { cont.resume() }
            })
        }

        try await Task.sleep(for: .milliseconds(300))

        // Step 2: Send SearchReply (simple, 0 files)
        var payload = Data()
        payload.appendString("testuser")      // username
        payload.appendUInt32(12345)           // token
        payload.appendUInt32(0)               // 0 files
        payload.appendBool(true)              // free slots
        payload.appendUInt32(100000)          // upload speed
        payload.appendUInt32(0)               // queue length

        var searchReply = Data()
        searchReply.appendUInt32(UInt32(4 + payload.count))
        searchReply.appendUInt32(9)           // code = SearchReply
        searchReply.append(payload)

        print("📤 SearchReply: \(searchReply.prefix(30).map { String(format: "%02x", $0) }.joined(separator: " "))")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peerConn.send(content: searchReply, completion: .contentProcessed { e in
                if let e = e { cont.resume(throwing: e) } else { cont.resume() }
            })
        }

        // Wait for search to be received
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if await state.searchReceived { break }
        }

        #expect(await state.searchReceived)

        peerConn.cancel()
        listener.cancel()
    }

    /// Simpler test: verify PeerConnection can receive raw data on incoming connection
    @Test("Incoming PeerConnection receives raw data")
    func incomingPeerConnectionReceivesRawData() async throws {
        actor State {
            var peerConnection: PeerConnection?
            var dataReceived = false
            func set(_ conn: PeerConnection) { peerConnection = conn }
            func setDataReceived() { dataReceived = true }
        }
        let state = State()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)

        listener.newConnectionHandler = { incomingConn in
            print("🔵 Incoming connection!")

            Task {
                let peerConnection = PeerConnection(connection: incomingConn, isIncoming: true)
                await state.set(peerConnection)

                await peerConnection.setOnMessage { code, data in
                    print("📨 Received message! code=\(code), \(data.count) bytes")
                    Task { await state.setDataReceived() }
                }

                await peerConnection.setOnSearchReply { token, results in
                    print("🔍 Received search reply! token=\(token), \(results.count) results")
                    Task { await state.setDataReceived() }
                }

                do {
                    try await peerConnection.accept()
                    print("🟢 Incoming connection accepted!")
                } catch {
                    print("🔴 Accept failed: \(error)")
                }
            }
        }

        listener.stateUpdateHandler = { listenerState in
            print("🔊 Listener: \(listenerState)")
        }

        listener.start(queue: .global())
        try await Task.sleep(for: .milliseconds(200))

        guard let port = listener.port else {
            throw TestError.noPort
        }

        // Connect from "peer"
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let peerConn = NWConnection(to: endpoint, using: .tcp)

        peerConn.stateUpdateHandler = { connState in
            print("🟣 Peer conn: \(connState)")
        }
        peerConn.start(queue: .global())

        try await Task.sleep(for: .milliseconds(500))

        // Send a simple peer message (just SearchReply, no PierceFirewall)
        var message = Data()
        var payload = Data()
        payload.appendString("testuser")      // username
        payload.appendUInt32(12345)           // token
        payload.appendUInt32(0)               // 0 files
        payload.appendBool(true)              // free slots
        payload.appendUInt32(100000)          // upload speed
        payload.appendUInt32(0)               // queue length

        message.appendUInt32(UInt32(4 + payload.count))  // length
        message.appendUInt32(9)                           // code = SearchReply
        message.append(payload)

        print("📤 Sending \(message.count) bytes")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peerConn.send(content: message, completion: .contentProcessed { error in
                if let error = error {
                    print("🔴 Send error: \(error)")
                    cont.resume(throwing: error)
                } else {
                    print("✅ Message sent")
                    cont.resume()
                }
            })
        }

        // Wait for receipt
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if await state.dataReceived { break }
        }

        #expect(await state.dataReceived)

        peerConn.cancel()
        listener.cancel()
    }

    /// Test that ListenerService properly accepts connections and forwards to callback
    @Test("ListenerService forwards connections")
    func listenerServiceForwardsConnections() async throws {
        actor ConnectionState {
            var receivedConnection: NWConnection?
            func set(_ conn: NWConnection) { receivedConnection = conn }
        }
        let connectionState = ConnectionState()

        let listenerService = ListenerService()

        // Set up callback BEFORE starting
        await listenerService.setOnNewConnection { conn, obfuscated in
            print("✅ ListenerService forwarded connection! obfuscated=\(obfuscated)")
            Task { await connectionState.set(conn) }
        }

        let ports = try await listenerService.start()
        print("🔊 ListenerService started on port \(ports.port)")

        // Connect to the listener
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: ports.port)!)
        let testConn = NWConnection(to: endpoint, using: .tcp)
        testConn.start(queue: .global())

        // Wait for connection
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if await connectionState.receivedConnection != nil { break }
        }

        #expect(await connectionState.receivedConnection != nil, "Should have received the connection")

        testConn.cancel()
        await listenerService.stop()
    }
}

enum TestError: Error {
    case noPort
}
