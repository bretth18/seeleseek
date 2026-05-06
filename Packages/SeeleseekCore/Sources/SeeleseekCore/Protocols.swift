import Foundation

// MARK: - Connection Status

/// Connection lifecycle state, used by NetworkClient callbacks.
public enum ConnectionStatus: String, CaseIterable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error
}

// MARK: - Activity Logging

/// Protocol for logging user-visible activity events.
/// Implemented by the app's ActivityLog. Core code calls this via `ActivityLogger.shared`.
@MainActor
public protocol ActivityLogging: AnyObject, Sendable {
    func logPeerConnected(username: String, ip: String)
    func logPeerDisconnected(username: String)
    func logSearchStarted(query: String)
    func logSearchResults(query: String, count: Int, user: String)
    func logDownloadStarted(filename: String, from user: String)
    func logDownloadCompleted(filename: String)
    func logUploadStarted(filename: String, to user: String)
    func logUploadCompleted(filename: String)
    func logChatMessage(from user: String, room: String?)
    func logError(_ message: String, detail: String?)
    func logInfo(_ message: String, detail: String?)
    func logConnectionSuccess(username: String, server: String)
    func logConnectionFailed(reason: String)
    func logDisconnected(reason: String?)
    func logRelogged()
    func logRoomJoined(room: String, userCount: Int)
    func logRoomLeft(room: String)
    func logNATMapping(port: UInt16, success: Bool)
    func logDistributedSearch(query: String, matchCount: Int)
}

extension ActivityLogging {
    public func logDisconnected() { logDisconnected(reason: nil) }
    public func logError(_ message: String) { logError(message, detail: nil) }
    public func logInfo(_ message: String) { logInfo(message, detail: nil) }
}

/// Global registry for the activity logger. Set from the app layer at startup.
@MainActor
public enum ActivityLogger {
    public static var shared: (any ActivityLogging)? = nil
}

// MARK: - Transfer Tracking

/// Protocol for tracking transfer state. Implemented by the app's TransferState.
@MainActor
public protocol TransferTracking: AnyObject, Sendable {
    var downloads: [Transfer] { get }
    /// Symmetric to `downloads`. Required by `UploadManager.resumeUploadsOnConnect`
    /// so it can sweep persisted `.failed` upload rows from prior sessions
    /// and re-drive the retriable ones.
    var uploads: [Transfer] { get }
    func addDownload(_ transfer: Transfer)
    func addUpload(_ transfer: Transfer)
    func updateTransfer(id: UUID, update: (inout Transfer) -> Void)
    func getTransfer(id: UUID) -> Transfer?
    /// Indexed lookup for the salvage path in `DownloadManager`: returns the
    /// download (if any) for `(username, filename)` whose status is still
    /// eligible to be lifted into `pendingDownloads` when the peer sends an
    /// unsolicited TransferRequest. Eligible = `.queued`, `.waiting`, or
    /// `.connecting`. Must be O(1) relative to total history size — the old
    /// implementation filtered every entry in `downloads` per peer message.
    func findSalvageableDownload(username: String, filename: String) -> Transfer?
}

// MARK: - Statistics Recording

/// Protocol for recording transfer statistics. Implemented by the app's StatisticsState.
@MainActor
public protocol StatisticsRecording: AnyObject, Sendable {
    func recordTransfer(filename: String, username: String, size: UInt64, duration: TimeInterval, isDownload: Bool)
}

// MARK: - Download Settings

/// Protocol for download-related settings. Implemented by the app's SettingsState.
@MainActor
public protocol DownloadSettingsProviding: AnyObject, Sendable {
    var activeDownloadTemplate: String { get }
    var incompleteDownloadDirectory: URL { get }
    var setFolderIcons: Bool { get }
}

// MARK: - Metadata Reading

/// Basic audio metadata extracted from file tags.
public struct AudioFileMetadata: Sendable {
    public var artist: String?
    public var album: String?
    public var title: String?

    public init(artist: String? = nil, album: String? = nil, title: String? = nil) {
        self.artist = artist
        self.album = album
        self.title = title
    }
}

/// Protocol for reading metadata and applying folder icons.
/// Implemented by the app's MetadataReader (AVFoundation/AppKit-based).
public protocol MetadataReading: Sendable {
    func extractAudioMetadata(from url: URL) async -> AudioFileMetadata?
    func extractArtwork(from url: URL) async -> Data?
    func applyArtworkAsFolderIcon(for directory: URL) async -> Bool
}
