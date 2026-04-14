---
title: Error Handling
description: Error types, connection failures, and recovery strategies in SeeleseekCore.
order: 17
section: package
---

## Error Types

SeeleseekCore defines domain-specific error types for each subsystem.

### ServerConnection Errors

```swift
public enum ConnectionError: Error, LocalizedError {
    case notConnected         // Tried to send while disconnected
    case connectionFailed(String)  // TCP connection failed
    case loginFailed(String)       // Server rejected credentials
    case timeout                   // Connection timed out
    case invalidResponse           // Malformed server response
}
```

### PeerConnectionPool Errors

```swift
public enum PeerConnectionError: Error, LocalizedError {
    case invalidAddress    // Peer IP is multicast, loopback, or reserved
    case timeout           // Connection timed out
    case connectionFailed(String)  // TCP connection failed with reason
}
```

### Download Errors

```swift
public enum DownloadError: Error, LocalizedError {
    case invalidPort            // Peer's port is invalid
    case connectionCancelled    // Connection was cancelled
    case connectionClosed       // Connection closed unexpectedly
    case cannotCreateFile       // Can't create the local file
    case timeout                // Transfer timed out
    case incompleteTransfer(expected: UInt64, actual: UInt64)
    case verificationFailed     // File verification failed
}
```

### Upload Errors

```swift
public enum UploadError: Error, LocalizedError {
    case fileNotFound      // File doesn't exist on disk
    case fileNotShared     // File isn't in shared folders
    case cannotReadFile    // Can't open the file for reading
    case connectionFailed  // Peer connection failed
    case peerRejected      // Peer rejected the transfer
    case timeout           // Transfer timed out
}
```

### Decompression Errors

```swift
public enum DecompressionError: Error, LocalizedError {
    case decompressionFailed  // Zlib decompression failed
    case invalidData          // Data isn't valid zlib
    case outputTooLarge       // Decompressed size exceeds limit
}
```

### Listener Errors

```swift
public enum ListenerError: Error, LocalizedError {
    case noAvailablePort    // All ports in range are in use
    case bindFailed(String) // Can't bind to port
}
```

### NAT Errors

```swift
public enum NATError: Error {
    case noLocalIP         // Can't determine local IP
    case noGatewayFound    // No UPnP gateway found
    case mappingFailed     // Port mapping failed
    case ipDiscoveryFailed // Can't discover external IP
}
```

## Login Failures

Login results are represented as an enum, not a thrown error:

```swift
public enum LoginResult: Sendable {
    case success(greeting: String, ip: String, hash: String?)
    case failure(reason: String)
}
```

Common failure reasons:
- `"INVALIDPASS"` — wrong password
- `"INVALIDUSERNAME"` — username contains invalid characters
- Connection timeout — server unreachable

## Connection Recovery

### Auto-Reconnect

`NetworkClient` handles reconnection automatically for unexpected disconnects:

```swift
// Triggered internally on connection drop
client.handleUnexpectedDisconnect(reason: "Connection reset")
// → Schedules reconnect with exponential backoff

// Explicitly disconnect (disables auto-reconnect)
client.disconnect()
```

The auto-reconnect uses exponential backoff — retrying after increasing intervals to avoid hammering the server.

### Relogged Handling

When the server sends a `Relogged` message (another client logged in), auto-reconnect is disabled:

```swift
client.handleReloggedDisconnect()
// → Disconnects without scheduling reconnect
```

### Download Retry

Failed downloads can be retried:

```swift
downloadManager.retryFailedDownload(transferId: transfer.id)
```

Retry re-queues the download with the same filename and username, re-establishing the peer connection.

## Peer Connection Failures

### CantConnectToPeer

When the server reports it can't connect us to a peer:

```swift
client.onCantConnectToPeer = { token in
    // Connection to peer failed via server mediation
    // The download manager handles this internally
}
```

### Upload Denied / Failed

Peers can deny or report failed uploads:

```swift
client.onUploadDenied = { filename, reason in
    // Reasons: "Queued", "Too many files", "Blocked", etc.
}

client.onUploadFailed = { filename in
    // Upload failed without a specific reason
}
```

## Activity Logging

SeeleseekCore provides a logging protocol for monitoring all operations:

```swift
@MainActor
public protocol ActivityLogging: AnyObject, Sendable {
    func logPeerConnected(username: String, ip: String)
    func logPeerDisconnected(username: String)
    func logSearchStarted(query: String)
    func logSearchResults(query: String, count: Int, user: String)
    func logDownloadStarted(filename: String, from user: String)
    func logDownloadCompleted(filename: String)
    func logUploadStarted(filename: String, to user: String)
    func logUploadCompleted(filename: String)
    func logChatMessage(from user: String, room: String?)
    func logError(_ message: String, detail: String?)
    func logInfo(_ message: String, detail: String?)
    func logConnectionSuccess(username: String, server: String)
    func logConnectionFailed(reason: String)
    func logDisconnected(reason: String?)
    func logRelogged()
    func logRoomJoined(room: String, userCount: Int)
    func logRoomLeft(room: String)
    func logNATMapping(port: UInt16, success: Bool)
    func logDistributedSearch(query: String, matchCount: Int)
}
```

Register your logger at app startup:

```swift
ActivityLogger.shared = MyLogger()
```

The package logs through `ActivityLogger.shared` when set, covering connection events, peer activity, search operations, transfer lifecycle, and errors.
