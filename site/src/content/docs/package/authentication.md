---
title: Authentication & Connection Lifecycle
description: Connecting to the Soulseek server, authentication, and managing the connection lifecycle.
order: 12
section: package
---

## Connecting to the Server

The main entry point is `NetworkClient`. Create an instance and call `connect`:

```swift
let client = NetworkClient()

// Set up callbacks before connecting
client.onConnectionStatusChanged = { status in
    print("Connection status: \(status)")
}

// Connect to the Soulseek server
await client.connect(
    server: "server.slsknet.org",
    port: 2242,
    username: "myUsername",
    password: "myPassword",
    preferredListenPort: 2234
)
```

## Connection Status

Monitor the connection through the `onConnectionStatusChanged` callback or the observable properties:

```swift
// Observable properties (for SwiftUI)
client.isConnecting  // true while connecting
client.isConnected   // true when logged in
client.connectionError // error message if failed

// Callback-based
client.onConnectionStatusChanged = { status in
    switch status {
    case .disconnected:
        print("Not connected")
    case .connecting:
        print("Connecting...")
    case .connected:
        print("Logged in")
    case .reconnecting:
        print("Reconnecting after drop")
    case .error:
        print("Connection error")
    }
}
```

The `ConnectionStatus` enum cases:

| Case | Meaning |
|------|---------|
| `.disconnected` | Not connected to server |
| `.connecting` | TCP connection or login in progress |
| `.connected` | Successfully authenticated |
| `.reconnecting` | Dropped, attempting auto-reconnect |
| `.error` | Connection or login failed |

## Server Connection Details

Under the hood, `NetworkClient` creates a `ServerConnection` actor:

```swift
// ServerConnection is an actor for thread safety
public actor ServerConnection {
    public static let defaultHost = "server.slsknet.org"
    public static let defaultPort: UInt16 = 2242

    // Async stream of complete message frames
    public nonisolated var messages: AsyncStream<Data>

    public func connect() async throws
    public func disconnect()
    public func send(_ data: Data) async throws
}
```

The server connection handles:
- TCP connection with keepalive (60s interval, 3 probes)
- Message framing (4-byte length prefix, little-endian)
- A 50 MB receive buffer security limit
- Automatic ping every 300 seconds

## Login Flow

When you call `connect`, the following happens:

1. `ServerConnection.connect()` establishes the TCP connection
2. A login message is sent with username, password hash, and client version info
3. The server responds with success (including your external IP) or failure
4. On success, SeeleseekCore sends: listen port, online status, shared file counts
5. `ListenerService` starts listening for incoming peer connections
6. `NATService` attempts UPnP port mapping in the background
7. Callbacks fire with `ConnectionStatus.connected`

## Disconnecting

```swift
// User-initiated disconnect (disables auto-reconnect)
client.disconnect()

// For unexpected disconnects (enables auto-reconnect)
client.handleUnexpectedDisconnect(reason: "Connection lost")
```

## Auto-Reconnect

When the connection drops unexpectedly, `NetworkClient` automatically attempts to reconnect with exponential backoff. This is triggered by `handleUnexpectedDisconnect` and disabled by explicit `disconnect()` calls.

The one exception is a "Relogged" disconnect — when another client logs in with the same credentials. Auto-reconnect is disabled in this case to prevent a login loop.

```swift
// Called internally when server sends Relogged message
client.handleReloggedDisconnect()
```

## Listening for Incoming Connections

SeeleseekCore automatically starts a `ListenerService` to accept incoming peer connections:

```swift
// ListenerService tries ports in order: preferred, then 2234-2240
let (port, obfuscatedPort) = try await listener.start(
    preferredPort: 2234
)
```

Incoming connections are routed to `PeerConnectionPool` for handshake processing.

## NAT Traversal

The `NATService` actor handles UPnP port mapping:

```swift
let nat = NATService()

// Map a port via UPnP
let externalPort = try await nat.mapPort(2234)

// Discover external IP
let externalIP = await nat.discoverExternalIP()
```

If UPnP fails, connections still work via the server-mediated "pierce firewall" mechanism — see [Peer Connections](/docs/package/peer-connections).
