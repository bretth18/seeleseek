# SeeleSeek Codebase Audit Report
**Date:** 2026-02-05
**Auditor:** Claude Opus 4.6
**Reference:** PROTOCOL_REFERENCE_FULL.md + Nicotine+ (nicotine-plus/nicotine-plus)

---

## 1. CRITICAL -- Protocol Correctness Bugs

### 1.1 IP Byte Order Inconsistency

Two different IP parsing strategies exist in the codebase and one is wrong.

**`ServerMessageHandler.swift:1177-1184`** -- Big-endian extraction (CORRECT per Nicotine+):
```swift
let b1 = (value >> 24) & 0xFF  // first octet from MSB
```

**`MessageParser.swift:56` and `MessageParser.swift:133`** -- Little-endian extraction (WRONG):
```swift
"\(ip & 0xFF).\((ip >> 8) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 24) & 0xFF)"
```

The protocol stores IP addresses on the wire such that when read as a LE uint32, the resulting integer value represents the IP in network byte order (big-endian). Nicotine+ confirms this: it reads the uint32 as LE, then does `inet_ntoa(struct.pack("!I", value))` to extract octets from MSB-first.

**Impact:** `parseLoginResponse` reports the user's own IP with reversed octets (e.g., `1.1.168.192` instead of `192.168.1.1`). `parseConnectToPeer` in MessageParser would also produce wrong IPs if called.

### 1.2 Missing Zlib Compression for FileSearchResponse (Peer Code 9)

`MessageBuilder.searchReplyMessage()` at line 257 does **not** zlib-compress the payload. Per the protocol reference and Nicotine+'s implementation, the entire payload of FileSearchResponse (peer code 9) **must** be zlib-compressed.

Compare with `sharesReplyMessage()` (code 5) and `folderContentsResponseMessage()` (code 37), which both correctly compress.

**Impact:** Other SoulSeek clients will attempt to zlib-decompress the search reply and fail, meaning your search results are invisible to the network.

### 1.3 Hardcoded Values in searchReplyMessage

At `MessageBuilder.swift:280-283`:
```swift
payload.appendBool(true)   // has free slots -- hardcoded
payload.appendUInt32(100)  // upload speed -- hardcoded
payload.appendUInt32(0)    // queue length -- hardcoded
```

These should reflect actual state (slot availability, real upload speed, real queue depth).

### 1.4 ServerMessageCode.getMoreParents = 41 Should Be "Relogged"

Per the protocol reference, server code 41 is **Relogged** -- sent by the server when another client logs in with your username. The codebase maps it to `getMoreParents` and never handles it.

**Impact:** When a user logs in from a second device, the first device will not detect it has been kicked from the server. The connection silently becomes stale.

### 1.5 ServerMessageCode.sendUploadSpeed = 34 Is Undocumented

The protocol reference defines **SendUploadSpeed as code 121**, which the codebase correctly has as `sendUploadSpeedRequest = 121`. Code 34 is not in the protocol reference. The `sendUploadSpeed = 34` entry appears to be from an older protocol revision or a misattribution.

### 1.6 SetListenPort Message Format

`MessageBuilder.setListenPortMessage()` always sends two fields: `[port] [obfuscatedPort]`. Per the protocol, the format is `[port]` only (obfuscation optional with 3 fields). Nicotine+ only sends the port field. Sending the extra `0` is likely interpreted by the server as `obfuscation_type=0` (none), which is harmless but technically incorrect.

### 1.7 Login Minor Version

seeleseek sends minor version `1`, Nicotine+ sends `3`. Low risk but could matter if the server uses it for feature negotiation.

---

## 2. HIGH -- Concurrency Issues

### 2.1 `nonisolated(unsafe)` Usage (13 occurrences)

| File | Line | Variable | Risk |
|------|------|----------|------|
| `NATService.swift` | 218 | `didComplete` | Data race on continuation flag |
| `NATService.swift` | 409 | `request` | Mutable Data across boundaries |
| `NATService.swift` | 418 | `didComplete` | Data race on continuation flag |
| `NATService.swift` | 475 | `request` | Mutable Data across boundaries |
| `NATService.swift` | 485 | `didComplete` | Data race on continuation flag |
| `ListenerService.swift` | 103 | `hasResumed` | Data race on continuation flag |
| `NetworkClient.swift` | 813 | `sharesResumed` | Data race on continuation flag |
| `NetworkClient.swift` | 814 | `receivedFiles` | Mutable array across boundaries |
| `PeerConnection.swift` | 54 | `peerInfo` | Mutable struct on actor |
| `UploadManager.swift` | 492 | `hasResumed` | Data race on continuation flag |
| `SettingsView.swift` | 752 | `didComplete` | Data race on continuation flag |

The continuation-flag pattern (`nonisolated(unsafe) var hasResumed = false`) wrapping `withCheckedThrowingContinuation` is a common data race. Use `Mutex<Bool>` (Swift 6) or `os_unfair_lock`-based synchronization.

### 2.2 Fire-and-Forget Tasks

**`AppState.swift:72`** -- Database init runs in an unstructured `Task {}`.
**`NetworkClient.disconnect()`** -- Creates a Task to perform async cleanup but doesn't await it.

### 2.3 Login Wait is Hardcoded Sleep

`Task.sleep(for: .milliseconds(500))` after login instead of awaiting the login response.

---

## 3. MEDIUM -- Protocol Implementation Gaps

### 3.1 Missing Server Message Handlers

| Code | Message | Impact |
|------|---------|--------|
| 41 | Relogged | Won't detect being kicked |
| 130 | ResetDistributed | Won't reset distributed network on server request |
| 160 | ExcludedSearchPhrases | Ignores banned search terms |

### 3.2 Max Message Size Too Small

`MessageParser.maxMessageSize` is 10MB. Nicotine+ allows up to 448MB for peer messages. Large shared file lists from power users could exceed 10MB.

### 3.3 Missing Search Token Validation

Nicotine+ tracks allowed search tokens and skips parsing responses for unknown tokens. On busy networks this is a significant CPU optimization.

### 3.4 Zlib Compression Buffer Too Small

`compressZlib()` uses a fixed 64KB output buffer. Large share lists may exceed this, causing silent compression failure and fallback to uncompressed data (which other clients can't parse).

---

## 4. LOW -- Code Quality

### 4.1 Debug Prints in Production Code

Extensive `print("emoji ...")` statements throughout production code. Should use `os.Logger`.

### 4.2 Duplicate Convenience Methods in MessageBuilder

Two styles for many messages: `loginMessage()` vs `login()`, `fileSearchMessage()` vs `fileSearch()`, etc.

### 4.3 PeerMessageCode Enum Mixing Init and Peer Codes

Combines peer init codes (uint8) with peer message codes (uint32) in one enum.

---

## 5. Security Notes

Solid security fundamentals with message size limits, connection limits, decompression bomb protection, and Keychain credential storage.

**One concern:** Zlib compression buffer size (64KB fixed) could cause silent failures for large data.

---

## 6. Additional Findings from Nicotine+ Cross-Reference

- PeerInit token should be 0 for direct connections (Nicotine+ convention)
- F-connection handshake uses raw bytes (no length prefix) for FileTransferInit (4 bytes) and FileOffset (8 bytes)
- Ghost connection timeout matches at 10 seconds (good)
- Indirect connection timeout: 20 seconds in Nicotine+ vs 10 seconds in seeleseek
