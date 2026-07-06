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

    /// Cached — allocating a DateFormatter per call is expensive and this
    /// runs on every history-row render.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var formattedDate: String {
        Self.dateFormatter.string(from: timestamp)
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
        didSet {
            guard !skipDownloadIndexRebuild else { return }
            rebuildDownloadIndex()
            refreshDownloadsInProgressCount()
        }
    }
    var uploads: [Transfer] = []

    /// Set briefly by `updateTransfer` when a mutation can't change the
    /// index (status/username/filename unchanged), so per-chunk progress
    /// writes skip the full O(n) rebuild. Wholesale assignments
    /// (load/remove/clear) leave this false and rebuild as before.
    @ObservationIgnored private var skipDownloadIndexRebuild = false

    // MARK: - Download Status Index (O(1) lookup)
    private(set) var downloadStatusIndex: [String: Transfer.TransferStatus] = [:]

    /// Per-`(user, filename)` lookup used by `DownloadManager`'s salvage path
    /// (peer sent a TransferRequest for a download we haven't lifted into
    /// `pendingDownloads` yet). Holds only entries whose status is still
    /// eligible for salvage: `.queued`, `.waiting`, `.connecting`. Rebuilt
    /// alongside `downloadStatusIndex` so it tracks live downloads — completed
    /// and failed entries fall out automatically.
    private(set) var salvageableDownloadIDs: [String: UUID] = [:]

    private func rebuildDownloadIndex() {
        var statusIndex: [String: Transfer.TransferStatus] = [:]
        var salvageIndex: [String: UUID] = [:]
        statusIndex.reserveCapacity(downloads.count)
        for transfer in downloads {
            let key = "\(transfer.username)\0\(transfer.filename)"
            statusIndex[key] = transfer.status
            switch transfer.status {
            case .queued, .waiting, .connecting:
                salvageIndex[key] = transfer.id
            default:
                break
            }
        }
        downloadStatusIndex = statusIndex
        salvageableDownloadIDs = salvageIndex
    }

    /// Count of downloads that are queued, waiting, connecting, or actively
    /// transferring. Surfaced to the sidebar badge.
    ///
    /// Stored (not computed) so observers subscribe only to this `Int`, not
    /// to `downloads` itself — mutating `downloads[i].bytesTransferred` on
    /// every progress update would otherwise fan-out observable
    /// invalidation to the sidebar. The setter guard below only writes
    /// when the value actually changes, so progress updates (which call
    /// `downloads.didSet` but leave the count identical) are free.
    private(set) var downloadsInProgressCount: Int = 0

    private func refreshDownloadsInProgressCount() {
        var count = 0
        for transfer in downloads {
            if transfer.isActive || transfer.status == .queued || transfer.status == .waiting {
                count += 1
            }
        }
        if count != downloadsInProgressCount {
            downloadsInProgressCount = count
        }
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
    /// Per-transfer sparkline ring buffer. Kept off the @Observable surface
    /// because it's written by the 1Hz speed timer for every active
    /// transfer — each tick rewrote the whole dict, which invalidated
    /// every SwiftUI view that read `speedHistory[id]` on the parent
    /// (TransfersView passed the slice into every row), causing the entire
    /// transfer list to re-render once per second. Sparklines now poll
    /// via `speedHistory(for:)` inside a 1Hz TimelineView so only the
    /// sparkline itself refreshes, not the row or the list.
    @ObservationIgnored private var speedHistoryStore: [UUID: [Int64]] = [:]
    private static let speedHistoryLimit = 30

    /// Non-observable accessor for the sparkline history. Reads from
    /// `speedHistoryStore` so the caller registers no dependency on
    /// @Observable state — the view drives its own refresh cadence
    /// (typically a TimelineView).
    func speedHistory(for id: UUID) -> [Int64] {
        speedHistoryStore[id] ?? []
    }

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

    // MARK: - Debounced persistence
    /// `updateTransfer` fires per received chunk; writing a row per call
    /// queued unbounded Tasks behind the DB writer. Instead, dirty ids are
    /// coalesced and flushed at most once per second, reading the current
    /// row state at flush time. Status transitions flush promptly; pure
    /// progress (bytes/speed/queuePosition/nextRetryAt) waits for the tick.
    @ObservationIgnored private var dirtyTransferIDs: Set<UUID> = []
    /// Dirty ids whose non-progress fields changed; flushed via full save.
    @ObservationIgnored private var fullSaveTransferIDs: Set<UUID> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var flushInFlight = false

    private func markDirty(_ id: UUID, progressOnly: Bool, urgent: Bool) {
        dirtyTransferIDs.insert(id)
        if !progressOnly { fullSaveTransferIDs.insert(id) }
        if urgent {
            flushDirtyTransfers()
        } else {
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushDirtyTransfers()
        }
    }

    private func flushDirtyTransfers() {
        guard !dirtyTransferIDs.isEmpty, !flushInFlight else { return }
        let ids = dirtyTransferIDs
        let fullIDs = fullSaveTransferIDs
        dirtyTransferIDs.removeAll()
        fullSaveTransferIDs.removeAll()

        // Snapshot current rows; ids removed in the meantime drop out here.
        var fullRows: [Transfer] = []
        var progressRows: [Transfer] = []
        for id in ids {
            guard let transfer = getTransfer(id: id) else { continue }
            if fullIDs.contains(id) {
                fullRows.append(transfer)
            } else {
                progressRows.append(transfer)
            }
        }
        guard !fullRows.isEmpty || !progressRows.isEmpty else { return }

        flushInFlight = true
        Task {
            for transfer in fullRows {
                do {
                    try await TransferRepository.save(transfer)
                } catch {
                    logger.error("Failed to persist transfer: \(error.localizedDescription)")
                }
            }
            for transfer in progressRows {
                try? await TransferRepository.updateProgress(
                    id: transfer.id,
                    bytesTransferred: transfer.bytesTransferred,
                    speed: transfer.speed
                )
            }
            flushInFlight = false
            // Re-arm if new updates landed while writing.
            if !dirtyTransferIDs.isEmpty { scheduleFlush() }
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

    func findSalvageableDownload(username: String, filename: String) -> Transfer? {
        guard let id = salvageableDownloadIDs["\(username)\0\(filename)"] else { return nil }
        return downloads.first(where: { $0.id == id })
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

    /// True when `before` → `after` only changed bytesTransferred/speed.
    /// (username/filename are `let`, so they can never change here.)
    private func isProgressOnlyChange(_ before: Transfer, _ after: Transfer) -> Bool {
        var probe = before
        probe.bytesTransferred = after.bytesTransferred
        probe.speed = after.speed
        return probe == after
    }

    func updateTransfer(id: UUID, update: (inout Transfer) -> Void) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let before = downloads[index]
            var transfer = before
            update(&transfer)
            let statusChanged = before.status != transfer.status

            if statusChanged {
                downloads[index] = transfer
            } else {
                // Status (the only indexed mutable field) is unchanged:
                // write the row back without the O(n) index rebuild.
                skipDownloadIndexRebuild = true
                downloads[index] = transfer
                skipDownloadIndexRebuild = false
            }

            // Record completion if status changed to completed
            if before.status != .completed && transfer.status == .completed {
                recordCompletion(transfer)
            }
            markDirty(id, progressOnly: isProgressOnlyChange(before, transfer), urgent: statusChanged)
        } else if let index = uploads.firstIndex(where: { $0.id == id }) {
            let before = uploads[index]
            var transfer = before
            update(&transfer)

            // Record completion if status changed to completed
            if before.status != .completed && transfer.status == .completed {
                recordCompletion(transfer)
            }
            uploads[index] = transfer
            markDirty(
                id,
                progressOnly: isProgressOnlyChange(before, transfer),
                urgent: before.status != transfer.status
            )
        }
    }

    /// Invoked when a user-visible action takes a transfer out of a
    /// retriable state (cancel, remove, manual retry). Set by AppState to
    /// `downloadManager.cancelRetry(transferId:)` so any `pendingRetries`
    /// Task that was sleeping for the next backoff tick is dropped
    /// immediately instead of waking up to 30 min later and finding it
    /// has no work to do. The status-guard inside the Task already makes
    /// the no-op safe; this just stops the wasted sleep.
    var onDownloadTerminated: ((UUID) -> Void)?

    /// Invoked when the user cancels (or removes) a transfer that may have
    /// live network activity. Set by AppState to the managers' cancel APIs
    /// so the actual streaming/queue work stops — flipping the row status
    /// alone leaves the bytes flowing. The Bool is `isDownload`, so AppState
    /// can route to the right manager. Deliberately NOT fired by
    /// retryTransfer, which also fires onDownloadTerminated but wants the
    /// transfer re-driven, not torn down.
    var onCancelRequested: ((UUID, Bool) -> Void)?

    func cancelTransfer(id: UUID) {
        let isDownload = downloads.contains { $0.id == id }
        updateTransfer(id: id) { transfer in
            transfer.status = .cancelled
        }
        onCancelRequested?(id, isDownload)
        onDownloadTerminated?(id)
    }

    func retryTransfer(id: UUID) {
        updateTransfer(id: id) { transfer in
            transfer.status = .queued
            transfer.bytesTransferred = 0
            transfer.error = nil
        }
        // The scheduled retry (if any) is now stale — the transfer is
        // about to be re-driven through startDownload.
        onDownloadTerminated?(id)
    }

    func removeTransfer(id: UUID) {
        // Direction must be captured BEFORE removal for the cancel routing.
        let isDownload = downloads.contains { $0.id == id }
        downloads.removeAll { $0.id == id }
        uploads.removeAll { $0.id == id }
        speedHistoryStore.removeValue(forKey: id)
        reconcilePeerWatches()
        // Removing an in-flight transfer must also stop its network work.
        onCancelRequested?(id, isDownload)
        onDownloadTerminated?(id)

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
        for id in removedIds { speedHistoryStore.removeValue(forKey: id) }
        reconcilePeerWatches()
        // Completed transfers can't have a pending retry Task, so skip
        // the onDownloadTerminated fan-out here.

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
        for id in removedIds { speedHistoryStore.removeValue(forKey: id) }
        reconcilePeerWatches()
        for id in removedIds { onDownloadTerminated?(id) }

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
        // Only write on change so idle ticks don't invalidate observers.
        let downloadSpeed = activeDownloads.reduce(0) { $0 + $1.speed }
        let uploadSpeed = activeUploads.reduce(0) { $0 + $1.speed }
        if downloadSpeed != totalDownloadSpeed { totalDownloadSpeed = downloadSpeed }
        if uploadSpeed != totalUploadSpeed { totalUploadSpeed = uploadSpeed }
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
        var samples = speedHistoryStore[id] ?? []
        samples.append(value)
        if samples.count > Self.speedHistoryLimit {
            samples.removeFirst(samples.count - Self.speedHistoryLimit)
        }
        speedHistoryStore[id] = samples
    }
}
