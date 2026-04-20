import SwiftUI
import Combine
import os
import SeeleseekCore

/// Represents a completed transfer in history
struct TransferHistoryItem: Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let filename: String
    let username: String
    let size: Int64
    let duration: TimeInterval
    let averageSpeed: Double
    let isDownload: Bool
    let localPath: URL?

    /// Resolved local path - uses stored path, or tries the default download location
    var resolvedLocalPath: URL? {
        if let localPath, FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }
        // Try default download directory: ~/Downloads/SeeleSeek/{username}/{folders}/{filename}
        return Self.inferDownloadPath(filename: filename, username: username)
    }

    var fileExists: Bool {
        resolvedLocalPath != nil
    }

    var isAudioFile: Bool {
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "alac", "wma", "ape", "aif"]
        let ext = (displayFilename as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }

    /// Reconstruct the likely download path from the soulseek filename
    private static func inferDownloadPath(filename: String, username: String) -> URL? {
        let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        let baseDir = paths[0].appendingPathComponent("SeeleSeek")

        var components = filename.split(separator: "\\").map(String.init)
        // Strip @@ root share marker
        if !components.isEmpty && components[0].hasPrefix("@@") {
            components.removeFirst()
        }
        guard !components.isEmpty else { return nil }

        // Default template: {username}/{folders}/{filename}
        var url = baseDir.appendingPathComponent(username)
        for component in components {
            url = url.appendingPathComponent(component)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    var displayFilename: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    var formattedSize: String {
        size.formattedBytes
    }

    var formattedSpeed: String {
        averageSpeed.formattedSpeed
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Informs an observer about peer-status lifecycle events so the app can
/// subscribe to live online/offline updates while transfers exist.
@MainActor
protocol PeerWatching: AnyObject {
    func watchPeer(_ username: String)
    func unwatchPeer(_ username: String)
}

@Observable
@MainActor
final class TransferState: TransferTracking {
    /// Peer-status observer (typically `SocialState`). Set once at app
    /// startup. Notifications fire whenever a transfer is added or removed
    /// so the watcher can subscribe/unsubscribe to live user status.
    /// Assigning the watcher also back-fills watches for every peer in
    /// the currently-loaded list — `loadPersisted()` typically runs
    /// before the lazy `networkClient` is touched, and we don't want the
    /// first wave of persisted transfers to come up with no live status.
    weak var peerWatcher: (any PeerWatching)? {
        didSet { reconcilePeerWatches() }
    }

    /// Usernames we currently hold a watch on. Prevents double-subscribing
    /// the same user when both a download and upload exist for them, or
    /// when `loadPersisted()` and `didSet` both try to back-fill.
    private var watchedUsernames: Set<String> = []

    private func reconcilePeerWatches() {
        guard let peerWatcher else {
            watchedUsernames.removeAll()
            return
        }
        let desired = Set((downloads + uploads).map { $0.username })
        for name in desired.subtracting(watchedUsernames) {
            peerWatcher.watchPeer(name)
        }
        for name in watchedUsernames.subtracting(desired) {
            peerWatcher.unwatchPeer(name)
        }
        watchedUsernames = desired
    }

    private func startWatch(_ username: String) {
        guard let peerWatcher,
              !username.isEmpty,
              !watchedUsernames.contains(username) else { return }
        peerWatcher.watchPeer(username)
        watchedUsernames.insert(username)
    }
    // MARK: - Transfers
    var downloads: [Transfer] = [] {
        didSet { rebuildDownloadIndex() }
    }
    var uploads: [Transfer] = []

    // MARK: - Download Status Index (O(1) lookup)
    private(set) var downloadStatusIndex: [String: Transfer.TransferStatus] = [:]

    private func rebuildDownloadIndex() {
        var index: [String: Transfer.TransferStatus] = [:]
        index.reserveCapacity(downloads.count)
        for transfer in downloads {
            index["\(transfer.username)\0\(transfer.filename)"] = transfer.status
        }
        downloadStatusIndex = index
    }

    // MARK: - History
    var history: [TransferHistoryItem] = []

    // MARK: - Stats
    var totalDownloadSpeed: Int64 = 0
    var totalUploadSpeed: Int64 = 0
    var totalDownloaded: Int64 = 0
    var totalUploaded: Int64 = 0

    // MARK: - Speed History (per-transfer ring buffer for sparklines)
    /// 1-sample-per-second speed history, oldest → newest, capped at 30
    /// entries (~30 seconds of context). Populated while the transfer is
    /// active and retained after completion so completed rows still show
    /// their final curve. Pruned in the removal paths
    /// (`removeTransfer` / `clearCompleted` / `clearFailed`) so the dict
    /// doesn't grow unboundedly with the lifetime cumulative transfer count.
    private(set) var speedHistory: [UUID: [Int64]] = [:]
    private static let speedHistoryLimit = 30

    // Speed update timer
    private var speedUpdateTimer: Timer?
    private let logger = Logger(subsystem: "com.seeleseek", category: "TransferState")

    init() {
        startSpeedUpdates()
    }

    private func startSpeedUpdates() {
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.updateSpeeds()
            }
        }
    }

    // MARK: - Computed Properties
    var activeDownloads: [Transfer] {
        downloads.filter { $0.isActive }
    }

    var activeUploads: [Transfer] {
        uploads.filter { $0.isActive }
    }

    var queuedDownloads: [Transfer] {
        downloads.filter { $0.status == .queued || $0.status == .waiting }
    }

    var completedDownloads: [Transfer] {
        downloads.filter { $0.status == .completed }
    }

    var failedDownloads: [Transfer] {
        downloads.filter { $0.status == .failed || $0.status == .cancelled }
    }

    var hasActiveTransfers: Bool {
        !activeDownloads.isEmpty || !activeUploads.isEmpty
    }

    // MARK: - Persistence

    /// Load persisted transfers from database
    func loadPersisted() async {
        do {
            var persisted = try await TransferRepository.fetchPersisted()

            // Reset stale active statuses — these were mid-transfer when the app quit
            for i in persisted.indices {
                if persisted[i].status == .connecting || persisted[i].status == .transferring {
                    persisted[i].status = .queued
                    persisted[i].speed = 0
                }
            }

            downloads = persisted.filter { $0.direction == .download }
            uploads = persisted.filter { $0.direction == .upload }
            logger.info("Loaded \(self.downloads.count) downloads and \(self.uploads.count) uploads from database")

            // Subscribe to status updates for every peer we just loaded
            // so offline state is visible as soon as rows render. Safe to
            // call even if `peerWatcher` is still nil — the didSet on
            // assignment will back-fill.
            reconcilePeerWatches()

            // Also load history
            await loadHistory()
        } catch {
            logger.error("Failed to load persisted transfers: \(error.localizedDescription)")
        }
    }

    /// Load transfer history from database
    func loadHistory() async {
        do {
            let records = try await TransferHistoryRepository.fetchRecent(limit: 200)
            history = records.map { record in
                TransferHistoryItem(
                    id: record.id,
                    timestamp: Date(timeIntervalSince1970: record.timestamp),
                    filename: record.filename,
                    username: record.username,
                    size: record.size,
                    duration: record.duration,
                    averageSpeed: record.averageSpeed,
                    isDownload: record.isDownload,
                    localPath: record.localPath.map { URL(fileURLWithPath: $0) }
                )
            }
            logger.info("Loaded \(self.history.count) history entries from database")

            // Update totals
            let stats = try await TransferHistoryRepository.getStats()
            totalDownloaded = stats.totalDownloadedBytes
            totalUploaded = stats.totalUploadedBytes
        } catch {
            logger.error("Failed to load transfer history: \(error.localizedDescription)")
        }
    }

    /// Clear all history
    func clearHistory() {
        history.removeAll()
        totalDownloaded = 0
        totalUploaded = 0

        Task {
            try? await TransferHistoryRepository.deleteOlderThan(Date.distantFuture)
        }
    }

    /// Persist a transfer to database
    private func persistTransfer(_ transfer: Transfer) {
        Task {
            do {
                try await TransferRepository.save(transfer)
            } catch {
                logger.error("Failed to persist transfer: \(error.localizedDescription)")
            }
        }
    }

    /// Record transfer completion to history
    private func recordCompletion(_ transfer: Transfer) {
        Task {
            do {
                try await TransferRepository.recordCompletion(transfer)
                // Reload history to include the new entry
                await loadHistory()
            } catch {
                logger.error("Failed to record transfer completion: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions

    func getTransfer(id: UUID) -> Transfer? {
        if let transfer = downloads.first(where: { $0.id == id }) {
            return transfer
        }
        return uploads.first(where: { $0.id == id })
    }

    /// Check if a file is already queued or downloading
    func downloadStatus(for filename: String, from username: String) -> Transfer.TransferStatus? {
        downloadStatusIndex["\(username)\0\(filename)"]
    }

    /// Check if any file with this exact path exists in downloads (any state except completed/cancelled)
    func isFileQueued(filename: String, username: String) -> Bool {
        guard let status = downloadStatusIndex["\(username)\0\(filename)"] else { return false }
        return status != .completed && status != .cancelled
    }

    func addDownload(_ transfer: Transfer) {
        downloads.insert(transfer, at: 0)
        persistTransfer(transfer)
        startWatch(transfer.username)
    }

    func addUpload(_ transfer: Transfer) {
        uploads.insert(transfer, at: 0)
        persistTransfer(transfer)
        startWatch(transfer.username)
    }

    func updateTransfer(id: UUID, update: (inout Transfer) -> Void) {
        var updatedTransfer: Transfer?

        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let previousStatus = downloads[index].status
            update(&downloads[index])
            updatedTransfer = downloads[index]

            // Record completion if status changed to completed
            if previousStatus != .completed && downloads[index].status == .completed {
                recordCompletion(downloads[index])
            }
        } else if let index = uploads.firstIndex(where: { $0.id == id }) {
            let previousStatus = uploads[index].status
            update(&uploads[index])
            updatedTransfer = uploads[index]

            // Record completion if status changed to completed
            if previousStatus != .completed && uploads[index].status == .completed {
                recordCompletion(uploads[index])
            }
        }

        // Persist the update
        if let transfer = updatedTransfer {
            persistTransfer(transfer)
        }
    }

    func cancelTransfer(id: UUID) {
        updateTransfer(id: id) { transfer in
            transfer.status = .cancelled
        }
    }

    func retryTransfer(id: UUID) {
        updateTransfer(id: id) { transfer in
            transfer.status = .queued
            transfer.bytesTransferred = 0
            transfer.error = nil
        }
    }

    func removeTransfer(id: UUID) {
        downloads.removeAll { $0.id == id }
        uploads.removeAll { $0.id == id }
        speedHistory.removeValue(forKey: id)
        reconcilePeerWatches()

        // Remove from database
        Task {
            try? await TransferRepository.delete(id: id)
        }
    }

    func clearCompleted() {
        let removedIds = (downloads + uploads)
            .filter { $0.status == .completed }
            .map(\.id)
        downloads.removeAll { $0.status == .completed }
        uploads.removeAll { $0.status == .completed }
        for id in removedIds { speedHistory.removeValue(forKey: id) }
        reconcilePeerWatches()

        // Clear from database
        Task {
            try? await TransferRepository.deleteCompleted()
        }
    }

    func clearFailed() {
        let removedIds = (downloads + uploads)
            .filter { $0.status == .failed || $0.status == .cancelled }
            .map(\.id)
        downloads.removeAll { $0.status == .failed || $0.status == .cancelled }
        uploads.removeAll { $0.status == .failed || $0.status == .cancelled }
        for id in removedIds { speedHistory.removeValue(forKey: id) }
        reconcilePeerWatches()

        // Clear from database
        Task {
            try? await TransferRepository.deleteFailed()
        }
    }

    func moveDownload(from source: IndexSet, to destination: Int) {
        downloads.move(fromOffsets: source, toOffset: destination)
    }

    func moveDownloadToTop(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let transfer = downloads.remove(at: index)
        downloads.insert(transfer, at: 0)
    }

    func moveDownloadToBottom(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let transfer = downloads.remove(at: index)
        downloads.append(transfer)
    }

    func updateSpeeds() {
        totalDownloadSpeed = activeDownloads.reduce(0) { $0 + $1.speed }
        totalUploadSpeed = activeUploads.reduce(0) { $0 + $1.speed }
        sampleSpeedHistory()
    }

    /// Append the current speed reading for each active transfer to its
    /// history buffer, capped at `speedHistoryLimit` entries. Called once
    /// per second from the speed-update timer.
    private func sampleSpeedHistory() {
        for transfer in activeDownloads {
            appendSample(transfer.speed, for: transfer.id)
        }
        for transfer in activeUploads {
            appendSample(transfer.speed, for: transfer.id)
        }
    }

    private func appendSample(_ value: Int64, for id: UUID) {
        var samples = speedHistory[id] ?? []
        samples.append(value)
        if samples.count > Self.speedHistoryLimit {
            samples.removeFirst(samples.count - Self.speedHistoryLimit)
        }
        speedHistory[id] = samples
    }
}
