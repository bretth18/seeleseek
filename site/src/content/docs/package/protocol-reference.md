---
title: Protocol Reference
description: Details of the Soulseek wire protocol — the message format, codes, serialization, and compression.
order: 16
section: package
---

## Wire Format

All Soulseek protocol messages have the same frame:

```
┌──────────────┬──────────────┬──────────────────┐
│ Length (4B)  │ Code (4B)    │ Payload (N bytes)│
│ uint32 LE    │ uint32 LE    │ varies           │
└──────────────┴──────────────┴──────────────────┘
```

- **Length**: the size of the code plus the payload. The length field itself is not included.
- **Code**: the message type identifier.
- **Payload**: binary data. The content is different for each message type.
- All integers are **little-endian**.
- Strings have a length prefix: a `uint32` length, then the UTF-8 bytes.

## Data Types

The protocol uses these primitive types:

| Type | Size | Description |
|------|------|-------------|
| `uint8` | 1 byte | An unsigned byte |
| `uint32` | 4 bytes | An unsigned 32-bit integer, little-endian |
| `uint64` | 8 bytes | An unsigned 64-bit integer, little-endian |
| `bool` | 1 byte | 0 = false, not zero = true |
| `string` | 4 + N bytes | A uint32 length prefix, then the UTF-8 data |

SeeleseekCore has `Data` extensions that read and write these types:

```swift
extension Data {
    func extractUInt32(at offset: Int) -> UInt32
    func extractUInt64(at offset: Int) -> UInt64
    func extractString(at offset: Int) -> (String, Int)  // (value, bytesConsumed)
    func extractBool(at offset: Int) -> Bool

    mutating func appendUInt32(_ value: UInt32)
    mutating func appendUInt64(_ value: UInt64)
    mutating func appendString(_ value: String)
    mutating func appendBool(_ value: Bool)
}
```

## Server Message Codes

Messages between your client and the Soulseek server. Important codes:

| Code | Name | Direction | Function |
|------|------|-----------|----------|
| 1 | Login | C→S / S→C | Log in and receive the login response |
| 2 | SetListenPort | C→S | Send the listen port to the server |
| 3 | GetPeerAddress | C→S / S→C | Request or receive the IP and port of a peer |
| 5 | WatchUser | C→S | Subscribe to the status changes of a user |
| 7 | GetUserStatus | C→S / S→C | Request or receive the online status of a user |
| 13 | SayInChatRoom | C→S / S→C | Send or receive room messages |
| 14 | JoinRoom | C→S / S→C | Join a room and receive the user list |
| 15 | LeaveRoom | C→S / S→C | Go out of a room |
| 18 | ConnectToPeer | C→S / S→C | Ask the server to mediate a peer connection |
| 22 | PrivateMessages | S→C | Receive a private message |
| 26 | FileSearch | C→S | Search the network |
| 28 | SetOnlineStatus | C→S | Set the away or online status |
| 32 | Ping | C→S | A keepalive ping |
| 36 | GetUserStats | C→S / S→C | Request or receive the statistics of a user |
| 64 | RoomList | S→C | The list of available rooms |
| 69 | PrivilegedUsers | S→C | The list of privileged users |
| 71 | HaveNoParent | C→S | Report that the client has no parent node |
| 73 | ParentMinSpeed | S→C | The minimum speed for distributed parents |
| 92 | CheckPrivileges | C→S / S→C | Get the remaining privilege time |
| 93 | EmbeddedMessage | S→C | A distributed search that the server forwards |
| 102 | PossibleParents | S→C | A list of candidate parent nodes |
| 103 | WishlistSearch | C→S | A search that the server repeats |
| 104 | WishlistInterval | S→C | The wishlist interval that the server sets |
| 120 | RoomTickerState | S→C | Room ticker messages |
| 130 | ResetDistributed | S→C | Reset the distributed network state |
| 141 | RoomSearch | C→S | Search in one room |
| 160 | ExcludedSearchPhrases | S→C | Search phrases that the server blocks |
| 1001 | CantConnectToPeer | C→S / S→C | A report of a failed peer connection |

The full enum is `ServerMessageCode` in `MessageCode.swift`.

## Peer Message Codes

Messages between peers. These use `uint32` codes in the message frame:

