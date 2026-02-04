import SwiftUI
import Combine

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

    // MARK: - Actions

    func getTransfer(id: UUID) -> Transfer? {
        if let transfer = downloads.first(where: { $0.id == id }) {
            return transfer
        }
        return uploads.first(where: { $0.id == id })
    }

    func addDownload(_ transfer: Transfer) {
        downloads.insert(transfer, at: 0)
    }

    func addUpload(_ transfer: Transfer) {
        uploads.insert(transfer, at: 0)
    }

    func updateTransfer(id: UUID, update: (inout Transfer) -> Void) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            update(&downloads[index])
        } else if let index = uploads.firstIndex(where: { $0.id == id }) {
            update(&uploads[index])
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
    }

    func clearCompleted() {
        downloads.removeAll { $0.status == .completed }
        uploads.removeAll { $0.status == .completed }
    }

    func clearFailed() {
        downloads.removeAll { $0.status == .failed || $0.status == .cancelled }
        uploads.removeAll { $0.status == .failed || $0.status == .cancelled }
    }

    func updateSpeeds() {
        totalDownloadSpeed = activeDownloads.reduce(0) { $0 + $1.speed }
        totalUploadSpeed = activeUploads.reduce(0) { $0 + $1.speed }
    }
}
