---
title: Peer Connections
description: How SeeleseekCore opens, manages, and routes peer-to-peer connections.
order: 15
section: package
---

## Connection Types

There are three types of peer connections:

```swift
public enum ConnectionType: String, Sendable {
    case peer = "P"          // General peer messages
    case file = "F"          // File transfers
    case distributed = "D"   // The distributed search network
}
```

## PeerConnection Actor

Each peer connection is an isolated `actor`:

```swift
public actor PeerConnection {
    public var state: State        // .idle, .connecting, .connected, .disconnected
    public var username: String?
    public var ip: String
    public var port: Int
    public var connectionType: ConnectionType

    // The event stream for messages and state changes
    public nonisolated var events: AsyncStream<PeerConnectionEvent>

    // Send raw data
    public func send(_ data: Data) async throws

    // Send protocol messages
    public func sendSharesRequest() async throws
    public func sendUserInfoRequest() async throws
    public func sendSearchReply(...) async throws
    public func sendTransferRequest(...) async throws
    public func sendQueueDownload(filename: String) async throws
    // ... and more
}
```

## PeerConnectionPool

The pool manages all peer connections. It applies rate limits and controls the connection lifecycle:

```swift
let pool = client.peerConnectionPool

// Connect to a peer
let connection = try await pool.connect(
    to: "alice",
    ip: "192.168.1.100",
    port: 2234,
    token: 12345
)

// Get an open connection for a user
let existing = await pool.getConnectionForUser("alice")

// Accept an incoming connection
await pool.handleIncomingConnection(nwConnection)

// Disconnect from a user
await pool.disconnect(username: "alice")

// Disconnect all peers
await pool.disconnectAll()
```

### Connection Limits

The pool applies these safety limits:

| Limit | Default | Function |
|-------|---------|----------|
| Max connections | 50 | The maximum number of open peer connections |
| Max per IP | 30 | The maximum number of connections from one IP |
| Rate limit | 10/60s | The maximum connection tries per IP each minute |
| Idle timeout | 60s | The pool closes idle connections after this time |
| Ghost timeout | 10s | The pool closes connections that show no initial activity |

### Statistics

The pool keeps statistics in real time. All properties are `@Observable`:

```swift
pool.totalBytesReceived     // All bytes received
pool.totalBytesSent         // All bytes sent
pool.totalConnections       // The number of connections made
pool.activeConnections      // The number of open connections
pool.currentDownloadSpeed   // bytes/sec
pool.currentUploadSpeed     // bytes/sec
pool.speedHistory           // The last 60 SpeedSample entries (1 each second)
pool.peerLocations          // The geographic locations of the peers
pool.connectionsByType      // The connections, in groups by type
pool.topPeersByTraffic      // The top 10 peers by transferred bytes
pool.averageConnectionDuration
```

## Open a Connection

### Direct Connection

The simplest case. Connect directly to the IP and port of a peer:

```swift
let conn = try await pool.connect(
    to: "alice", ip: "1.2.3.4", port: 2234, token: token
)
// The pool sends the PeerInit handshake automatically
```

### Server-Mediated Connection (NAT Traversal)

A direct connection is not possible when the two peers are behind NAT. Then this sequence occurs:

1. Your client asks the server to tell the peer to connect to you:

```swift
await client.sendConnectToPeer(token: token, username: "alice")
```

2. The server sends a `ConnectToPeer` message with your address to the peer.
3. The peer connects directly to you, or:
4. The peer sends a `PierceFirewall` connection. This connection goes to your listen port with a token, not a username.

In this "firewall piercing" procedure, the two peers try to connect at the same time. The first connection that opens wins.

### Get the Address of a Peer

To find the IP and port of a peer:

```swift
let (ip, port) = try await client.getPeerAddress(for: "alice")
```

This async call requests the address from the server. It waits a maximum of 10 seconds.

## Events

Peer events flow through `AsyncStream<PeerConnectionEvent>`:

```swift
public enum PeerConnectionEvent: Sendable {
    case stateChanged(PeerConnection.State)
    case message(code: UInt32, payload: Data)
    case sharesReceived([SharedFile])
    case searchReply(token: UInt32, results: [SearchResult])
    case transferRequest(TransferRequest)
    case queueUpload(username: String, filename: String)
    case transferResponse(token: UInt32, allowed: Bool, filesize: UInt64?)
    case uploadDenied(filename: String, reason: String)
    case uploadFailed(filename: String)
    case placeInQueueRequest(username: String, filename: String)
    case placeInQueueReply(filename: String, position: UInt32)
    case sharesRequest
    case userInfoRequest
    case folderContentsRequest(token: UInt32, folder: String)
    case folderContentsResponse(token: UInt32, folder: String, files: [SharedFile])
    case pierceFirewall(token: UInt32)
    // ... and more
}
```

`PeerConnectionPool` consumes these events. It sends them out again as `PeerPoolEvent` values. `NetworkClient` routes them to the applicable callbacks.

## Browse a User

To browse the shared files of a user:

```swift
let files = try await client.browseUser("alice")

// files is a flat [SharedFile] list. buildTree makes a tree from it
let tree = SharedFile.buildTree(from: files)
```

`browseUser` does the full connection lifecycle internally:

1. Gets the address of the peer.
2. Tries a direct TCP connection (10 s timeout) and a PierceFirewall connection at the same time.
3. Sends a shares request.
4. Waits for the shares response and decompresses it.
5. Returns the parsed file list.

## IP Validation

The pool validates peer IPs before it connects:

```swift
PeerConnectionPool.isValidPeerIP("192.168.1.100")  // true
PeerConnectionPool.isValidPeerIP("224.0.0.1")      // false (multicast)
PeerConnectionPool.isValidPeerIP("127.0.0.1")      // false (loopback)
PeerConnectionPool.isValidPeerIP("0.0.0.0")        // false (reserved)
```
