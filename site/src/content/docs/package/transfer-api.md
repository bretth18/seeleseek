---
title: Transfer API
description: Managing downloads, uploads, and transfer queues with SeeleseekCore.
order: 14
section: package
---

## Transfer Model

All transfers (downloads and uploads) are represented by the `Transfer` struct:

```swift
public struct Transfer: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let username: String
    public let filename: String
    public let size: UInt64
    public let direction: TransferDirection  // .download or .upload
    public var status: TransferStatus
    public var bytesTransferred: UInt64
    public var startTime: Date?
    public var speed: Int64                  // bytes/sec
    public var queuePosition: Int?
    public var error: String?
    public var localPath: URL?
    public var retryCount: Int
}
```

### Transfer Status

```swift
public enum TransferStatus: String, Sendable {
    case queued        // Waiting in queue
    case connecting    // Establishing peer connection
    case transferring  // Actively transferring data
    case completed     // Transfer finished
    case failed        // Error occurred
    case cancelled     // User cancelled
    case waiting       // Paused / waiting for slot
}
```

### Computed Properties

```swift
transfer.displayFilename  // Filename without path
transfer.folderPath       // Directory path or nil
transfer.isAudioFile      // True for audio formats
transfer.progress         // 0.0 to 1.0
transfer.formattedProgress // "45.2 MB / 100.0 MB"
transfer.formattedSpeed   // "1.5 MB/s"
transfer.isActive         // Currently transferring
transfer.canCancel        // Can be cancelled
transfer.canRetry         // Can be retried
```

## Download Manager

`DownloadManager` handles the full download lifecycle. Before using it, configure it with the required dependencies:

```swift
let downloadManager = DownloadManager()

downloadManager.configure(
    networkClient: client,
    transferState: myTransferTracker,       // TransferTracking
    statisticsState: myStatsRecorder,       // StatisticsRecording
    uploadManager: uploadManager,
    settings: myDownloadSettings,           // DownloadSettingsProviding
    metadataReader: myMetadataReader        // MetadataReading
)
```

### Queueing Downloads

Start a download from a search result:

```swift
downloadManager.queueDownload(from: searchResult)
```

This:
1. Creates a `Transfer` with status `.queued`
2. Adds it via `TransferTracking.addDownload`
3. Checks the user's online status
4. Requests a peer connection
5. Sends a `QueueDownload` message to the peer
6. Waits for a `TransferResponse` granting the download
7. Receives the file data over a dedicated file transfer connection
8. Writes to disk and marks as `.completed`

### Handling Incoming Connections

The download manager needs to handle various connection events:

```swift
// When a peer connects for a queued download
await downloadManager.handleIncomingConnection(
    username: "alice", token: 12345, connection: peerConn
)

// When a file transfer connection is established
await downloadManager.handleFileTransferConnection(
    username: "alice", token: 12345, connection: peerConn
)

// When a peer pierces our firewall
await downloadManager.handlePierceFirewall(
    token: 12345, connection: peerConn
)

// When a download is denied or fails
downloadManager.handleUploadDenied(filename: "path/to/file.flac", reason: "Queued")
downloadManager.handleUploadFailed(filename: "path/to/file.flac")
```

### Retry and Cancel

```swift
downloadManager.retryFailedDownload(transferId: transfer.id)
downloadManager.cancelRetry(transferId: transfer.id)
```

### Resume on Reconnect

After reconnecting to the server, resume pending downloads:

```swift
downloadManager.resumeDownloadsOnConnect()
```

## Upload Manager

`UploadManager` serves files to other users who request downloads from your shares:

```swift
let uploadManager = UploadManager()

uploadManager.configure(
    networkClient: client,
    transferState: myTransferTracker,
    shareManager: shareManager,
    statisticsState: myStatsRecorder
)
```

### Configuration

```swift
uploadManager.maxConcurrentUploads = 3   // Default: 3
uploadManager.maxQueuedPerUser = 50      // Default: 50
uploadManager.uploadSpeedLimit = nil     // bytes/sec, nil = unlimited

// Optional permission checker
uploadManager.uploadPermissionChecker = { username in
    return !blockedUsers.contains(username)
}
```

### Queue Management

```swift
// Check queue position for a file request
let position = uploadManager.getQueuePosition(for: "path/file.flac", username: "bob")

// Cancel queued or active uploads
uploadManager.cancelQueuedUpload(uploadId)
await uploadManager.cancelActiveUpload(transferId)

// Stats
uploadManager.activeUploadCount  // Currently transferring
uploadManager.queueDepth         // Waiting in queue
uploadManager.slotsSummary       // "3/5"
```

## Share Manager

`ShareManager` indexes your shared folders so they can be searched and served:

```swift
let shareManager = ShareManager()

// Add folders to share
shareManager.addFolder(musicFolderURL)

// Rescan all folders (e.g., after files change)
await shareManager.rescanAll()

// Search your shares (used for responding to network searches)
let matches = await shareManager.search(query: "boards of canada")

// Get share stats
shareManager.totalFiles    // Total indexed files
shareManager.totalFolders  // Total shared folders
shareManager.totalSize     // Total bytes

// Convert to protocol format for sending to peers
let sharedFiles = shareManager.toSharedFiles()
```

### SharedFolder Model

```swift
public struct SharedFolder: Identifiable, Codable, Hashable {
    public let id: UUID
    public let path: String
    public var fileCount: Int
    public var totalSize: UInt64
    public var lastScanned: Date?
    public var displayName: String  // Last path component
}
```

### IndexedFile Model

```swift
public struct IndexedFile: Identifiable, Sendable {
    public let id: UUID
    public let localPath: String      // Absolute path on disk
    public let sharedPath: String     // Path as shown to peers
    public let filename: String
    public let size: UInt64
    public let bitrate: UInt32?
    public let duration: UInt32?
    public let fileExtension: String
}
```
