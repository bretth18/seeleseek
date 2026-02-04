import Foundation
import os

/// Manages the download queue and file transfers
@Observable
@MainActor
final class DownloadManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "DownloadManager")

    // MARK: - Dependencies
    private weak var networkClient: NetworkClient?
    private weak var transferState: TransferState?

    // MARK: - Pending Downloads
    // Maps token to pending download info
    private var pendingDownloads: [UInt32: PendingDownload] = [:]

    struct PendingDownload {
        let transferId: UUID
        let username: String
        let filename: String
        let size: UInt64
        var peerConnection: PeerConnection?
    }

    // MARK: - Initialization

    func configure(networkClient: NetworkClient, transferState: TransferState) {
        self.networkClient = networkClient
        self.transferState = transferState

        // Set up callbacks for peer address responses
        networkClient.onPeerAddress = { [weak self] username, ip, port in
            Task { @MainActor in
                await self?.handlePeerAddress(username: username, ip: ip, port: port)
            }
        }
    }

    // MARK: - Download API

    /// Queue a file for download
    func queueDownload(from result: SearchResult) {
        guard let transferState else {
            logger.error("TransferState not configured")
            return
        }

        let transfer = Transfer(
            username: result.username,
            filename: result.filename,
            size: result.size,
            direction: .download,
            status: .queued
        )

        transferState.addDownload(transfer)
        logger.info("Queued download: \(result.filename) from \(result.username)")

        // Start the download process
        Task {
            await startDownload(transfer: transfer)
        }
    }

    // MARK: - Download Flow

    private func startDownload(transfer: Transfer) async {
        guard let networkClient, let transferState else { return }

        let token = UInt32.random(in: 0...UInt32.max)

        // Update status to connecting
        transferState.updateTransfer(id: transfer.id) { t in
            t.status = .connecting
        }

        // Store pending download
        pendingDownloads[token] = PendingDownload(
            transferId: transfer.id,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size
        )

        logger.info("Starting download from \(transfer.username), token=\(token)")

        do {
            // Step 1: Get peer address
            try await networkClient.getUserAddress(transfer.username)

            // Wait for peer address callback (handled in handlePeerAddress)
            // Set a timeout
            try await Task.sleep(for: .seconds(30))

            // If we're still here and not connected, mark as failed
            if let pending = pendingDownloads[token], pending.peerConnection == nil {
                transferState.updateTransfer(id: transfer.id) { t in
                    t.status = .failed
                    t.error = "Connection timeout"
                }
                pendingDownloads.removeValue(forKey: token)
            }
        } catch {
            logger.error("Download failed: \(error.localizedDescription)")
            transferState.updateTransfer(id: transfer.id) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingDownloads.removeValue(forKey: token)
        }
    }

    private func handlePeerAddress(username: String, ip: String, port: Int) async {
        guard let networkClient, let transferState else { return }

        // Find pending download for this user
        guard let (token, pending) = pendingDownloads.first(where: { $0.value.username == username }) else {
            logger.debug("No pending download for \(username)")
            return
        }

        logger.info("Got peer address for \(username): \(ip):\(port)")

        // Try to connect to peer
        do {
            let connection = try await networkClient.peerConnectionPool.connect(
                to: username,
                ip: ip,
                port: port,
                token: token
            )

            // Connected! Send queue download request
            pendingDownloads[token]?.peerConnection = connection

            try await connection.queueDownload(filename: pending.filename)
            logger.info("Sent QueueDownload for \(pending.filename)")

            // Wait for transfer response
            await waitForTransferResponse(token: token, connection: connection)

        } catch {
            logger.warning("Direct connection failed: \(error.localizedDescription)")

            // Update transfer status
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .connecting
                t.error = "Trying indirect connection..."
            }

            // Send CantConnectToPeer to request indirect connection
            await networkClient.sendCantConnectToPeer(token: token, username: username)

            // Wait for indirect connection via ConnectToPeer
            // This is handled by the peer connection pool's incoming connections
            logger.info("Waiting for indirect connection to \(username)")
        }
    }

    private func waitForTransferResponse(token: UInt32, connection: PeerConnection) async {
        guard let transferState, let pending = pendingDownloads[token] else { return }

        // Set up callback for transfer request
        await connection.setOnTransferRequest { [weak self] request in
            guard let self else { return }
            await self.handleTransferRequest(token: token, request: request)
        }

        // Wait for the transfer to complete or timeout
        do {
            try await Task.sleep(for: .seconds(60))

            // Still waiting - mark as queued on remote
            if pendingDownloads[token] != nil {
                await MainActor.run {
                    transferState.updateTransfer(id: pending.transferId) { t in
                        t.status = .waiting
                    }
                }
            }
        } catch {
            // Task was cancelled or other error
        }
    }

    private func handleTransferRequest(token: UInt32, request: TransferRequest) async {
        guard let transferState, let pending = pendingDownloads[token] else { return }

        let directionStr = request.direction == .upload ? "upload" : "download"
        logger.info("Transfer request received: direction=\(directionStr) size=\(request.size)")

        if request.direction == .upload {
            // Peer is ready to upload to us
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .transferring
                t.startTime = Date()
            }

            // Start the actual file transfer
            await startFileTransfer(token: token, request: request)
        }
    }

    private func startFileTransfer(token: UInt32, request: TransferRequest) async {
        guard let transferState, let pending = pendingDownloads[token] else { return }

        logger.info("Starting file transfer for \(request.filename)")

        // TODO: Implement actual file transfer
        // 1. Establish file transfer connection (type 'F')
        // 2. Send/receive file data
        // 3. Write to disk
        // 4. Update progress

        // For now, mark as failed with a message
        transferState.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "File transfer not yet implemented"
        }

        pendingDownloads.removeValue(forKey: token)
    }

    // MARK: - Incoming Connection Handling

    /// Called when we receive an indirect connection from a peer
    func handleIncomingConnection(username: String, token: UInt32, connection: PeerConnection) async {
        guard let pending = pendingDownloads[token] else {
            // Not a download we're waiting for
            return
        }

        logger.info("Indirect connection established with \(username) for token \(token)")

        pendingDownloads[token]?.peerConnection = connection

        // Send queue download request
        do {
            try await connection.queueDownload(filename: pending.filename)
            logger.info("Sent QueueDownload via indirect connection")

            await waitForTransferResponse(token: token, connection: connection)
        } catch {
            logger.error("Failed to queue download: \(error.localizedDescription)")
        }
    }
}
