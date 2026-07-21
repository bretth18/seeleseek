---
title: Authentication and Connection Lifecycle
description: Connect to the Soulseek server, log in, and control the connection lifecycle.
order: 12
section: package
---

## Connect to the Server

The main entry point is `NetworkClient`. Make an instance and call `connect`:

```swift
let client = NetworkClient()

// Set the callbacks before you connect
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

Monitor the connection with the `onConnectionStatusChanged` callback, or with the observable properties:

```swift
// Observable properties (for SwiftUI)
client.isConnecting  // true during the connection sequence
client.isConnected   // true after a successful login
client.connectionError // the error message after a failure

// Callback
client.onConnectionStatusChanged = { status in
    switch status {
    case .disconnected:
        print("Not connected")
    case .connecting:
        print("Connection in progress")
    case .connected:
        print("Logged in")
    case .reconnecting:
        print("New connection in progress")
    case .error:
        print("Connection error")
    }
}
```

The `ConnectionStatus` enum has these cases:

| Case | Meaning |
|------|---------|
| `.disconnected` | There is no connection to the server |
| `.connecting` | The TCP connection or the login is in progress |
| `.connected` | The login was successful |
| `.reconnecting` | The connection stopped. The client tries to connect again |
| `.error` | The connection or the login failed |

## Server Connection Details

`NetworkClient` makes a `ServerConnection` actor:

```swift
// ServerConnection is an actor for thread safety
public actor ServerConnection {
    public static let defaultHost = "server.slsknet.org"
    public static let defaultPort: UInt16 = 2242

    // An async stream of complete message frames
    public nonisolated var messages: AsyncStream<Data>

    public func connect() async throws
    public func disconnect()
    public func send(_ data: Data) async throws
}
```

The server connection does these tasks:

- The TCP connection, with keepalive (60 s interval, 3 probes)
- The message framing (4-byte length prefix, little-endian)
- A 50 MB receive buffer limit, for security
- An automatic ping every 300 seconds

## Login Sequence

When you call `connect`, this sequence occurs:

1. `ServerConnection.connect()` opens the TCP connection.
2. The client sends a login message with the username, the password hash, and the client version.
3. The server responds with success (the response includes your external IP) or with failure.
4. On success, SeeleseekCore sends the listen port, the online status, and the shared file counts.
5. `ListenerService` starts to listen for incoming peer connections.
6. `NATService` tries the UPnP port mapping in the background.
7. The callbacks fire with `ConnectionStatus.connected`.

## Disconnect

```swift
// A disconnect by the user (this stops automatic reconnection)
client.disconnect()

// For unexpected disconnects (this permits automatic reconnection)
client.handleUnexpectedDisconnect(reason: "Connection lost")
```

## Automatic Reconnection

When the connection stops unexpectedly, `NetworkClient` connects again automatically. The interval between tries increases each time (exponential backoff). `handleUnexpectedDisconnect` starts this behavior. An explicit `disconnect()` call stops it.

There is one exception: the "Relogged" disconnect. This occurs when a different client logs in with the same credentials. Automatic reconnection stops in this case. This prevents a login loop.

```swift
// Called internally when the server sends a Relogged message
client.handleReloggedDisconnect()
```

## Listen for Incoming Connections

SeeleseekCore starts a `ListenerService` automatically. This service accepts incoming peer connections:

```swift
// ListenerService tries the ports in sequence: the preferred port, then 2234-2240
let (port, obfuscatedPort) = try await listener.start(
    preferredPort: 2234
)
```

Incoming connections go to `PeerConnectionPool` for the handshake.

## NAT Traversal

The `NATService` actor does the UPnP port mapping:

```swift
let nat = NATService()

// Map a port with UPnP
let externalPort = try await nat.mapPort(2234)

// Find the external IP
let externalIP = await nat.discoverExternalIP()
```

If UPnP fails, connections operate through the server-mediated "pierce firewall" procedure. See [Peer Connections](/docs/package/peer-connections).
