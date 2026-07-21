---
title: Search API
description: Do searches on the Soulseek network and receive the results.
order: 13
section: package
---

## Start a Search

Searches use tokens. You supply a unique token. The token connects the results to the query:

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

Results arrive asynchronously when peers on the network respond. The callback can fire many times for one search.

## Search Types

### Network Search

The standard search sends your query across the distributed network:

```swift
try await client.search(query: "artist album", token: token)
```

### Room Search

Search the members of one chat room:

```swift
try await client.searchRoom("Electronic Music", query: "ambient", token: token)
```

### User Search

Search the shared files of one user:

```swift
try await client.userSearch(username: "alice", token: token, query: "flac")
```

### Wishlist Search

Add a search that the server repeats at an interval:

```swift
try await client.addWishlistSearch(query: "rare album", token: token)

// The server sets the interval
client.onWishlistInterval = { seconds in
    print("Wishlist searches occur every \(seconds) seconds")
}
```

## SearchResult Model

Each result is a `SearchResult` struct:

```swift
public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String
    public let filename: String      // The full path on the computer of the remote user
    public let size: UInt64
    public let bitrate: UInt32?      // kbps
    public let duration: UInt32?     // seconds
    public let sampleRate: UInt32?   // Hz
    public let bitDepth: UInt32?
    public let isVBR: Bool
    public let freeSlots: Bool       // The user has free upload slots
    public let uploadSpeed: UInt32   // The upload speed of the user
    public let queueLength: UInt32   // The length of the upload queue of the user
    public let isPrivate: Bool       // The file is private
}
```

### Computed Properties

`SearchResult` has properties for display:

```swift
result.displayFilename   // The filename without the path
result.folderPath        // The directory path
result.fileExtension     // "flac", "mp3", and others
result.isAudioFile       // true for known audio formats
result.isLossless        // true for FLAC, WAV, APE, AIFF
result.formattedSize     // "14.2 MB"
result.formattedDuration // "3:45"
result.formattedBitrate  // "320 kbps"
result.formattedSpeed    // "1.2 MB/s"
result.formattedSampleRate // "44.1 kHz"
result.formattedBitDepth   // "24-bit"
```

## SearchQuery Model

Use `SearchQuery` to monitor searches:

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

## Search Responses

Other users search the network. Your client receives their distributed search requests. `NetworkClient` can respond automatically with your shared files:

```swift
// Control of the search responses
client.searchResponseFilter = {
    return (
        enabled: true,
        minQueryLength: 3,
        maxResults: 50
    )
}
```

`NetworkClient` does the response internally. It asks `ShareManager` for files that match the query. Then it sends the results through the peer connection.

## Distributed Search Network

Soulseek uses a distributed search tree. Searches move through a hierarchy of nodes. SeeleseekCore manages this automatically:

```swift
// Permit or block distributed child nodes
try await client.setAcceptDistributedChildren(true)

// Monitor the state of the distributed network
client.distributedBranchLevel  // The level of this client in the tree
client.distributedBranchRoot   // The username of the tree root
client.distributedChildCount   // The number of child connections
```

The distributed network organizes itself. The server assigns the parent nodes. Your client sends searches to its children.
