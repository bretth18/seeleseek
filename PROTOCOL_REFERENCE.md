# SoulSeek Protocol Reference

Quick reference for implementing the SoulSeek protocol. Based on nicotine-plus documentation.

## Download Flow (Critical)

### Step-by-step:
1. **Downloader** connects to peer (direct or via ConnectToPeer)
2. **Downloader** sends `PeerInit`: `username, "P", token=0` (CRITICAL - identifies who we are!)
3. **Downloader** sends `QueueUpload` (code 43): `filename (string)`
4. **Uploader** may respond with:
   - `TransferRequest` (code 40) - ready to upload
   - `PlaceInQueueResponse` (code 44) - queued
   - `UploadDenied` (code 50) - rejected
5. If `TransferRequest` received: `direction=1, token, filename, filesize`
6. **Downloader** sends `TransferResponse` (code 41): `token, allowed=true`
7. **Uploader** opens F connection to downloader's listen port
8. **Uploader** sends `PeerInit`: `username, "F", token=0` (token is ALWAYS 0 for F connections)
9. **Downloader** sends (raw, no length prefix):
   - `uint32`: transfer token (from TransferRequest)
   - `uint64`: file offset (usually 0)
10. **Uploader** sends raw file data

### Connection Types:
- **Direct**: We connect to peer, send PeerInit
- **Indirect (ConnectToPeer)**: Peer connects to us after we sent CantConnectToPeer, sends PierceFirewall with token

### Key Points:
- ALWAYS send PeerInit when making outgoing connection (identifies who we are)
- F connection PeerInit token is ALWAYS 0
- Match F connections by USERNAME, not token
- Downloader must send token+offset BEFORE receiving file data
- Handle UploadDenied (50) and UploadFailed (46) - download may be rejected

## Message Codes

### Server Messages (uint32 codes)
| Code | Name | Direction |
|------|------|-----------|
| 1 | Login | Bidirectional |
| 2 | SetWaitPort | C→S |
| 3 | GetPeerAddress | Bidirectional |
| 5 | WatchUser | Bidirectional |
| 6 | UnwatchUser | C→S |
| 7 | GetUserStatus | Bidirectional |
| 13 | SayInChatRoom | Bidirectional |
| 14 | JoinRoom | Bidirectional |
| 15 | LeaveRoom | Bidirectional |
| 16 | UserJoinedRoom | S→C |
| 17 | UserLeftRoom | S→C |
| 18 | ConnectToPeer | Bidirectional |
| 22 | MessageUser | Bidirectional |
| 23 | MessageAcked | C→S |
| 26 | FileSearch | Bidirectional |
| 28 | SetStatus | C→S |
| 32 | ServerPing | C→S |
| 35 | SharedFoldersFiles | C→S |
| 36 | GetUserStats | Bidirectional |
| 64 | RoomList | Bidirectional |
| 71 | HaveNoParent | C→S |
| 83 | ParentMinSpeed | S→C |
| 84 | ParentSpeedRatio | S→C |
| 93 | EmbeddedMessage | S→C |
| 100 | AcceptChildren | C→S |
| 102 | PossibleParents | S→C |
| 126 | BranchLevel | C→S |
| 127 | BranchRoot | C→S |
| **1001** | CantConnectToPeer | Bidirectional |
| 1003 | CantCreateRoom | S→C |

### Peer Init Messages (uint8 codes, 1-byte)
| Code | Name | Fields |
|------|------|--------|
| 0 | PierceFireWall | token (uint32) |
| 1 | PeerInit | username (string), type (string), token (uint32) |

### Peer Messages (uint32 codes, sent on P connections)
| Code | Name | Fields |
|------|------|--------|
| 4 | GetShareFileList | (empty) |
| 5 | SharedFileListResponse | (zlib compressed) |
| 9 | FileSearchResponse | (zlib compressed) |
| 15 | UserInfoRequest | (empty) |
| 16 | UserInfoResponse | description, picture, stats |
| 36 | FolderContentsRequest | token, folder |
| 37 | FolderContentsResponse | (zlib compressed) |
| 40 | TransferRequest | direction, token, filename, [size if upload] |
| 41 | TransferResponse | token, allowed, [reason if denied] |
| 43 | QueueUpload | filename |
| 44 | PlaceInQueueResponse | filename, place |
| 46 | UploadFailed | filename |
| 50 | UploadDenied | filename, reason |
| 51 | PlaceInQueueRequest | filename |

### Connection Types
- `P` - Peer-to-peer messaging
- `F` - File transfer
- `D` - Distributed network

## Data Types (Little-Endian)

| Type | Size | Notes |
|------|------|-------|
| uint8 | 1 byte | |
| uint16 | 2 bytes | |
| uint32 | 4 bytes | |
| uint64 | 8 bytes | |
| int32 | 4 bytes | Signed |
| bool | 1 byte | 0=false, non-zero=true |
| string | 4+N bytes | uint32 length + UTF-8 data |
| ip | 4 bytes | Little-endian uint32 |

## Message Format

### Server/Peer Messages (P/D connections)
```
[uint32 length][uint32 code][payload...]
```

### Peer Init Messages (connection start)
```
[uint32 length][uint8 code][payload...]
```

### File Transfer (F connection after PeerInit)
```
[uint32 token][uint64 offset][raw file data...]
```

## Transfer Directions
- 0 = Download (peer wants to download from us)
- 1 = Upload (peer is ready to upload to us)

## User Status
- 0 = Offline
- 1 = Away
- 2 = Online

## Common Issues Fixed

1. **Missing PeerInit on outgoing connections** - Peer doesn't know who we are
2. **Wrong CantConnectToPeer code** - Was 36, should be 1001
3. **Wrong PlaceInQueueResponse code** - Was 52, should be 44
4. **Missing UploadDenied handler** - Downloads fail silently
5. **Missing UploadFailed handler** - No error feedback
6. **Missing PierceFirewall handler** - Indirect connections don't work
7. **F connection token matching** - Use username, not token (always 0)
8. **Missing token+offset on F connection** - Uploader doesn't know which transfer
