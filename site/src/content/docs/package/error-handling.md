---
title: Errors and Recovery
description: Error types, connection failures, and recovery procedures in SeeleseekCore.
order: 17
section: package
---

## Error Types

SeeleseekCore defines error types for each subsystem.

### ServerConnection Errors

```swift
public enum ConnectionError: Error, LocalizedError {
    case notConnected         // A send occurred without a connection
    case connectionFailed(String)  // The TCP connection failed
    case loginFailed(String)       // The server rejected the credentials
    case timeout                   // The connection timed out
    case invalidResponse           // The server response was not valid
}
```

### PeerConnectionPool Errors

```swift
public enum PeerConnectionError: Error, LocalizedError {
    case invalidAddress    // The peer IP is multicast, loopback, or reserved
    case timeout           // The connection timed out
    case connectionFailed(String)  // The TCP connection failed, with the reason
}
```

### Download Errors

```swift
public enum DownloadError: Error, LocalizedError {
    case invalidPort            // The port of the peer is not valid
    case connectionCancelled    // The connection was cancelled
    case connectionClosed       // The connection closed unexpectedly
    case cannotCreateFile       // The client cannot make the local file
    case timeout                // The transfer timed out
    case incompleteTransfer(expected: UInt64, actual: UInt64)
    case verificationFailed     // The file verification failed
}
```

### Upload Errors

```swift
public enum UploadError: Error, LocalizedError {
    case fileNotFound      // The file is not on the disk
    case fileNotShared     // The file is not in the shared folders
    case cannotReadFile    // The client cannot open the file
    case connectionFailed  // The peer connection failed
    case peerRejected      // The peer rejected the transfer
    case timeout           // The transfer timed out
}
```

### Decompression Errors

```swift
public enum DecompressionError: Error, LocalizedError {
    case decompressionFailed  // The zlib decompression failed
    case invalidData          // The data is not valid zlib
    case outputTooLarge       // The decompressed size is more than the limit
}
```

### Listener Errors

```swift
public enum ListenerError: Error, LocalizedError {
    case noAvailablePort    // All ports in the range are in use
    case bindFailed(String) // The bind to the port failed
}
```

### NAT Errors

```swift
public enum NATError: Error {
    case noLocalIP         // The local IP is not known
    case noGatewayFound    // No UPnP gateway was found
    case mappingFailed     // The port mapping failed
    case ipDiscoveryFailed // The external IP is not known
}
```

## Login Failures

The login result is an enum, not a thrown error:

```swift
public enum LoginResult: Sendable {
    case success(greeting: String, ip: String, hash: String?)
    case failure(reason: String)
}
```

Usual failure reasons:

- `"INVALIDPASS"` — The password is not correct.
- `"INVALIDUSERNAME"` — The username contains characters that are not permitted.
- A connection timeout — The server is not available.

## Connection Recovery

### Automatic Reconnection

`NetworkClient` connects again automatically after an unexpected disconnect:

```swift
// Called internally when the connection stops
client.handleUnexpectedDisconnect(reason: "Connection reset")
// → Plans a new connection with exponential backoff

// An explicit disconnect (this stops automatic reconnection)
client.disconnect()
```

The interval between tries increases each time (exponential backoff). This prevents too many login tries in a short time.

### Relogged Disconnects

The server sends a `Relogged` message when a different client logs in with the same credentials. Automatic reconnection stops:

```swift
client.handleReloggedDisconnect()
// → Disconnects and does not try again
```

### Download Retry

You can start a failed download again:

```swift
downloadManager.retryFailedDownload(transferId: transfer.id)
```

The retry puts the download in the queue again, with the same filename and username. The client opens the peer connection again.

## Peer Connection Failures

### CantConnectToPeer

The server reports when it cannot connect you to a peer:

```swift
client.onCantConnectToPeer = { token in
    // The server-mediated connection to the peer failed
    // The download manager receives this event internally
}
```

### Upload Denied and Upload Failed

A peer can deny an upload, or report a failed upload:

```swift
client.onUploadDenied = { filename, reason in
    // Possible reasons: "Queued", "Too many files", "Blocked"
}

client.onUploadFailed = { filename in
    // The upload failed. No reason was given
}
```

## Activity Logs

SeeleseekCore has a log protocol. Use it to monitor all operations:

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

The package writes to `ActivityLogger.shared` when it is set. The logs cover connection events, peer activity, searches, the transfer lifecycle, and errors.
