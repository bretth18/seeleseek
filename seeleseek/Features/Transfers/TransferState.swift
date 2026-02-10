import SwiftUI
import Combine
import os

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
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "alac", "wma", "ape"]
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
        ByteFormatter.format(size)
    }

    var formattedSpeed: String {
        ByteFormatter.formatSpeed(Int64(averageSpeed))
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

@Observable
@MainActor
final class TransferState {
    // MARK: - Transfers
    var downloads: [Transfer] = []
    var uploads: [Transfer] = []

    // MARK: - History
    var history: [TransferHistoryItem] = []

    // MARK: - Stats
    var totalDownloadSpeed: Int64 = 0
    var totalUploadSpeed: Int64 = 0
    var totalDownloaded: Int64 = 0
    var totalUploaded: Int64 = 0

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
        downloads.first {
            $0.filename == filename && $0.username == username
        }?.status
    }

    /// Check if any file with this exact path exists in downloads (any state except completed/cancelled)
    func isFileQueued(filename: String, username: String) -> Bool {
        downloads.contains {
            $0.filename == filename &&
            $0.username == username &&
            $0.status != .completed &&
            $0.status != .cancelled
        }
    }

    func addDownload(_ transfer: Transfer) {
        downloads.insert(transfer, at: 0)
        persistTransfer(transfer)
    }

    func addUpload(_ transfer: Transfer) {
        uploads.insert(transfer, at: 0)
        persistTransfer(transfer)
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

        // Remove from database
        Task {
            try? await TransferRepository.delete(id: id)
        }
    }

    func clearCompleted() {
        downloads.removeAll { $0.status == .completed }
        uploads.removeAll { $0.status == .completed }

        // Clear from database
        Task {
            try? await TransferRepository.deleteCompleted()
        }
    }

    func clearFailed() {
        downloads.removeAll { $0.status == .failed || $0.status == .cancelled }
        uploads.removeAll { $0.status == .failed || $0.status == .cancelled }

        // Clear from database
        Task {
            try? await TransferRepository.deleteFailed()
        }
    }

    func updateSpeeds() {
        totalDownloadSpeed = activeDownloads.reduce(0) { $0 + $1.speed }
        totalUploadSpeed = activeUploads.reduce(0) { $0 + $1.speed }
    }
}
