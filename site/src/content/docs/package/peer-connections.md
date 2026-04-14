---
title: Peer Connections
description: How SeeleseekCore establishes, manages, and routes peer-to-peer connections.
order: 15
section: package
---

## Connection Types

Peer connections come in several flavors:

```swift
public enum ConnectionType: String, Sendable {
    case peer = "P"          // General peer messaging
    case file = "F"          // File transfer
    case distributed = "D"   // Distributed search network
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

    // Event stream for messages and state changes
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

The pool manages all peer connections with rate limiting and lifecycle management:

```swift
let pool = client.peerConnectionPool

// Connect to a peer
let connection = try await pool.connect(
    to: "alice",
    ip: "192.168.1.100",
    port: 2234,
    token: 12345
)

// Get an existing connection for a user
let existing = await pool.getConnectionForUser("alice")

// Accept an incoming connection
await pool.handleIncomingConnection(nwConnection)

// Disconnect from a user
await pool.disconnect(username: "alice")

// Disconnect all peers
await pool.disconnectAll()
```

### Connection Limits

The pool enforces several safety limits:

| Limit | Default | Purpose |
|-------|---------|---------|
| Max connections | 50 | Total concurrent peer connections |
| Max per IP | 30 | Connections from a single IP |
| Rate limit | 10/60s | Connection attempts per IP per minute |
| Idle timeout | 60s | Auto-close idle connections |
| Ghost timeout | 10s | Close connections with no initial activity |

### Statistics

The pool tracks real-time statistics, all `@Observable`:

```swift
pool.totalBytesReceived     // Lifetime bytes received
pool.totalBytesSent         // Lifetime bytes sent
pool.totalConnections       // Total connections created
pool.activeConnections      // Currently open connections
pool.currentDownloadSpeed   // bytes/sec
pool.currentUploadSpeed     // bytes/sec
pool.speedHistory           // Last 60 SpeedSample entries (1/sec)
pool.peerLocations          // Geographic locations of peers
pool.connectionsByType      // Connections grouped by type
pool.topPeersByTraffic      // Top 10 peers by bytes transferred
pool.averageConnectionDuration
```

## Connection Establishment

### Direct Connection

The simplest case — connect directly to a peer's IP and port:

```swift
let conn = try await pool.connect(
    to: "alice", ip: "1.2.3.4", port: 2234, token: token
)
// Pool automatically sends PeerInit handshake
```

### Server-Mediated (NAT Traversal)

When direct connection fails (both peers behind NAT):

1. Your client asks the server to tell the peer to connect to you:
```swift
await client.sendConnectToPeer(token: token, username: "alice")
```

2. The server sends a `ConnectToPeer` message to the peer with your address
3. The peer either connects directly to you, or...
4. The peer sends a `PierceFirewall` connection — connecting to your listening port with a token instead of a username

This "firewall piercing" mechanism means both peers race to establish a connection, and the first one to succeed wins.

### Getting Peer Addresses

To find a peer's IP and port:

```swift
let (ip, port) = try await client.getPeerAddress(for: "alice")
```

This is an async call that requests the address from the server and waits (with a 10-second timeout).

## Event Handling

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

These are consumed by `PeerConnectionPool` and re-emitted as `PeerPoolEvent`s, which `NetworkClient` routes to the appropriate callbacks.

## Browsing Users

To browse another user's shared files:

```swift
let files = try await client.browseUser("alice")

// files is [SharedFile] — a flat list that can be built into a tree
let tree = SharedFile.buildTree(from: files)
```

`browseUser` internally handles the full connection lifecycle:
1. Gets the peer's address
2. Races a direct TCP connection (10s timeout) against a PierceFirewall connection
3. Sends a shares request
4. Waits for and decompresses the shares response
5. Returns the parsed file list

## IP Validation

The pool validates peer IPs before connecting:

```swift
PeerConnectionPool.isValidPeerIP("192.168.1.100")  // true
PeerConnectionPool.isValidPeerIP("224.0.0.1")      // false (multicast)
PeerConnectionPool.isValidPeerIP("127.0.0.1")      // false (loopback)
PeerConnectionPool.isValidPeerIP("0.0.0.0")        // false (reserved)
```
