---
title: Search API
description: Performing searches on the Soulseek network and handling results.
order: 13
section: package
---

## Performing a Search

Searches are token-based — you provide a unique token to match results back to the query:

```swift
let token = UInt32.random(in: 0...UInt32.max)

client.onSearchResults = { resultToken, results in
    if resultToken == token {
        for result in results {
            print("\(result.username): \(result.filename) (\(result.formattedSize))")
        }
    }
}

try await client.search(query: "boards of canada", token: token)
```

Results arrive asynchronously as peers on the network respond. The callback may fire many times for a single search.

## Search Types

### Network Search

The standard search broadcasts your query across the distributed network:

```swift
try await client.search(query: "artist album", token: token)
```

### Room Search

Search within a specific chat room's members:

```swift
try await client.searchRoom("Electronic Music", query: "ambient", token: token)
```

### User Search

Search a specific user's shared files:

```swift
try await client.userSearch(username: "alice", token: token, query: "flac")
```

### Wishlist Search

Add a recurring search that the server runs periodically:

```swift
try await client.addWishlistSearch(query: "rare album", token: token)

// The server tells us the interval
client.onWishlistInterval = { seconds in
    print("Wishlist searches run every \(seconds) seconds")
}
```

## SearchResult Model

Each result is a `SearchResult` struct:

```swift
public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String
    public let filename: String      // Full path on remote user's machine
    public let size: UInt64
    public let bitrate: UInt32?      // kbps
    public let duration: UInt32?     // seconds
    public let sampleRate: UInt32?   // Hz
    public let bitDepth: UInt32?
    public let isVBR: Bool
    public let freeSlots: Bool       // User has free upload slots
    public let uploadSpeed: UInt32   // User's upload speed
    public let queueLength: UInt32   // User's upload queue length
    public let isPrivate: Bool       // File is private/restricted
}
```

### Computed Properties

`SearchResult` includes convenience properties for display:

```swift
result.displayFilename   // Just the filename without path
result.folderPath        // Directory path
result.fileExtension     // "flac", "mp3", etc.
result.isAudioFile       // True for known audio formats
result.isLossless        // True for FLAC, WAV, APE, AIFF
result.formattedSize     // "14.2 MB"
result.formattedDuration // "3:45"
result.formattedBitrate  // "320 kbps"
result.formattedSpeed    // "1.2 MB/s"
result.formattedSampleRate // "44.1 kHz"
result.formattedBitDepth   // "24-bit"
```

## SearchQuery Model

To track searches, use `SearchQuery`:

```swift
public struct SearchQuery: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let token: UInt32
    public let timestamp: Date
    public var results: [SearchResult]
    public var isSearching: Bool

    public var resultCount: Int
    public var uniqueUsers: Int
}
```

## Responding to Searches

When other users search the network, your client receives distributed search requests. `NetworkClient` can automatically respond using your shared files:

```swift
// Control search response behavior
client.searchResponseFilter = {
    return (
        enabled: true,
        minQueryLength: 3,
        maxResults: 50
    )
}
```

The response is handled internally — `NetworkClient` queries the `ShareManager` for matching files and sends results back via the peer connection.

## Distributed Search Network

Soulseek uses a distributed search tree where searches propagate through a hierarchy of nodes. SeeleseekCore manages this automatically:

```swift
// Whether to accept distributed children nodes
try await client.setAcceptDistributedChildren(true)

// Monitor distributed network state
client.distributedBranchLevel  // Our level in the tree
client.distributedBranchRoot   // Username of tree root
client.distributedChildCount   // Number of child connections
```

The distributed network is self-organizing — the server assigns parent nodes and your client forwards searches to its children.
