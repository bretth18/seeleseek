import SwiftUI
import Combine
import os

@Observable
@MainActor
final class TransferState {
    // MARK: - Transfers
    var downloads: [Transfer] = []
    var uploads: [Transfer] = []

    // MARK: - Stats
    var totalDownloadSpeed: Int64 = 0
    var totalUploadSpeed: Int64 = 0

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
            let resumable = try await TransferRepository.fetchResumable()
            downloads = resumable.filter { $0.direction == .download }
            uploads = resumable.filter { $0.direction == .upload }
            logger.info("Loaded \(self.downloads.count) downloads and \(self.uploads.count) uploads from database")
        } catch {
            logger.error("Failed to load persisted transfers: \(error.localizedDescription)")
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
