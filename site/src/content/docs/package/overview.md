---
title: Overview and Architecture
description: The architecture of SeeleseekCore, the Swift networking package for the Soulseek protocol.
order: 10
section: package
---

## What is SeeleseekCore?

SeeleseekCore is a Swift package that implements the Soulseek peer-to-peer file sharing protocol. The package contains the binary wire protocol, connection management, search, file transfers, and chat. It supplies a high-level API for Soulseek clients.

The seeleseek macOS app uses this package. You can also use the package in other Swift projects for macOS 15+ or iOS 18+.

## Architecture

The package has four layers:

### Protocol Layer (`Network/Protocol/`)

The lowest layer. It serializes and deserializes binary messages.

- **`MessageBuilder`** — Makes the binary messages for the server and for peers
- **`MessageParser`** — Parses incoming binary data into structured types
- **`MessageCode`** — Enums for all server, peer, and distributed message codes
- **`DataExtensions`** — Helper functions that read and write little-endian integers and strings in `Data`
- **`Decompression`** — zlib decompression for compressed responses (shares, search replies)

### Connection Layer (`Network/Connections/`)

This layer manages the TCP connections to the server and to peers.

- **`ServerConnection`** — An `actor` that holds the TCP connection to the Soulseek server. It does the message framing and supplies an `AsyncStream<Data>` of incoming messages.
- **`PeerConnection`** — An `actor` for one peer-to-peer TCP connection. It does the handshake, the message routing, and the file transfers.
- **`PeerConnectionPool`** — An `@Observable` class that manages the lifecycle of all peer connections. It does rate limits, connection reuse, and statistics.

### Service Layer (`Network/Services/`)

Services for specific protocol features.

- **`ListenerService`** — Listens for incoming peer connections on a configurable port
- **`NATService`** — Does the UPnP port mapping and finds the external IP
- **`GeoIPService`** — Converts IP addresses to country codes for peer geolocation
- **`UserInfoCache`** — Keeps the country codes and IP addresses of users

### Coordinator (`Network/NetworkClient.swift`)

The main entry point. `NetworkClient` is an `@Observable @MainActor` class. It connects the layers, routes server messages to the applicable handlers, and supplies a callback API for the app layer.

## Concurrency Model

SeeleseekCore is built for Swift 6 strict concurrency:

- **Actors** for connection types (`ServerConnection`, `PeerConnection`, `ListenerService`, `NATService`, `GeoIPService`) — isolated mutable state
- **`@MainActor @Observable`** for UI types (`NetworkClient`, `PeerConnectionPool`, `DownloadManager`, `UploadManager`, `ShareManager`, `UserInfoCache`) — observable from SwiftUI
- **`Sendable`** for all model types (`Transfer`, `SearchResult`, `SharedFile`, `User`, and others)
- **`AsyncStream`** for events from actors to the main actor

## App-Layer Protocols

The package defines protocols that the app layer must implement. This keeps AppKit and UIKit out of the core package:

```swift
// Monitor downloads and uploads
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

// Supply the download path settings
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

| Type | Kind | Function |
|------|------|----------|
| `NetworkClient` | `@Observable class` | The main coordinator — connect, search, chat, browse |
| `ServerConnection` | `actor` | The TCP connection to the Soulseek server |
| `PeerConnection` | `actor` | A TCP connection to one peer |
| `PeerConnectionPool` | `@Observable class` | Manages all peer connections |
| `DownloadManager` | `@Observable class` | Queues, starts, and monitors downloads |
| `UploadManager` | `@Observable class` | Manages the upload queue and sends files |
| `ShareManager` | `@Observable class` | Makes and manages the index of shared folders |
| `MessageBuilder` | `enum` | Makes binary protocol messages |
| `MessageParser` | `enum` | Parses binary protocol messages |
