---
title: Protocol Reference
description: Soulseek wire protocol details — message format, codes, serialization, and compression.
order: 16
section: package
---

## Wire Format

All Soulseek protocol messages follow the same framing:

```
┌──────────────┬──────────────┬──────────────────┐
│ Length (4B)  │ Code (4B)    │ Payload (N bytes)│
│ uint32 LE    │ uint32 LE    │ varies           │
└──────────────┴──────────────┴──────────────────┘
```

- **Length**: total size of code + payload (does not include itself)
- **Code**: message type identifier
- **Payload**: message-specific binary data
- All integers are **little-endian**
- Strings are length-prefixed: `uint32 length` followed by UTF-8 bytes

## Data Types

The protocol uses these primitive types:

| Type | Size | Description |
|------|------|-------------|
| `uint8` | 1 byte | Unsigned byte |
| `uint32` | 4 bytes | Unsigned 32-bit integer, little-endian |
| `uint64` | 8 bytes | Unsigned 64-bit integer, little-endian |
| `bool` | 1 byte | 0 = false, non-zero = true |
| `string` | 4 + N bytes | uint32 length prefix + UTF-8 data |

SeeleseekCore provides `Data` extensions for reading and writing these:

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

Messages between your client and the Soulseek server. Key codes:

| Code | Name | Direction | Purpose |
|------|------|-----------|---------|
| 1 | Login | C→S / S→C | Authenticate and receive login response |
| 2 | SetListenPort | C→S | Tell server our listening port |
| 3 | GetPeerAddress | C→S / S→C | Request/receive a peer's IP and port |
| 5 | WatchUser | C→S | Subscribe to user status updates |
| 7 | GetUserStatus | C→S / S→C | Request/receive user online status |
| 13 | SayInChatRoom | C→S / S→C | Send/receive room messages |
| 14 | JoinRoom | C→S / S→C | Join a room, receive user list |
| 15 | LeaveRoom | C→S / S→C | Leave a room |
| 18 | ConnectToPeer | C→S / S→C | Request server to mediate peer connection |
| 22 | PrivateMessages | S→C | Receive private message |
| 26 | FileSearch | C→S | Search the network |
| 28 | SetOnlineStatus | C→S | Set away/online status |
| 32 | Ping | C→S | Keepalive ping |
| 36 | GetUserStats | C→S / S→C | Request/receive user stats |
| 64 | RoomList | S→C | List of available rooms |
| 69 | PrivilegedUsers | S→C | List of privileged users |
| 71 | HaveNoParent | C→S | Distributed network: have no parent node |
| 73 | ParentMinSpeed | S→C | Minimum speed for distributed parents |
| 92 | CheckPrivileges | C→S / S→C | Check privilege time remaining |
| 93 | EmbeddedMessage | S→C | Distributed search forwarded by server |
| 102 | PossibleParents | S→C | List of candidate parent nodes |
| 103 | WishlistSearch | C→S | Recurring search |
| 104 | WishlistInterval | S→C | Server-set wishlist interval |
| 120 | RoomTickerState | S→C | Room ticker messages |
| 130 | ResetDistributed | S→C | Reset distributed network state |
| 141 | RoomSearch | C→S | Search within a room |
| 160 | ExcludedSearchPhrases | S→C | Banned search terms |
| 1001 | CantConnectToPeer | C→S / S→C | Peer connection failure report |

Full enum: `ServerMessageCode` in `MessageCode.swift`.

## Peer Message Codes

Messages between peers. These use `uint32` codes in the message frame:

| Code | Name | Purpose |
|------|------|---------|
| 0 | PierceFirewall | NAT traversal handshake (sends token) |
| 1 | PeerInit | Initial handshake (sends username, type, token) |
| 4 | SharesRequest | Request user's shared file list |
| 5 | SharesReply | Respond with shared files (zlib compressed) |
| 8 | SearchRequest | Peer search request |
| 9 | SearchReply | Search results (zlib compressed) |
| 15 | UserInfoRequest | Request user profile info |
| 16 | UserInfoReply | Respond with profile |
| 36 | FolderContentsRequest | Request folder listing |
| 37 | FolderContentsReply | Folder listing (zlib compressed) |
| 40 | TransferRequest | Request to transfer a file |
| 41 | TransferReply | Accept/deny transfer |
| 43 | QueueDownload | Queue a file for download |
| 44 | PlaceInQueueReply | Report queue position |
| 46 | UploadFailed | Upload failed notification |
| 50 | UploadDenied | Upload denied with reason |
| 51 | PlaceInQueueRequest | Ask for queue position |

Full enum: `PeerMessageCode` in `MessageCode.swift`.

## Distributed Message Codes

Messages in the distributed search network (code in first byte after peer init):

| Code | Name | Purpose |
|------|------|---------|
| 0 | Ping | Distributed keepalive |
| 3 | SearchRequest | Distributed search (forwarded to children) |
| 4 | BranchLevel | Report branch level |
| 5 | BranchRoot | Report branch root username |
| 7 | ChildDepth | Report child depth |
| 93 | EmbeddedMessage | Server-embedded distributed message |

## Building Messages

Use `MessageBuilder` to construct messages:

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

## Parsing Messages

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

The parser enforces limits to prevent malicious payloads:

```swift
MessageParser.maxItemCount      // 100,000 items per list
MessageParser.maxAttributeCount // 100 attributes per file
MessageParser.maxMessageSize    // 100 MB per message
```

## Compression

Three message types use zlib compression: **SharesReply** (5), **SearchReply** (9), and **FolderContentsReply** (37).

The compressed data uses raw DEFLATE (RFC 1951). Apple's `COMPRESSION_ZLIB` handles this, but zlib-wrapped data needs the 2-byte header and 4-byte Adler32 checksum stripped first.

```swift
// Decompression is handled internally
public enum DecompressionError: Error, LocalizedError {
    case decompressionFailed
    case invalidData
    case outputTooLarge
}
```

## IP Address Encoding

IP addresses in the protocol are stored as `uint32` in network byte order (big-endian), but read as little-endian from the wire. SeeleseekCore handles the byte-order conversion internally — you always receive human-readable IP strings.

## seeleseek Extensions

seeleseek defines custom peer message codes for features not in the standard protocol:

```swift
public enum seeleseekPeerCode: UInt32, CaseIterable {
    case handshake = 10000       // Custom client identification
    case artworkRequest = 10001  // Request album art for a file
    case artworkReply = 10002    // Album art response
}
```

These are only recognized by other seeleseek clients.
