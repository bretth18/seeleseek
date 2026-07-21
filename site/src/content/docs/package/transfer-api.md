---
title: Transfer API
description: Control downloads, uploads, and transfer queues with SeeleseekCore.
order: 14
section: package
---

## Transfer Model

The `Transfer` struct represents all downloads and uploads:

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
    case queued        // The transfer is in the queue
    case connecting    // The peer connection opens
    case transferring  // The data transfer is in progress
    case completed     // The transfer is complete
    case failed        // An error occurred
    case cancelled     // The user cancelled the transfer
    case waiting       // The transfer is on hold, or waits for a slot
}
```

### Computed Properties

```swift
transfer.displayFilename  // The filename without the path
transfer.folderPath       // The directory path, or nil
transfer.isAudioFile      // true for audio formats
transfer.progress         // 0.0 to 1.0
transfer.formattedProgress // "45.2 MB / 100.0 MB"
transfer.formattedSpeed   // "1.5 MB/s"
transfer.isActive         // The transfer is in progress
transfer.canCancel        // A cancel is possible
transfer.canRetry         // A retry is possible
```

## Download Manager

`DownloadManager` controls the full download lifecycle. Configure it with the necessary dependencies first:

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

### Queue a Download

Start a download from a search result:

```swift
downloadManager.queueDownload(from: searchResult)
```

This call does these steps:

1. Makes a `Transfer` with the status `.queued`.
2. Adds the transfer with `TransferTracking.addDownload`.
3. Gets the online status of the user.
4. Requests a peer connection.
5. Sends a `QueueDownload` message to the peer.
6. Waits for a `TransferResponse` that permits the download.
7. Receives the file data on a file transfer connection.
8. Writes the file to the disk and sets the status to `.completed`.

### Incoming Connections

The download manager must receive these connection events:

```swift
// When a peer connects for a queued download
await downloadManager.handleIncomingConnection(
    username: "alice", token: 12345, connection: peerConn
)

// When a file transfer connection opens
await downloadManager.handleFileTransferConnection(
    username: "alice", token: 12345, connection: peerConn
)

// When a peer sends a PierceFirewall connection
await downloadManager.handlePierceFirewall(
    token: 12345, connection: peerConn
)

// When a peer denies a download, or when a download fails
downloadManager.handleUploadDenied(filename: "path/to/file.flac", reason: "Queued")
downloadManager.handleUploadFailed(filename: "path/to/file.flac")
```

### Retry and Cancel

```swift
downloadManager.retryFailedDownload(transferId: transfer.id)
downloadManager.cancelRetry(transferId: transfer.id)
```

### Continue After a Reconnection

After the client connects to the server again, continue the pending downloads:

```swift
downloadManager.resumeDownloadsOnConnect()
```

## Upload Manager

`UploadManager` sends files to users who request downloads from your shares:

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
uploadManager.maxConcurrentUploads = 3   // The default is 3
uploadManager.maxQueuedPerUser = 50      // The default is 50
uploadManager.uploadSpeedLimit = nil     // bytes/sec, nil = no limit

// An optional permission check
uploadManager.uploadPermissionChecker = { username in
    return !blockedUsers.contains(username)
}
```

### Queue Management

```swift
// Get the queue position for a file request
let position = uploadManager.getQueuePosition(for: "path/file.flac", username: "bob")

// Cancel queued or active uploads
uploadManager.cancelQueuedUpload(uploadId)
await uploadManager.cancelActiveUpload(transferId)

// Statistics
uploadManager.activeUploadCount  // The number of active uploads
uploadManager.queueDepth         // The number of uploads in the queue
uploadManager.slotsSummary       // "3/5"
```

## Share Manager

`ShareManager` makes an index of your shared folders. The index supplies the search responses and the uploads:

```swift
let shareManager = ShareManager()

// Add folders to share
shareManager.addFolder(musicFolderURL)

// Scan all folders again (for example, after file changes)
await shareManager.rescanAll()

// Search your shares (used for the responses to network searches)
let matches = await shareManager.search(query: "boards of canada")

// Get the share statistics
shareManager.totalFiles    // The number of files in the index
shareManager.totalFolders  // The number of shared folders
shareManager.totalSize     // The total bytes

// Convert to the protocol format for transmission to peers
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
    public var displayName: String  // The last path component
}
```

### IndexedFile Model

```swift
public struct IndexedFile: Identifiable, Sendable {
    public let id: UUID
    public let localPath: String      // The absolute path on the disk
    public let sharedPath: String     // The path that peers see
    public let filename: String
    public let size: UInt64
    public let bitrate: UInt32?
    public let duration: UInt32?
    public let fileExtension: String
}
```
