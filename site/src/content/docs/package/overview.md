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
- **`PeerConnectionPool`** — An `actor` that manages the lifecycle of all peer connections. It does rate limits, connection reuse, and statistics. The UI observes its `monitor` mirror.

### Service Layer (`Network/Services/`)

Services for specific protocol features.

- **`ListenerService`** — Listens for incoming peer connections on a configurable port
- **`NATService`** — Does the UPnP port mapping and finds the external IP
- **`GeoIPService`** — Converts IP addresses to country codes for peer geolocation
- **`UserInfoCache`** — Keeps the country codes and IP addresses of users

### Coordinator (`Network/NetworkClient.swift`)

The main entry point. `NetworkClient` is an `actor`. It connects the layers and routes server messages to the applicable handlers. The app layer receives events from `client.events` (the event bus) and observes the `client.status` and `client.monitor` mirrors from SwiftUI.

## Concurrency Model

SeeleseekCore is built for Swift 6 strict concurrency, with the Swift 6.2 caller-isolation semantics (`NonisolatedNonsendingByDefault`):

- **Actors** for the network and storage subsystems (`NetworkClient`, `PeerConnectionPool`, `ShareManager`, `DownloadManager`, `UploadManager`, `ServerConnection`, `PeerConnection`, `ListenerService`, `NATService`, `GeoIPService`) — isolated mutable state, off the main actor
- **`@MainActor @Observable` mirrors** for the UI (`NetworkStatusState`, `NetworkMonitorState`, `ShareState`, `UploadState`, `UserInfoCache`) — fed with value snapshots, observable from SwiftUI
- **Event bus** (`NetworkEventBus`) — one multi-subscriber channel for each event domain (chat, social, search, connection, transfers, transfer notices). Subscribe before you connect.
- **`Sendable`** for all model types (`Transfer`, `SearchResult`, `SharedFile`, `User`, and others)
- **`@concurrent` functions** for CPU-bound and disk-bound work (index walks, file scans, metadata reads)

## App-Layer Protocols

The package defines protocols that the app layer must implement. This keeps AppKit and UIKit out of the core package:

```swift
// Monitor downloads and uploads
protocol TransferTracking: AnyObject, Sendable {
    var downloads: [Transfer] { get }
    func addDownload(_ transfer: Transfer)
    func addUpload(_ transfer: Transfer)
    func updateTransfer(id: UUID, update: @Sendable (inout Transfer) -> Void)
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
| `NetworkClient` | `actor` | The main coordinator — connect, search, chat, browse |
| `NetworkEventBus` | `class` | Multi-subscriber event channels for each domain |
| `NetworkStatusState` | `@MainActor @Observable` | Connection-state mirror for the UI |
| `NetworkMonitorState` | `@MainActor @Observable` | Pool-statistics mirror for the UI |
| `ServerConnection` | `actor` | The TCP connection to the Soulseek server |
| `PeerConnection` | `actor` | A TCP connection to one peer |
| `PeerConnectionPool` | `actor` | Manages all peer connections |
| `DownloadManager` | `actor` | Queues, starts, and monitors downloads |
| `UploadManager` | `actor` | Manages the upload queue and sends files |
| `ShareManager` | `actor` | Makes and manages the index of shared folders |
| `MessageBuilder` | `enum` | Makes binary protocol messages |
| `MessageParser` | `enum` | Parses binary protocol messages |
