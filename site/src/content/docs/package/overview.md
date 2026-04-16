---
title: Overview & Architecture
description: Architecture overview of SeeleseekCore, the Swift networking package for the Soulseek protocol.
order: 10
section: package
---

## What is SeeleseekCore?

SeeleseekCore is a Swift package that implements the Soulseek peer-to-peer file sharing protocol. It handles everything from the binary wire protocol to connection management, search, file transfers, and chat — providing a high-level API for building Soulseek clients.

The package is used by the seeleseek macOS app but is designed to be reusable in any Swift project targeting macOS 15+ or iOS 18+.

## Architecture

The package is organized into four layers:

### Protocol Layer (`Network/Protocol/`)

The lowest level. Handles binary message serialization and deserialization.

- **`MessageBuilder`** — constructs binary messages to send to the server or peers
- **`MessageParser`** — parses incoming binary data into structured types
- **`MessageCode`** — enums for all server, peer, and distributed message codes
- **`DataExtensions`** — helpers for reading/writing little-endian integers and strings from `Data`
- **`Decompression`** — zlib decompression for compressed responses (shares, search replies)

### Connection Layer (`Network/Connections/`)

Manages TCP connections to the server and peers.

- **`ServerConnection`** — an `actor` that maintains the TCP connection to the Soulseek server, handles message framing, and exposes an `AsyncStream<Data>` of incoming messages
- **`PeerConnection`** — an `actor` for individual peer-to-peer TCP connections, handling the handshake, message routing, and file transfers
- **`PeerConnectionPool`** — an `@Observable` class that manages the lifecycle of all peer connections, including rate limiting, connection reuse, and statistics

### Service Layer (`Network/Services/`)

Specialized services for specific protocol features.

- **`ListenerService`** — listens for incoming peer connections on a configurable port
- **`NATService`** — handles UPnP port mapping and external IP discovery
- **`GeoIPService`** — resolves IP addresses to country codes for peer geolocation
- **`UserInfoCache`** — caches user country codes and IP addresses

### Coordinator (`Network/NetworkClient.swift`)

The main entry point. `NetworkClient` is an `@Observable @MainActor` class that ties everything together, routing server messages to the appropriate handlers and exposing a callback-based API for the app layer.

## Concurrency Model

SeeleseekCore is built for Swift 6 strict concurrency:

- **Actors** for connection types (`ServerConnection`, `PeerConnection`, `ListenerService`, `NATService`, `GeoIPService`) — isolated mutable state
- **`@MainActor @Observable`** for UI-facing types (`NetworkClient`, `PeerConnectionPool`, `DownloadManager`, `UploadManager`, `ShareManager`, `UserInfoCache`) — observable from SwiftUI
- **`Sendable`** for all model types (`Transfer`, `SearchResult`, `SharedFile`, `User`, etc.)
- **`AsyncStream`** for event delivery from actors to the main actor

## App-Layer Protocols

The package defines several protocols that the app layer must conform to. This keeps the core package free of AppKit/UIKit dependencies:

```swift
// Track downloads and uploads
protocol TransferTracking: AnyObject, Sendable {
    var downloads: [Transfer] { get }
    func addDownload(_ transfer: Transfer)
    func addUpload(_ transfer: Transfer)
    func updateTransfer(id: UUID, update: (inout Transfer) -> Void)
    func getTransfer(id: UUID) -> Transfer?
}

// Record transfer statistics
protocol StatisticsRecording: AnyObject, Sendable {
    func recordTransfer(filename: String, username: String,
                        size: UInt64, duration: TimeInterval, isDownload: Bool)
}

// Provide download path settings
protocol DownloadSettingsProviding: AnyObject, Sendable {
    var activeDownloadTemplate: String { get }
    var setFolderIcons: Bool { get }
}

// Read audio file metadata
protocol MetadataReading: Sendable {
    func extractAudioMetadata(from url: URL) async -> AudioFileMetadata?
    func extractArtwork(from url: URL) async -> Data?
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool
}
```

## Key Types

| Type | Kind | Purpose |
|------|------|---------|
| `NetworkClient` | `@Observable class` | Main coordinator — connect, search, chat, browse |
| `ServerConnection` | `actor` | TCP connection to Soulseek server |
| `PeerConnection` | `actor` | TCP connection to individual peers |
| `PeerConnectionPool` | `@Observable class` | Manages all peer connections |
| `DownloadManager` | `@Observable class` | Queues, initiates, and tracks downloads |
| `UploadManager` | `@Observable class` | Handles upload queue and file serving |
| `ShareManager` | `@Observable class` | Indexes and manages shared folders |
| `MessageBuilder` | `enum` | Constructs binary protocol messages |
| `MessageParser` | `enum` | Parses binary protocol messages |