| Code | Name | Function |
|------|------|----------|
| 0 | PierceFirewall | The NAT traversal handshake (sends a token) |
| 1 | PeerInit | The initial handshake (sends the username, type, and token) |
| 4 | SharesRequest | Request the shared file list of a user |
| 5 | SharesReply | The shared file list (zlib compressed) |
| 8 | SearchRequest | A peer search request |
| 9 | SearchReply | The search results (zlib compressed) |
| 15 | UserInfoRequest | Request the profile of a user |
| 16 | UserInfoReply | The profile response |
| 36 | FolderContentsRequest | Request the contents of a folder |
| 37 | FolderContentsReply | The contents of a folder (zlib compressed) |
| 40 | TransferRequest | Request a file transfer |
| 41 | TransferReply | Accept or deny a transfer |
| 43 | QueueDownload | Put a file in the download queue |
| 44 | PlaceInQueueReply | The queue position report |
| 46 | UploadFailed | A report of a failed upload |
| 50 | UploadDenied | A report of a denied upload, with the reason |
| 51 | PlaceInQueueRequest | Request the queue position |

The full enum is `PeerMessageCode` in `MessageCode.swift`.

## Distributed Message Codes

Messages in the distributed search network. The code is the first byte after the peer init:

| Code | Name | Function |
|------|------|----------|
| 0 | Ping | The distributed keepalive |
| 3 | SearchRequest | A distributed search (the client forwards it to its children) |
| 4 | BranchLevel | Report the branch level |
| 5 | BranchRoot | Report the username of the branch root |
| 7 | ChildDepth | Report the child depth |
| 93 | EmbeddedMessage | A distributed message that the server embeds |

## Message Construction

Use `MessageBuilder` to make messages:

```swift
// Server messages
let login = MessageBuilder.loginMessage(
    username: "myUser", password: "myPass"
)
let search = MessageBuilder.fileSearchMessage(
    token: 12345, query: "boards of canada"
)

// Peer messages
let init = MessageBuilder.peerInitMessage(
    username: "myUser", connectionType: "P", token: 12345
)
let pierce = MessageBuilder.pierceFirewallMessage(token: 12345)
let queue = MessageBuilder.queueDownloadMessage(
    filename: "Music/Artist/track.flac"
)
```

## Message Parsing

Use `MessageParser` to decode incoming data:

```swift
// Parse a message frame
if let (frame, consumed) = MessageParser.parseFrame(from: data) {
    // frame.code is the message type
    // frame.payload is the message body
}

// Parse specific message types
if let login = MessageParser.parseLoginResponse(payload) { ... }
if let results = MessageParser.parseSearchReply(payload) { ... }
if let status = MessageParser.parseGetUserStatus(payload) { ... }
if let room = MessageParser.parseJoinRoom(payload) { ... }
```

### Safety Limits

The parser applies limits. These limits prevent damage from malicious payloads:

```swift
MessageParser.maxItemCount      // 100,000 items per list
MessageParser.maxAttributeCount // 100 attributes per file
MessageParser.maxMessageSize    // 100 MB per message
```

## Compression

Three message types use zlib compression: **SharesReply** (5), **SearchReply** (9), and **FolderContentsReply** (37).

The compressed data is raw DEFLATE (RFC 1951). Apple's `COMPRESSION_ZLIB` reads this format. For zlib-wrapped data, remove the 2-byte header and the 4-byte Adler-32 checksum first.

```swift
// Decompression occurs internally
public enum DecompressionError: Error, LocalizedError {
    case decompressionFailed
    case invalidData
    case outputTooLarge
}
```

## IP Address Encoding

The protocol keeps IP addresses as `uint32` values in network byte order (big-endian). The client reads the values as little-endian from the wire. SeeleseekCore does the byte-order conversion internally. You always receive IP strings in the usual format.

## seeleseek Extensions

seeleseek defines custom peer message codes. These codes supply features that the standard protocol does not have:

```swift
public enum seeleseekPeerCode: UInt32, CaseIterable {
    case handshake = 10000       // Custom client identification
    case artworkRequest = 10001  // Request the album art for a file
    case artworkReply = 10002    // The album art response
}
```

Only other seeleseek clients know these codes.
