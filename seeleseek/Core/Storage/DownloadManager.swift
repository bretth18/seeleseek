import Foundation
import Network
import os


/// Manages the download queue and file transfers
@Observable
@MainActor
final class DownloadManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "DownloadManager")

    // MARK: - Dependencies
    private weak var networkClient: NetworkClient?
    private weak var transferState: TransferState?
    private weak var statisticsState: StatisticsState?
    private weak var uploadManager: UploadManager?
    private weak var settings: SettingsState?

    // MARK: - Pending Downloads
    // Maps token to pending download info
    private var pendingDownloads: [UInt32: PendingDownload] = [:]

    // Maps username to pending file transfers (waiting for F connection)
    // Array-based to support multiple concurrent downloads from same user
    private var pendingFileTransfersByUser: [String: [PendingFileTransfer]] = [:]

    // MARK: - Post-Download Processing
    private let metadataReader = MetadataReader()
    /// Directories that already have folder icons applied (avoid redundant work)
    private var iconAppliedDirs: Set<URL> = []

    // MARK: - Retry Configuration (nicotine+ style)
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 5  // Start with 5 seconds
    private var pendingRetries: [UUID: Task<Void, Never>] = [:]  // Track retry tasks
    private var reQueueTimer: Task<Void, Never>?  // Periodic re-queue timer (60s)
    private var connectionRetryTimer: Task<Void, Never>?  // Retry failed connections (3 min)
    private var queuePositionTimer: Task<Void, Never>?  // Update queue positions (5 min)
    private var staleRecoveryTimer: Task<Void, Never>?  // Recover stale downloads (15 min)

    struct PendingDownload {
        let transferId: UUID
        let username: String
        let filename: String
        var size: UInt64
        var peerConnection: PeerConnection?
        var peerIP: String?       // Store peer IP for outgoing F connection
        var peerPort: Int?        // Store peer port for outgoing F connection
        var resumeOffset: UInt64 = 0  // For resuming partial downloads
    }

    // Track partial downloads for resume
    private var partialDownloads: [String: URL] = [:]  // filename -> partial file path

    // MARK: - Pending Indirect Connection State (for racing direct vs PierceFirewall)
    private struct PendingIndirectState {
        let username: String
        var receivedConnection: PeerConnection?
        var failed = false  // Set by CantConnectToPeer
    }
    private var pendingIndirectStates: [UInt32: PendingIndirectState] = [:]

    struct PendingFileTransfer {
        let transferId: UUID
        let username: String
        let filename: String
        let size: UInt64
        let downloadToken: UInt32   // The original download token
        let transferToken: UInt32   // The token from TransferRequest - sent on F connection
        let offset: UInt64          // File offset (usually 0 for new downloads)
    }

    // MARK: - Errors

    enum DownloadError: Error, LocalizedError {
        case noPeerConnection
        case invalidPort
        case connectionCancelled
        case connectionClosed
        case cannotCreateFile
        case timeout
        case incompleteTransfer(expected: UInt64, actual: UInt64)
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .noPeerConnection: return "No peer connection available"
            case .invalidPort: return "Invalid port number"
            case .connectionCancelled: return "Connection was cancelled"
            case .connectionClosed: return "Connection closed unexpectedly"
            case .cannotCreateFile: return "Cannot create download file"
            case .timeout: return "Connection timed out"
            case .incompleteTransfer(let expected, let actual):
                return "Incomplete transfer: received \(actual) of \(expected) bytes"
            case .verificationFailed: return "File verification failed"
            }
        }
    }

    // MARK: - Initialization

    func configure(networkClient: NetworkClient, transferState: TransferState, statisticsState: StatisticsState, uploadManager: UploadManager, settings: SettingsState) {
        self.networkClient = networkClient
        self.transferState = transferState
        self.statisticsState = statisticsState
        self.uploadManager = uploadManager
        self.settings = settings

        // Set up callbacks for peer address responses using multi-listener pattern
        logger.info("Adding peer address handler")
        networkClient.addPeerAddressHandler { [weak self] username, ip, port in
            self?.logger.debug("Peer address handler called: \(username) @ \(ip):\(port)")
            Task { @MainActor in
                await self?.handlePeerAddress(username: username, ip: ip, port: port)
            }
        }

        // Set up callback for incoming connections that match pending downloads
        networkClient.onIncomingConnectionMatched = { [weak self] username, token, connection in
            guard let self else { return }
            Task { @MainActor in
                await self.handleIncomingConnection(username: username, token: token, connection: connection)
            }
        }

        // Set up callback for incoming file transfer connections
        networkClient.onFileTransferConnection = { [weak self] username, token, connection in
            self?.logger.debug("File transfer connection callback invoked: username='\(username)' token=\(token)")
            guard let self else {
                return
            }
            Task { @MainActor in
                await self.handleFileTransferConnection(username: username, token: token, connection: connection)
            }
        }

        // Set up callback for PierceFirewall (indirect connections)
        networkClient.onPierceFirewall = { [weak self] token, connection in
            guard let self else { return }
            Task { @MainActor in
                await self.handlePierceFirewall(token: token, connection: connection)
            }
        }

        // Set up callback for upload denied
        networkClient.onUploadDenied = { [weak self] filename, reason in
            Task { @MainActor in
                self?.handleUploadDenied(filename: filename, reason: reason)
            }
        }

        // Set up callback for upload failed
        networkClient.onUploadFailed = { [weak self] filename in
            Task { @MainActor in
                self?.handleUploadFailed(filename: filename)
            }
        }

        // Set up callback for PlaceInQueueReply (peer tells us our queue position)
        networkClient.onPlaceInQueueReply = { [weak self] username, filename, position in
            Task { @MainActor in
                self?.handlePlaceInQueueReply(username: username, filename: filename, position: position)
            }
        }

        // Set up callback for CantConnectToPeer (fast-fail instead of waiting for timeout)
        networkClient.onCantConnectToPeer = { [weak self] token in
            Task { @MainActor in
                self?.handleCantConnectToPeer(token: token)
            }
        }

        // Start periodic timers (nicotine+ style)
        startReQueueTimer()           // Re-sends QueueDownload every 60s
        startConnectionRetryTimer()   // Retries failed connections every 3 min
        startQueuePositionTimer()     // Updates queue positions every 5 min
        startStaleRecoveryTimer()     // Recovers stale downloads every 15 min
    }

    // MARK: - Download API

    /// Resume all retriable downloads on connect (queued, waiting, and failed-but-retriable)
    func resumeDownloadsOnConnect() {
        guard let transferState else {
            logger.error("TransferState not configured for resume")
            return
        }

        // Gather downloads that should be resumed
        let queuedDownloads = transferState.downloads.filter {
            $0.status == .queued || $0.status == .waiting || $0.status == .connecting
        }

        // Also gather failed downloads with retriable errors
        let retriableFailedDownloads = transferState.downloads.filter {
            $0.status == .failed && $0.direction == .download &&
            isRetriableError($0.error ?? "")
        }

        let allToResume = queuedDownloads + retriableFailedDownloads

        guard !allToResume.isEmpty else {
            logger.info("No downloads to resume on connect")
            return
        }

        logger.info("Resuming \(allToResume.count) downloads on connect (\(queuedDownloads.count) queued, \(retriableFailedDownloads.count) retrying failed)")

        // Reset failed downloads back to queued
        for transfer in retriableFailedDownloads {
            transferState.updateTransfer(id: transfer.id) { t in
                t.status = .queued
                t.error = nil
                t.retryCount = 0
            }
        }

        // Stagger download starts to avoid connection storms
        for (index, transfer) in allToResume.enumerated() {
            let delay = Double(index) * 0.5  // 500ms between each
            Task {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                }
                await startDownload(transfer: transfer)
            }
        }
    }

    /// Queue a file for download
    func queueDownload(from result: SearchResult) {
        // Skip macOS resource fork files (._xxx in __MACOSX folders)
        // These are metadata files that usually don't exist as real files
        if isMacOSResourceFork(result.filename) {
            logger.info("Skipping macOS resource fork file: \(result.filename)")
            return
        }


        guard let transferState else {
            logger.error("TransferState not configured")
            return
        }

        guard networkClient != nil else {
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

    /// Start download with existing transfer ID (used for retries after UploadFailed)
    private func startDownload(transferId: UUID, username: String, filename: String, size: UInt64) async {
        guard let transfer = transferState?.getTransfer(id: transferId) else {
            logger.error("Transfer not found for ID \(transferId)")
            return
        }
        await startDownload(transfer: transfer)
    }

    private func startDownload(transfer: Transfer) async {
        logger.info("Starting download: \(transfer.filename) from \(transfer.username)")

        guard let networkClient, let transferState else {
            logger.error("NetworkClient or TransferState is nil")
            return
        }

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
            size: transfer.size,
            peerIP: nil,
            peerPort: nil
        )

        logger.info("Starting download from \(transfer.username), token=\(token)")

        do {
            // Step 1: Get peer address
            logger.debug("Requesting peer address for \(transfer.username)")
            try await networkClient.getUserAddress(transfer.username)

            // Poll every 500ms for up to 30s, checking if connection was established
            // handlePeerAddress() will set peerConnection or remove the pending entry
            var elapsed: TimeInterval = 0
            let timeoutSeconds: TimeInterval = 30
            while elapsed < timeoutSeconds {
                try await Task.sleep(for: .milliseconds(500))
                elapsed += 0.5
                // Connection established by handlePeerAddress
                if pendingDownloads[token]?.peerConnection != nil { return }
                // Already handled (removed from pending by handlePeerAddress or other handler)
                if pendingDownloads[token] == nil { return }
            }

            // Timed out - mark as failed and schedule retry
            if pendingDownloads[token] != nil {
                let errorMsg = "Connection timeout"
                let currentRetryCount = transferState.getTransfer(id: transfer.id)?.retryCount ?? 0

                transferState.updateTransfer(id: transfer.id) { t in
                    t.status = .failed
                    t.error = errorMsg
                }
                pendingDownloads.removeValue(forKey: token)

                // Auto-retry for connection timeouts
                if currentRetryCount < maxRetries {
                    scheduleRetry(
                        transferId: transfer.id,
                        username: transfer.username,
                        filename: transfer.filename,
                        size: transfer.size,
                        retryCount: currentRetryCount
                    )
                }
            }
        } catch {
            logger.error("Download failed: \(error.localizedDescription)")
            let currentRetryCount = transferState.getTransfer(id: transfer.id)?.retryCount ?? 0

            transferState.updateTransfer(id: transfer.id) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingDownloads.removeValue(forKey: token)

            // Auto-retry for retriable errors
            if isRetriableError(error.localizedDescription) && currentRetryCount < maxRetries {
                scheduleRetry(
                    transferId: transfer.id,
                    username: transfer.username,
                    filename: transfer.filename,
                    size: transfer.size,
                    retryCount: currentRetryCount
                )
            }
        }
    }

    private func handlePeerAddress(username: String, ip: String, port: Int) async {
        guard let networkClient, let transferState else {
            logger.error("handlePeerAddress: NetworkClient or TransferState is nil")
            return
        }

        // Find ALL pending downloads for this user (not just first)
        let matchingEntries = pendingDownloads.filter { $0.value.username == username }
        guard !matchingEntries.isEmpty else {
            logger.debug("No pending download for \(username)")
            return
        }

        // Use first entry as the "primary" for connection establishment
        let (token, pending) = matchingEntries.first!
        let additionalEntries = matchingEntries.filter { $0.key != token }

        logger.info("Peer address for \(username): \(ip):\(port), token=\(token) (\(matchingEntries.count) pending downloads)")

        // Store peer address for all pending downloads
        for (t, _) in matchingEntries {
            pendingDownloads[t]?.peerIP = ip
            pendingDownloads[t]?.peerPort = port
        }

        // First, check if we already have a connection to this user (from incoming connections)
        if let existingConnection = await networkClient.peerConnectionPool.getConnectionForUser(username) {
            logger.info("Reusing existing connection to \(username)")
            pendingDownloads[token]?.peerConnection = existingConnection

            do {
                await setupTransferRequestCallback(token: token, connection: existingConnection)
                try await existingConnection.queueDownload(filename: pending.filename)
                try? await existingConnection.sendPlaceInQueueRequest(filename: pending.filename)
                logger.info("Sent QueueDownload for \(pending.filename)")

                // Also queue additional downloads on the same connection
                for (extraToken, extraPending) in additionalEntries {
                    pendingDownloads[extraToken]?.peerConnection = existingConnection
                    await setupTransferRequestCallback(token: extraToken, connection: existingConnection)
                    try? await existingConnection.queueDownload(filename: extraPending.filename)
                    try? await existingConnection.sendPlaceInQueueRequest(filename: extraPending.filename)
                    logger.info("Sent QueueDownload for additional: \(extraPending.filename)")
                }

                await waitForTransferResponse(token: token)
            } catch {
                logger.error("Failed to queue download on existing connection: \(error.localizedDescription)")
                transferState.updateTransfer(id: pending.transferId) { t in
                    t.status = .failed
                    t.error = error.localizedDescription
                }
                pendingDownloads.removeValue(forKey: token)
            }
            return
        }

        // CRITICAL: Register pending indirect BEFORE sending ConnectToPeer to avoid race condition
        // PierceFirewall can arrive immediately after ConnectToPeer is sent!
        registerPendingIndirect(token: token, username: username, timeout: 30)

        // Send ConnectToPeer to server - starts indirect path in parallel
        // Server will tell the peer to connect to us via PierceFirewall
        await networkClient.sendConnectToPeer(token: token, username: username, connectionType: "P")
        logger.info("Sent ConnectToPeer for \(username), racing direct vs indirect...")

        // Race: direct connection + handshake (10s) vs indirect (PierceFirewall)
        var connection: PeerConnection
        var isIndirect = false

        do {
            connection = try await withThrowingTaskGroup(of: PeerConnection.self) { group in
                group.addTask {
                    let conn = try await networkClient.peerConnectionPool.connect(
                        to: username, ip: ip, port: port, token: token
                    )
                    // Must also complete handshake - peer may not respond if they
                    // already connected to us via PierceFirewall
                    try await conn.waitForPeerHandshake(timeout: .seconds(8))
                    return conn
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw NetworkError.timeout
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            cancelPendingIndirect(token: token)
            logger.info("Direct connection + handshake to \(username) succeeded")
        } catch {
            // Direct timed out or failed - wait for indirect (PierceFirewall) connection
            logger.info("Direct connection failed (\(error.localizedDescription)), waiting for indirect...")
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .connecting
                t.error = "Trying indirect connection..."
            }

            do {
                connection = try await waitForPendingIndirect(token: token)
                isIndirect = true
                logger.info("Got indirect connection from \(username)")
            } catch {
                // Both paths failed - fail all pending downloads for this user
                logger.error("Both direct and indirect connections to \(username) failed")
                let isSameNetwork = networkClient.externalIP == ip
                let errorMsg = isSameNetwork
                    ? "Same network - hairpin NAT limitation"
                    : "Connection timeout - peer unreachable"

                for (failToken, failPending) in matchingEntries {
                    let currentRetryCount = transferState.getTransfer(id: failPending.transferId)?.retryCount ?? 0
                    transferState.updateTransfer(id: failPending.transferId) { t in
                        t.status = .failed
                        t.error = errorMsg
                    }
                    pendingDownloads.removeValue(forKey: failToken)

                    if !isSameNetwork && currentRetryCount < maxRetries {
                        scheduleRetry(
                            transferId: failPending.transferId,
                            username: failPending.username,
                            filename: failPending.filename,
                            size: failPending.size,
                            retryCount: currentRetryCount
                        )
                    }
                }
                return
            }
        }

        if isIndirect {
            // Resume receive loop - PierceFirewall stops it assuming file transfer mode,
            // but P connections need to continue receiving peer messages
            await connection.resumeReceivingForPeerConnection()
        }

        // Got a connection - send QueueDownload for all pending downloads
        pendingDownloads[token]?.peerConnection = connection

        do {
            if isIndirect {
                // For indirect connections, identify ourselves to the peer
                try await connection.sendPeerInit(username: networkClient.username)
                logger.debug("Sent PeerInit via indirect connection")
            }

            await setupTransferRequestCallback(token: token, connection: connection)
            try await connection.queueDownload(filename: pending.filename)
            try? await connection.sendPlaceInQueueRequest(filename: pending.filename)
            logger.info("Sent QueueDownload for \(pending.filename)")

            // Also queue additional downloads on the same connection
            for (extraToken, extraPending) in additionalEntries {
                pendingDownloads[extraToken]?.peerConnection = connection
                await setupTransferRequestCallback(token: extraToken, connection: connection)
                try? await connection.queueDownload(filename: extraPending.filename)
                try? await connection.sendPlaceInQueueRequest(filename: extraPending.filename)
                logger.info("Sent QueueDownload for additional: \(extraPending.filename)")
            }

            await waitForTransferResponse(token: token)
        } catch {
            logger.error("Failed to queue download: \(error.localizedDescription)")
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingDownloads.removeValue(forKey: token)
        }
    }

    // MARK: - Pending Indirect Connection Helpers

    /// Register a pending indirect download BEFORE sending ConnectToPeer (to avoid race condition)
    private func registerPendingIndirect(token: UInt32, username: String, timeout: TimeInterval) {
        pendingIndirectStates[token] = PendingIndirectState(username: username)
    }

    /// Wait for PierceFirewall to arrive for a previously registered token (polling-based, no continuation leak)
    private func waitForPendingIndirect(token: UInt32, timeout: TimeInterval = 30) async throws -> PeerConnection {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let state = pendingIndirectStates[token] {
                if let connection = state.receivedConnection {
                    pendingIndirectStates.removeValue(forKey: token)
                    return connection
                }
                if state.failed {
                    pendingIndirectStates.removeValue(forKey: token)
                    throw NetworkError.connectionFailed("Peer unreachable")
                }
            } else {
                // State was removed (cancelled)
                throw NetworkError.timeout
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        // Timed out
        pendingIndirectStates.removeValue(forKey: token)
        throw NetworkError.timeout
    }

    /// Cancel a pending indirect download (used when direct connection succeeds)
    private func cancelPendingIndirect(token: UInt32) {
        pendingIndirectStates.removeValue(forKey: token)
    }

    /// Called when PierceFirewall arrives - check if it matches a racing download
    /// Returns true if it was handled
    private func handlePierceFirewallForRace(token: UInt32, connection: PeerConnection) -> Bool {
        guard let state = pendingIndirectStates[token] else {
            return false
        }

        logger.info("PierceFirewall token=\(token) matched racing download for \(state.username)")

        Task {
            await connection.setPeerUsername(state.username)
        }

        pendingIndirectStates[token]?.receivedConnection = connection
        return true
    }

    /// Set up callback for TransferRequest - must be called BEFORE sending QueueDownload
    /// Uses filename-based matching to handle multiple concurrent downloads on same connection
    private func setupTransferRequestCallback(token: UInt32, connection: PeerConnection) async {
        // Use a central callback that matches by filename instead of capturing a specific token
        // This fixes the issue where multiple downloads on the same connection would overwrite callbacks
        await connection.setOnTransferRequest { [weak self] request in
            guard let self else { return }
            // Find pending download by filename match
            await self.handleTransferRequestByFilename(request: request, fallbackToken: token)
        }
        logger.debug("TransferRequest callback set up (filename-based matching, fallback token=\(token))")
    }

    /// Handle TransferRequest by matching filename to pending downloads
    /// This supports multiple concurrent downloads on the same connection
    private func handleTransferRequestByFilename(request: TransferRequest, fallbackToken: UInt32) async {
        // Try to find matching pending download by filename
        let matchingEntry = pendingDownloads.first { (_, pending) in
            pending.filename == request.filename
        }

        if let (token, _) = matchingEntry {
            logger.debug("Matched TransferRequest to pending download by filename: \(request.filename)")
            await handleTransferRequest(token: token, request: request)
        } else {
            // Fall back to the original token if no filename match
            logger.debug("No filename match for TransferRequest, using fallback token=\(fallbackToken)")
            await handleTransferRequest(token: fallbackToken, request: request)
        }
    }

    private func waitForTransferResponse(token: UInt32) async {
        guard let transferState, let pending = pendingDownloads[token] else { return }

        // Wait for the transfer to complete or timeout
        do {
            try await Task.sleep(for: .seconds(60))

            // Still waiting - only mark as waiting if still in .connecting status
            // Don't overwrite .transferring or other statuses
            if pendingDownloads[token] != nil {
                await MainActor.run {
                    if let currentTransfer = transferState.getTransfer(id: pending.transferId),
                       currentTransfer.status == .connecting {
                        transferState.updateTransfer(id: pending.transferId) { t in
                            t.status = .waiting
                        }
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
        logger.info("Transfer request received: direction=\(directionStr) size=\(request.size) from \(request.username)")

        if request.direction == .upload {
            // Peer is ready to upload to us - send acceptance reply
            if let connection = pending.peerConnection {
                do {
                    try await connection.sendTransferReply(token: request.token, allowed: true)
                    logger.info("Sent transfer reply accepting upload for token \(request.token)")
                } catch {
                    logger.error("Failed to send transfer reply: \(error.localizedDescription)")
                    transferState.updateTransfer(id: pending.transferId) { t in
                        t.status = .failed
                        t.error = "Failed to accept transfer"
                    }
                    pendingDownloads.removeValue(forKey: token)
                    return
                }
            }

            // Register pending file transfer - peer will connect to us with type "F"
            // Key by username because PeerInit on F connections always has token=0
            // Use pending.username (from original search result) not request.username (might be empty for reused connections)
            // Store the transfer token from TransferRequest - we'll send this on the F connection

            // Check for partial file to enable resume
            let destPath = computeDestPath(for: pending.filename, username: pending.username)
            var resumeOffset: UInt64 = 0
            if FileManager.default.fileExists(atPath: destPath.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: destPath.path),
                   let existingSize = attrs[.size] as? UInt64,
                   existingSize > 0 && existingSize < request.size {
                    resumeOffset = existingSize
                    logger.info("Found partial file \(destPath.lastPathComponent), \(existingSize)/\(request.size) bytes, resuming from offset \(resumeOffset)")
                }
            }

            let pendingTransfer = PendingFileTransfer(
                transferId: pending.transferId,
                username: pending.username,
                filename: pending.filename,
                size: request.size,
                downloadToken: token,
                transferToken: request.token,  // This is sent on F connection handshake
                offset: resumeOffset           // Resume from partial file if exists
            )
            pendingFileTransfersByUser[pending.username, default: []].append(pendingTransfer)
            logger.info("Registered pending file transfer for \(pending.username): transferToken=\(request.token)")

            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .transferring
                t.startTime = Date()
            }

            // Wait for the file connection - peer may connect to us, or we connect to them
            // Store context for outgoing connection attempt
            let peerIP = pending.peerIP
            let peerPort = pending.peerPort
            let transferToken = request.token
            let fileSize = request.size
            let peerUsername = pending.username

            Task {
                // Wait 5 seconds for peer to connect to us
                try? await Task.sleep(for: .seconds(5))

                // If still pending, try connecting to them instead (NAT traversal fallback)
                if self.hasPendingFileTransfer(username: peerUsername, transferToken: transferToken) {
                    await self.initiateOutgoingFileConnection(
                        username: peerUsername,
                        ip: peerIP,
                        port: peerPort,
                        transferToken: transferToken,
                        fileSize: fileSize,
                        downloadToken: token
                    )
                }

                // Wait another 55 seconds for either connection type
                try? await Task.sleep(for: .seconds(55))

                // If still pending after total 60 seconds, mark as failed
                if self.removePendingFileTransfer(username: peerUsername, transferToken: transferToken) != nil {
                    pendingDownloads.removeValue(forKey: token)
                    await MainActor.run {
                        transferState.updateTransfer(id: pending.transferId) { t in
                            t.status = .failed
                            t.error = "File connection timeout"
                        }
                    }
                }
            }
        }
    }

    private func startFileTransfer(token: UInt32, request: TransferRequest) async {
        guard let _ = networkClient, let transferState, let pending = pendingDownloads[token] else { return }

        logger.info("Starting file transfer for \(request.filename) (\(request.size) bytes)")

        // Compute destination path preserving folder structure
        let destPath = computeDestPath(for: pending.filename, username: pending.username)
        let filename = destPath.lastPathComponent

        logger.info("Downloading to: \(destPath.path)")

        do {
            // Create file connection to peer
            // Get peer address from the request
            guard let peerConnection = pending.peerConnection else {
                throw DownloadError.noPeerConnection
            }

            let peerInfo = peerConnection.peerInfo
            logger.info("Creating file connection to \(peerInfo.ip):\(peerInfo.port)")

            // Create a file transfer connection
            let fileConnection = try await createFileConnection(
                ip: peerInfo.ip,
                port: peerInfo.port,
                token: request.token
            )

            // Receive the file data
            try await receiveFileData(
                connection: fileConnection,
                destPath: destPath,
                expectedSize: request.size,
                transferId: pending.transferId
            )

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = request.size
                t.localPath = destPath
                t.error = nil
            }

            logger.info("Download complete: \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)
            applyFolderArtworkIfNeeded(for: destPath)

        } catch {
            logger.error("File transfer failed: \(error.localizedDescription)")
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
        }

        pendingDownloads.removeValue(forKey: token)
    }

    // MARK: - Outgoing File Connection (NAT traversal fallback)

    /// Initiate an outgoing F connection to the peer (when they can't connect to us)
    private func initiateOutgoingFileConnection(
        username: String,
        ip: String?,
        port: Int?,
        transferToken: UInt32,
        fileSize: UInt64,
        downloadToken: UInt32
    ) async {
        guard let ip, let port, port > 0 else {
            logger.warning("Cannot initiate outgoing F connection to \(username): missing address")
            return
        }

        guard let transferState else { return }

        // Check if still pending
        guard hasPendingFileTransfer(username: username, transferToken: transferToken) else {
            logger.debug("Outgoing F connection not needed - transfer no longer pending")
            return
        }
        guard let pending = removePendingFileTransfer(username: username, transferToken: transferToken) else {
            return
        }

        logger.info("Initiating outgoing F connection to \(username) at \(ip):\(port)")

        do {
            // Create TCP connection
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                throw DownloadError.invalidPort
            }

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: nwPort
            )

            let params = NWParameters.tcp
            let connection = NWConnection(to: endpoint, using: params)

            // Wait for connection
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        continuation.resume()
                    case .failed(let error):
                        continuation.resume(throwing: error)
                    case .cancelled:
                        continuation.resume(throwing: DownloadError.connectionCancelled)
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }

            logger.info("Outgoing F connection established to \(username)")

            // Send PierceFirewall with the transfer token
            // This tells the uploader which pending upload this connection is for
            let pierceMessage = MessageBuilder.pierceFirewallMessage(token: transferToken)
            try await sendData(connection: connection, data: pierceMessage)
            logger.debug("Sent PierceFirewall token=\(transferToken) to \(username)")

            // Capture offset (pending already removed above)
            let resumeOffset = pending.offset

            // Per SoulSeek/nicotine+ protocol on F connections:
            // 1. UPLOADER sends FileTransferInit (token - 4 bytes)
            // 2. DOWNLOADER sends FileOffset (offset - 8 bytes)
            // But when WE (downloader) initiate the connection, we need to wait for uploader's token first

            // Wait for FileTransferInit from uploader (token - 4 bytes)
            logger.debug("Waiting for FileTransferInit from uploader")
            let tokenData = try await receiveData(connection: connection, length: 4)
            let receivedToken = tokenData.readUInt32(at: 0) ?? 0
            logger.debug("Received FileTransferInit: token=\(receivedToken) (expected=\(transferToken))")

            // Send FileOffset (offset - 8 bytes)
            var offsetData = Data()
            offsetData.appendUInt64(resumeOffset)
            logger.debug("Sending FileOffset: offset=\(resumeOffset)")
            try await sendData(connection: connection, data: offsetData)

            logger.debug("Handshake complete, receiving file data")

            // Compute destination path preserving folder structure
            let destPath = computeDestPath(for: pending.filename, username: username)
            let filename = destPath.lastPathComponent

            // Receive file data
            try await receiveFileData(
                connection: connection,
                destPath: destPath,
                expectedSize: fileSize,
                transferId: pending.transferId,
                resumeOffset: resumeOffset
            )

            // Calculate transfer duration
            let duration = Date().timeIntervalSince(transferState.getTransfer(id: pending.transferId)?.startTime ?? Date())

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = fileSize
                t.localPath = destPath
                t.error = nil
            }

            logger.info("Download complete (outgoing F): \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)
            applyFolderArtworkIfNeeded(for: destPath)

            // Record in statistics
            statisticsState?.recordTransfer(
                filename: filename,
                username: username,
                size: fileSize,
                duration: duration,
                isDownload: true
            )

            // Clean up
            pendingDownloads.removeValue(forKey: downloadToken)

        } catch {
            logger.error("Outgoing F connection failed: \(error.localizedDescription)")
            // Don't mark as failed yet - the timeout will handle that
        }
    }

    // MARK: - File Transfer Connection

    private func createFileConnection(ip: String, port: Int, token: UInt32) async throws -> NWConnection {
        // Validate port
        guard port > 0, port <= Int(UInt16.max), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw DownloadError.invalidPort
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: nwPort
        )

        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        // Wait for connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: DownloadError.connectionCancelled)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        logger.info("File connection established to \(ip):\(port)")

        // Send the token to identify this transfer
        var tokenData = Data()
        tokenData.appendUInt32(token)
        try await sendData(connection: connection, data: tokenData)

        logger.info("Sent transfer token: \(token)")

        return connection
    }

    private func sendData(connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveData(connection: NWConnection, length: Int, timeout: TimeInterval = 30) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let data, data.count >= length {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: DownloadError.connectionClosed)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw DownloadError.timeout
            }

            guard let result = try await group.next() else {
                throw DownloadError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private func receiveFileData(connection: NWConnection, destPath: URL, expectedSize: UInt64, transferId: UUID, resumeOffset: UInt64 = 0) async throws {
        // SECURITY: Check for symlink attacks before creating any files
        let baseDir = getDownloadDirectory()
        guard isPathSafe(destPath, within: baseDir) else {
            logger.error("SECURITY: Symlink attack detected for path \(destPath.path)")
            throw DownloadError.cannotCreateFile
        }

        // Ensure parent directory exists
        let parentDir = destPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create parent directory \(parentDir.path): \(error)")
            throw DownloadError.cannotCreateFile
        }

        let fileHandle: FileHandle

        if resumeOffset > 0 && FileManager.default.fileExists(atPath: destPath.path) {
            // Resume mode - append to existing file
            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open file handle for resume at \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            try handle.seekToEnd()
            fileHandle = handle
        } else {
            // Create file for writing
            let created = FileManager.default.createFile(atPath: destPath.path, contents: nil)
            if !created {
                logger.error("Failed to create file at \(destPath.path)")
            }

            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open file handle for \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            fileHandle = handle
        }

        var bytesReceived: UInt64 = resumeOffset
        let startTime = Date()

        logger.info("Receiving file data, expected size: \(expectedSize) bytes")

        // Receive data in chunks
        while bytesReceived < expectedSize {
            let (chunk, isComplete) = try await receiveChunkWithStatus(connection: connection)

            if chunk.isEmpty && isComplete {
                // Connection closed with no more data
                break
            } else if chunk.isEmpty {
                // No data but connection still open
                continue
            }

            try fileHandle.write(contentsOf: chunk)
            bytesReceived += UInt64(chunk.count)

            // Update progress
            let elapsed = Date().timeIntervalSince(startTime)
            let speed = elapsed > 0 ? Int64(Double(bytesReceived) / elapsed) : 0

            await MainActor.run { [transferState] in
                transferState?.updateTransfer(id: transferId) { t in
                    t.bytesTransferred = bytesReceived
                    t.speed = speed
                }
            }

            // If this was the final chunk, exit loop
            if isComplete {
                break
            }
        }

        // Flush data to disk before verifying
        try fileHandle.synchronize()
        try fileHandle.close()

        // Verify file integrity
        let attrs = try FileManager.default.attributesOfItem(atPath: destPath.path)
        let actualSize = attrs[.size] as? UInt64 ?? 0

        logger.info("File verification: expected=\(expectedSize), received=\(bytesReceived), disk=\(actualSize)")
        // If expected size is 0, something went wrong with TransferRequest parsing
        if expectedSize == 0 {
            logger.error("Expected size is 0 - TransferRequest parsing likely failed")
        }

        // Allow small discrepancy (up to 0.1% or 1KB, whichever is larger)
        let tolerance = max(1024, expectedSize / 1000)
        let sizeDiff = actualSize > expectedSize ? actualSize - expectedSize : expectedSize - actualSize


        if expectedSize > 0 && sizeDiff > tolerance {
            logger.error("File size mismatch: expected \(expectedSize), got \(actualSize) (diff: \(sizeDiff))")
            throw DownloadError.incompleteTransfer(expected: expectedSize, actual: actualSize)
        }

        if actualSize != expectedSize && expectedSize > 0 {
            logger.warning("Minor size discrepancy: expected \(expectedSize), got \(actualSize) (diff: \(sizeDiff) bytes) - accepting")
        }

        connection.cancel()
        logger.info("File transfer complete and verified: \(actualSize) bytes received")
    }

    private func receiveChunkWithStatus(connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            // Use 1MB buffer for better throughput on file transfers
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: (data, isComplete))
                } else if isComplete {
                    continuation.resume(returning: (Data(), true))
                } else {
                    continuation.resume(returning: (Data(), false))
                }
            }
        }
    }

    // MARK: - Helpers

    private func getDownloadDirectory() -> URL {
        let paths = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        let downloadsDir = paths[0].appendingPathComponent("SeeleSeek")

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            logger.debug("Download directory: \(downloadsDir.path)")
        } catch {
            logger.error("Failed to create download directory: \(downloadsDir.path) - \(error)")
            // Fall back to app's document directory
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let fallbackDir = appSupport.appendingPathComponent("SeeleSeek/Downloads")
                try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
                logger.info("Using fallback directory: \(fallbackDir.path)")
                return fallbackDir
            }
        }

        return downloadsDir
    }

    /// Compute destination path preserving folder structure from SoulSeek path
    /// e.g., "@@music\Artist\Album\01 Song.mp3" -> "Downloads/SeeleSeek/Artist/Album/01 Song.mp3"
    private func computeDestPath(for soulseekPath: String, username: String) -> URL {
        let downloadDir = getDownloadDirectory()

        // Parse the SoulSeek path (uses backslash separators)
        var pathComponents = soulseekPath.split(separator: "\\").map(String.init)

        // Remove the root share marker (e.g., "@@music", "@@downloads")
        if !pathComponents.isEmpty && pathComponents[0].hasPrefix("@@") {
            pathComponents.removeFirst()
        }

        // Need at least a filename
        guard !pathComponents.isEmpty else {
            let fallbackName = (soulseekPath as NSString).lastPathComponent
            return downloadDir.appendingPathComponent(fallbackName.isEmpty ? "unknown" : fallbackName)
        }

        // Extract filename (last component) and folders (everything else)
        let filename = pathComponents.last!
        let folders = pathComponents.dropLast().joined(separator: "/")

        // Get the active template
        let template = settings?.activeDownloadTemplate ?? "{username}/{folders}/{filename}"

        // Substitute tokens
        var result = template
            .replacingOccurrences(of: "{username}", with: username)
            .replacingOccurrences(of: "{folders}", with: folders)
            .replacingOccurrences(of: "{filename}", with: filename)

        // Clean up double slashes from empty tokens (e.g. empty folders)
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        // Trim leading/trailing slashes
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Split into components, sanitize each, and build the URL
        let resultComponents = result.split(separator: "/").map(String.init)
        var destURL = downloadDir
        for component in resultComponents {
            destURL = destURL.appendingPathComponent(sanitizeFilename(component))
        }

        return destURL
    }

    /// Sanitize a filename/folder name for the filesystem
    /// Prevents directory traversal attacks and invalid filesystem characters
    private func sanitizeFilename(_ name: String) -> String {
        // SECURITY: Prevent directory traversal attacks
        // Reject ".." and "." components that could escape the download directory
        if name == ".." || name == "." {
            return "unnamed"
        }

        // Remove/replace characters that are invalid in macOS filenames
        var sanitized = name
        let invalidChars: [Character] = [":", "/", "\\", "\0"]
        for char in invalidChars {
            sanitized = sanitized.replacingOccurrences(of: String(char), with: "_")
        }

        // SECURITY: Remove any embedded ".." sequences (e.g., "foo..bar" is fine, but "foo/../bar" is not)
        // After replacing slashes above, this catches edge cases
        while sanitized.contains("..") {
            sanitized = sanitized.replacingOccurrences(of: "..", with: "_")
        }

        // Remove ~ which could reference home directory in some contexts
        sanitized = sanitized.replacingOccurrences(of: "~", with: "_")

        // Trim whitespace and dots from ends
        sanitized = sanitized.trimmingCharacters(in: .whitespaces)
        if sanitized.hasPrefix(".") {
            sanitized = "_" + sanitized.dropFirst()
        }
        return sanitized.isEmpty ? "unnamed" : sanitized
    }

    /// SECURITY: Check if a path contains any symlinks that could be used for symlink attacks
    /// Returns true if the path is safe (no symlinks), false if symlinks are detected
    private func isPathSafe(_ url: URL, within baseDir: URL) -> Bool {
        let fileManager = FileManager.default

        // Standardize paths (remove . and ..) without following symlinks
        // This is important because app container paths may resolve differently
        let standardizedPath = url.standardized.path
        let standardizedBasePath = baseDir.standardized.path

        // First check: Ensure the standardized path is within the base directory
        // This catches directory traversal attacks (../) without symlink resolution issues
        guard standardizedPath.hasPrefix(standardizedBasePath) else {
            logger.warning("SECURITY: Path \(url.path) is outside base directory")
            return false
        }

        // Second check: Ensure no path component is ".." (extra safety)
        let relativeComponents = url.pathComponents.dropFirst(baseDir.pathComponents.count)
        for component in relativeComponents {
            if component == ".." {
                logger.warning("SECURITY: Directory traversal attempt detected in \(url.path)")
                return false
            }
        }

        // Third check: Look for symlinks in the USER-CREATED portions of the path only
        // (Don't check base directory itself - it's system-controlled)
        var currentPath = baseDir
        for component in relativeComponents {
            currentPath = currentPath.appendingPathComponent(component)

            // Only check if the path exists
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: currentPath.path, isDirectory: &isDirectory) {
                // Check if it's a symbolic link
                if let attributes = try? fileManager.attributesOfItem(atPath: currentPath.path),
                   let fileType = attributes[.type] as? FileAttributeType,
                   fileType == .typeSymbolicLink {
                    logger.warning("SECURITY: Symlink detected at \(currentPath.path)")
                    return false
                }
            }
        }

        return true
    }

    /// Check if a filename is a macOS resource fork file (._xxx in __MACOSX folders)
    /// These are metadata files from zip extraction that usually don't exist as real files
    private func isMacOSResourceFork(_ filename: String) -> Bool {
        let lowercased = filename.lowercased()

        // Check for __MACOSX folder in path
        if lowercased.contains("__macosx") {
            return true
        }

        // Check for ._ prefix on filename (resource fork)
        let components = filename.split(separator: "\\")
        if let lastComponent = components.last, lastComponent.hasPrefix("._") {
            return true
        }

        // Check for .DS_Store
        if lowercased.hasSuffix(".ds_store") || lowercased.hasSuffix("\\.ds_store") {
            return true
        }

        return false
    }

    // MARK: - Post-Download Processing

    /// Apply album artwork as the Finder folder icon for the directory containing the downloaded file.
    /// Runs off-main-thread via MetadataReader actor. Fire-and-forget.
    private func applyFolderArtworkIfNeeded(for filePath: URL) {
        guard settings?.setFolderIcons == true else { return }

        let directory = filePath.deletingLastPathComponent()

        // Skip if we've already set an icon for this directory in this session
        guard !iconAppliedDirs.contains(directory) else { return }
        iconAppliedDirs.insert(directory)

        Task.detached { [metadataReader, logger] in
            let applied = await metadataReader.applyArtworkAsFolderIcon(for: directory)
            if applied {
                logger.info("Applied album art as folder icon for \(directory.lastPathComponent)")
            }
        }
    }

    // MARK: - Incoming Connection Handling

    /// Called when we receive an indirect connection from a peer
    func handleIncomingConnection(username: String, token: UInt32, connection: PeerConnection) async {
        guard let pending = pendingDownloads[token] else {
            // Not a download we're waiting for
            return
        }

        guard let networkClient else {
            logger.error("NetworkClient is nil in handleIncomingConnection")
            return
        }

        logger.info("Indirect connection established with \(username) for token \(token)")

        pendingDownloads[token]?.peerConnection = connection

        // Send PeerInit + QueueDownload
        // Per protocol: We need to send PeerInit to identify ourselves before QueueUpload
        do {
            // Send PeerInit FIRST - identifies us to the peer (token=0 for P connections)
            try await connection.sendPeerInit(username: networkClient.username)
            logger.debug("Sent PeerInit via indirect connection")

            // Set up callback BEFORE sending QueueDownload to avoid race condition
            await setupTransferRequestCallback(token: token, connection: connection)

            try await connection.queueDownload(filename: pending.filename)
            try? await connection.sendPlaceInQueueRequest(filename: pending.filename)
            logger.info("Sent QueueDownload via indirect connection")

            await waitForTransferResponse(token: token)
        } catch {
            logger.error("Failed to queue download: \(error.localizedDescription)")
        }
    }

    /// Called when a peer opens a file transfer connection to us (type "F")
    /// Per SoulSeek protocol: After PeerInit, uploader sends FileTransferInit token (4 bytes)
    func handleFileTransferConnection(username: String, token: UInt32, connection: PeerConnection) async {
        guard transferState != nil else {
            logger.error("TransferState not configured")
            return
        }

        // Find pending entries for this user (try exact then case-insensitive)
        let entries = findPendingFileTransfers(for: username)
        guard !entries.isEmpty else {
            logger.warning("No pending file transfer for username \(username)")
            return
        }

        if entries.count == 1 {
            // Single entry - use it directly (most common case)
            let pending = entries[0]
            _ = removePendingFileTransfer(username: username, transferToken: pending.transferToken)
            await handleFileTransferWithPending(pending, connection: connection)
        } else {
            // Multiple entries for same user - receive FileTransferInit token first to match
            await handleFileTransferWithTokenMatch(entries: entries, username: username, connection: connection)
        }
    }

    // MARK: - Pending File Transfer Helpers (array-based)

    /// Check if a pending file transfer exists for a given username and token
    private func hasPendingFileTransfer(username: String, transferToken: UInt32) -> Bool {
        let entries = findPendingFileTransfers(for: username)
        return entries.contains { $0.transferToken == transferToken }
    }

    /// Find all pending file transfers for a username (exact or case-insensitive)
    private func findPendingFileTransfers(for username: String) -> [PendingFileTransfer] {
        if let entries = pendingFileTransfersByUser[username], !entries.isEmpty {
            return entries
        }
        // Case-insensitive fallback
        let lower = username.lowercased()
        for (key, entries) in pendingFileTransfersByUser {
            if key.lowercased() == lower, !entries.isEmpty {
                return entries
            }
        }
        return []
    }

    /// Remove and return a specific pending file transfer by username and token
    @discardableResult
    private func removePendingFileTransfer(username: String, transferToken: UInt32) -> PendingFileTransfer? {
        // Try exact match first
        let key = pendingFileTransfersByUser[username] != nil ? username
            : pendingFileTransfersByUser.keys.first { $0.lowercased() == username.lowercased() }
        guard let key else { return nil }

        guard var entries = pendingFileTransfersByUser[key] else { return nil }
        guard let idx = entries.firstIndex(where: { $0.transferToken == transferToken }) else { return nil }
        let removed = entries.remove(at: idx)
        if entries.isEmpty {
            pendingFileTransfersByUser.removeValue(forKey: key)
        } else {
            pendingFileTransfersByUser[key] = entries
        }
        return removed
    }

    /// Handle F connection when multiple transfers are pending for same user.
    /// Receives FileTransferInit token first to match the right pending entry.
    private func handleFileTransferWithTokenMatch(entries: [PendingFileTransfer], username: String, connection: PeerConnection) async {
        do {
            await connection.stopReceiving()
            try await Task.sleep(for: .milliseconds(50))

            // Receive FileTransferInit token to identify which transfer this is for
            var tokenData: Data
            let bufferedData = await connection.getFileTransferBuffer()
            if bufferedData.count >= 4 {
                tokenData = Data(bufferedData.prefix(4))
                if bufferedData.count > 4 {
                    await connection.prependToFileTransferBuffer(Data(bufferedData.dropFirst(4)))
                }
            } else if bufferedData.count > 0 {
                let remaining = try await connection.receiveRawBytes(count: 4 - bufferedData.count, timeout: 30)
                tokenData = bufferedData + remaining
            } else {
                tokenData = try await connection.receiveRawBytes(count: 4, timeout: 30)
            }

            let receivedToken = tokenData.readUInt32(at: 0) ?? 0
            logger.info("F connection: received FileTransferInit token=\(receivedToken), matching against \(entries.count) pending entries")

            // Match by token
            if let pending = removePendingFileTransfer(username: username, transferToken: receivedToken) {
                // Send FileOffset and proceed
                var offsetData = Data()
                offsetData.appendUInt64(pending.offset)
                try await connection.sendRaw(offsetData)

                let destPath = computeDestPath(for: pending.filename, username: pending.username)
                try await receiveFileDataFromPeer(
                    connection: connection,
                    destPath: destPath,
                    expectedSize: pending.size,
                    transferId: pending.transferId,
                    resumeOffset: pending.offset
                )

                let duration = Date().timeIntervalSince(transferState?.getTransfer(id: pending.transferId)?.startTime ?? Date())
                transferState?.updateTransfer(id: pending.transferId) { t in
                    t.status = .completed
                    t.bytesTransferred = pending.size
                    t.localPath = destPath
                    t.error = nil
                }
                ActivityLog.shared.logDownloadCompleted(filename: destPath.lastPathComponent)
                applyFolderArtworkIfNeeded(for: destPath)
                statisticsState?.recordTransfer(
                    filename: destPath.lastPathComponent,
                    username: pending.username,
                    size: pending.size,
                    duration: duration,
                    isDownload: true
                )
            } else {
                // Token didn't match any pending - try first entry as fallback
                logger.warning("Token \(receivedToken) didn't match any pending transfer for \(username)")
                if let fallback = entries.first {
                    _ = removePendingFileTransfer(username: username, transferToken: fallback.transferToken)
                    // Put token back into buffer so handleFileTransferWithPending can read it
                    await connection.prependToFileTransferBuffer(tokenData)
                    await handleFileTransferWithPending(fallback, connection: connection)
                }
            }
        } catch {
            logger.error("Failed token-match F connection: \(error.localizedDescription)")
        }
    }

    /// Common handler for file transfer with a pending transfer record
    private func handleFileTransferWithPending(_ pending: PendingFileTransfer, connection: PeerConnection) async {
        guard let transferState else {
            logger.error("TransferState not configured in handleFileTransferWithPending")
            return
        }

        logger.info("File transfer connection, sending transferToken=\(pending.transferToken) offset=\(pending.offset)")

        // Compute destination path preserving folder structure
        let destPath = computeDestPath(for: pending.filename, username: pending.username)
        let filename = destPath.lastPathComponent

        logger.info("Receiving file to: \(destPath.path)")

        do {
            // Note: receive loop is already stopped in PeerConnection.handleInitMessage when F connection detected
            // This call is now just a safety no-op (stopReceiving is idempotent)
            await connection.stopReceiving()

            // Small delay to let any in-flight network data arrive
            try await Task.sleep(for: .milliseconds(50))

            // Per SoulSeek/nicotine+ protocol on F connections:
            // 1. UPLOADER sends FileTransferInit (token - 4 bytes)
            // 2. DOWNLOADER sends FileOffset (offset - 8 bytes)
            // 3. UPLOADER sends raw file data
            // See: https://nicotine-plus.org/doc/SLSKPROTOCOL.md step 8-9

            // Step 1: Receive FileTransferInit from uploader (token - 4 bytes)
            // Check if data was already received by the message loop before we stopped it
            var tokenData: Data
            let bufferedData = await connection.getFileTransferBuffer()
            if bufferedData.count >= 4 {
                logger.debug("Using \(bufferedData.count) bytes from file transfer buffer")
                tokenData = bufferedData.prefix(4)
                // Put remaining data back (if any) for file data
                if bufferedData.count > 4 {
                    await connection.prependToFileTransferBuffer(Data(bufferedData.dropFirst(4)))
                }
            } else {
                logger.debug("Waiting for FileTransferInit from uploader")
                if bufferedData.count > 0 {
                    // Have partial data, need more
                    let remaining = try await connection.receiveRawBytes(count: 4 - bufferedData.count, timeout: 30)
                    tokenData = bufferedData + remaining
                } else {
                    tokenData = try await connection.receiveRawBytes(count: 4, timeout: 30)
                }
            }

            let receivedToken = tokenData.readUInt32(at: 0) ?? 0
            logger.debug("Received FileTransferInit: token=\(receivedToken) (expected=\(pending.transferToken))")

            if receivedToken != pending.transferToken {
                logger.warning("Token mismatch: received \(receivedToken) but expected \(pending.transferToken)")
            }

            // Step 2: Send FileOffset (offset - 8 bytes)
            var offsetData = Data()
            offsetData.appendUInt64(pending.offset)
            logger.debug("Sending FileOffset: offset=\(pending.offset)")
            try await connection.sendRaw(offsetData)

            logger.debug("Handshake complete, receiving file data")

            // Receive file data using the PeerConnection
            try await receiveFileDataFromPeer(
                connection: connection,
                destPath: destPath,
                expectedSize: pending.size,
                transferId: pending.transferId,
                resumeOffset: pending.offset
            )

            // Calculate transfer duration
            let duration = Date().timeIntervalSince(transferState.getTransfer(id: pending.transferId)?.startTime ?? Date())

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = pending.size
                t.localPath = destPath
                t.error = nil
            }

            logger.info("Download complete: \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)
            applyFolderArtworkIfNeeded(for: destPath)

            logger.debug("Recording download stats: \(filename), size=\(pending.size), duration=\(duration)")
            if let stats = statisticsState {
                stats.recordTransfer(
                    filename: filename,
                    username: pending.username,
                    size: pending.size,
                    duration: duration,
                    isDownload: true
                )
                logger.debug("Stats recorded: downloads=\(stats.filesDownloaded), total=\(stats.totalDownloaded)")
            } else {
                logger.warning("statisticsState is nil")
            }

            // Clean up the original download tracking
            pendingDownloads.removeValue(forKey: pending.downloadToken)

        } catch {
            logger.error("File transfer failed: \(error.localizedDescription)")

            let errorMsg = error.localizedDescription
            let currentRetryCount = transferState.getTransfer(id: pending.transferId)?.retryCount ?? 0

            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = errorMsg
            }
            pendingDownloads.removeValue(forKey: pending.downloadToken)

            // Auto-retry for retriable errors (nicotine+ style)
            if isRetriableError(errorMsg) && currentRetryCount < maxRetries {
                scheduleRetry(
                    transferId: pending.transferId,
                    username: pending.username,
                    filename: pending.filename,
                    size: pending.size,
                    retryCount: currentRetryCount
                )
            }
        }
    }

    /// Receive file data from a PeerConnection
    private func receiveFileDataFromPeer(
        connection: PeerConnection,
        destPath: URL,
        expectedSize: UInt64,
        transferId: UUID,
        resumeOffset: UInt64 = 0
    ) async throws {
        // SECURITY: Check for symlink attacks before creating any files
        let baseDir = getDownloadDirectory()
        guard isPathSafe(destPath, within: baseDir) else {
            logger.error("SECURITY: Symlink attack detected for path \(destPath.path)")
            throw DownloadError.cannotCreateFile
        }

        // Ensure parent directory exists
        let parentDir = destPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create parent directory \(parentDir.path): \(error)")
            throw DownloadError.cannotCreateFile
        }

        let fileHandle: FileHandle

        if resumeOffset > 0 && FileManager.default.fileExists(atPath: destPath.path) {
            // Resume mode - open existing file and seek to end
            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open existing file for resume: \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            try handle.seekToEnd()
            fileHandle = handle
            logger.info("Resume mode: Appending to \(destPath.lastPathComponent) from offset \(resumeOffset)")
        } else {
            // Normal mode - create new file
            let created = FileManager.default.createFile(atPath: destPath.path, contents: nil)
            if !created && !FileManager.default.fileExists(atPath: destPath.path) {
                logger.error("Failed to create file at \(destPath.path)")
            }

            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open file handle for \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            fileHandle = handle
        }

        var bytesReceived: UInt64 = resumeOffset  // Start from resume offset if resuming
        let startTime = Date()

        logger.info("Receiving file data from peer, expected size: \(expectedSize) bytes")
        logger.info("Start receive: \(destPath.lastPathComponent), expected=\(expectedSize) bytes")

        // First, drain any data that was buffered by the receive loop before it stopped
        let bufferedFileData = await connection.getFileTransferBuffer()
        if !bufferedFileData.isEmpty {
            logger.debug("Writing \(bufferedFileData.count) bytes from file transfer buffer")
            try fileHandle.write(contentsOf: bufferedFileData)
            bytesReceived += UInt64(bufferedFileData.count)

            // Update progress
            await MainActor.run { [transferState] in
                transferState?.updateTransfer(id: transferId) { t in
                    t.bytesTransferred = bytesReceived
                }
            }
        }

        // Receive data in chunks - like nicotine+, we receive until connection closes
        // then check if we got enough bytes
        var lastDataTime = Date()

        // Nicotine+ approach: receive until connection ACTUALLY closes, then verify byte count
        // Don't use artificial timeouts that could cut off slow transfers
        receiveLoop: while true {
            // Receive data - no artificial timeout that returns fake completion
            let chunkResult: PeerConnection.FileChunkResult
            do {
                // Use a long timeout (60s) just to prevent infinite hangs on dead connections
                // This throws an error on timeout rather than returning fake completion
                chunkResult = try await withThrowingTaskGroup(of: PeerConnection.FileChunkResult.self) { group in
                    group.addTask {
                        try await connection.receiveFileChunk()
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(60))
                        throw DownloadError.timeout
                    }
                    guard let result = try await group.next() else {
                        throw DownloadError.timeout
                    }
                    group.cancelAll()
                    return result
                }
            } catch is DownloadError {
                // Timeout - but try to drain any remaining buffered data first
                let timeSinceLastData = Date().timeIntervalSince(lastDataTime)
                logger.debug("Timeout after \(timeSinceLastData)s, attempting final buffer drain")

                // Try to drain remaining data from connection buffer
                var drainAttempts = 0
                while drainAttempts < 10 {
                    let remainingBuffer = await connection.getFileTransferBuffer()
                    if !remainingBuffer.isEmpty {
                        try fileHandle.write(contentsOf: remainingBuffer)
                        bytesReceived += UInt64(remainingBuffer.count)
                        logger.debug("Drain: +\(remainingBuffer.count) bytes, total=\(bytesReceived)")
                        drainAttempts += 1
                    } else {
                        break
                    }
                }

                logger.debug("Timeout final: \(bytesReceived)/\(expectedSize) bytes")

                // If we have all the data now, consider it complete
                if bytesReceived >= expectedSize {
                    logger.debug("Got all bytes after drain")
                    break receiveLoop
                }
                // Otherwise, this is an incomplete transfer
                break receiveLoop
            } catch {
                logger.error("Receive error: \(error.localizedDescription)")
                logger.error("Receive error: \(error.localizedDescription) at \(bytesReceived)/\(expectedSize)")
                break receiveLoop
            }

            switch chunkResult {
            case .data(let chunk), .dataWithCompletion(let chunk):
                if !chunk.isEmpty {
                    try fileHandle.write(contentsOf: chunk)
                    bytesReceived += UInt64(chunk.count)
                    lastDataTime = Date()  // Reset timeout tracker

                    // Update progress periodically (not every chunk to reduce UI overhead)
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Int64(Double(bytesReceived) / elapsed) : 0

                    await MainActor.run { [transferState] in
                        transferState?.updateTransfer(id: transferId) { t in
                            t.bytesTransferred = bytesReceived
                            t.speed = speed
                        }
                    }

                    // Log progress every 1MB
                    if bytesReceived % (1024 * 1024) < UInt64(chunk.count) {
                        let pct = expectedSize > 0 ? Double(bytesReceived) / Double(expectedSize) * 100 : 0
                        logger.debug("Progress: \(bytesReceived)/\(expectedSize) (\(String(format: "%.1f", pct))%) @ \(speed/1024)KB/s")
                    }
                }

                // CRITICAL: Like nicotine+, we're done when bytesReceived >= expectedSize
                if expectedSize > 0 && bytesReceived >= expectedSize {
                    logger.info("Received all expected bytes: \(bytesReceived)/\(expectedSize)")
                    break receiveLoop
                }

                // If this was the final chunk with completion signal, fall through to drain logic
                if case .dataWithCompletion = chunkResult {
                    logger.info("Connection signaled complete with data, bytesReceived=\(bytesReceived)")
                    logger.debug("Data+complete signal: \(bytesReceived)/\(expectedSize), falling through to drain")
                    // Fall through to connectionComplete drain logic below
                } else {
                    continue receiveLoop
                }
                fallthrough

            case .connectionComplete:
                // Connection closed - but there might still be buffered data!
                // Try multiple reads to drain everything
                logger.debug("Connection signaled complete at \(bytesReceived)/\(expectedSize), draining remaining data")

                // First drain our local buffer
                let remainingBuffer = await connection.getFileTransferBuffer()
                if !remainingBuffer.isEmpty {
                    try fileHandle.write(contentsOf: remainingBuffer)
                    bytesReceived += UInt64(remainingBuffer.count)
                    logger.debug("Buffer drain: +\(remainingBuffer.count) bytes, now at \(bytesReceived)")
                }

                // Try to read more from the connection even after completion signal
                // The TCP stack might have more data buffered
                var additionalReads = 0
                let maxAdditionalReads = 30
                while bytesReceived < expectedSize && additionalReads < maxAdditionalReads {
                    additionalReads += 1

                    // Use drainAvailableData which doesn't require a minimum byte count
                    let extraChunk = await connection.drainAvailableData(maxLength: 65536, timeout: 0.3)

                    if extraChunk.isEmpty {
                        logger.debug("No more data available after \(additionalReads) drain attempts")
                        break
                    }

                    try fileHandle.write(contentsOf: extraChunk)
                    bytesReceived += UInt64(extraChunk.count)
                    logger.debug("Drain \(additionalReads): +\(extraChunk.count) bytes, now at \(bytesReceived)/\(expectedSize)")
                }

                logger.info("Connection closed by peer, final bytesReceived=\(bytesReceived)")
                logger.debug("Connection closed: \(bytesReceived)/\(expectedSize)")
                break receiveLoop
            }
        }

        // Drain any final buffer
        let finalBuffer = await connection.getFileTransferBuffer()
        if !finalBuffer.isEmpty {
            try fileHandle.write(contentsOf: finalBuffer)
            bytesReceived += UInt64(finalBuffer.count)
        }

        // Flush data to disk before verifying
        try fileHandle.synchronize()
        try fileHandle.close()

        // Verify file integrity
        let attrs = try FileManager.default.attributesOfItem(atPath: destPath.path)
        let actualSize = attrs[.size] as? UInt64 ?? 0

        let percentComplete = expectedSize > 0 ? Double(actualSize) / Double(expectedSize) * 100 : 100
        logger.info("Verify: expected=\(expectedSize), received=\(bytesReceived), disk=\(actualSize) (\(String(format: "%.1f", percentComplete))%)")

        // Like nicotine+: require actualSize >= expectedSize
        if expectedSize > 0 && actualSize >= expectedSize {
            logger.info("Download complete: received \(actualSize) bytes (expected \(expectedSize))")
        } else if expectedSize == 0 && actualSize > 0 {
            // Expected size was 0 (parsing issue) but we got data - accept it
            logger.warning("Expected size was 0 but received \(actualSize) bytes - accepting")
        } else if actualSize < expectedSize && expectedSize > 0 {
            // Check if we're very close (99%+) - might be a metadata size mismatch
            if percentComplete >= 99.0 {
                // Accept files that are 99%+ complete - likely a slight size mismatch in peer's metadata
                logger.warning("Near-complete transfer: \(actualSize)/\(expectedSize) bytes (\(String(format: "%.2f", percentComplete))%) - accepting")
            } else {
                // Incomplete transfer - nicotine+ would fail this too
                logger.error("Incomplete transfer: \(actualSize)/\(expectedSize) bytes (\(String(format: "%.1f", percentComplete))%)")
                throw DownloadError.incompleteTransfer(expected: expectedSize, actual: actualSize)
            }
        }

        await connection.disconnect()
        logger.info("File transfer complete and verified: \(actualSize) bytes received")
    }

    // MARK: - PierceFirewall Handling (Indirect Connections)

    /// Called when a peer sends PierceFirewall - indirect connection established
    func handlePierceFirewall(token: UInt32, connection: PeerConnection) async {
        logger.debug("handlePierceFirewall: token=\(token)")

        // Check if this matches a racing download (handlePeerAddress is waiting for this)
        if handlePierceFirewallForRace(token: token, connection: connection) {
            logger.debug("PierceFirewall handled by download race")
            return
        }

        // Check if this is for a pending upload
        if let uploadManager, uploadManager.hasPendingUpload(token: token) {
            logger.debug("PierceFirewall token \(token) delegated to UploadManager")
            await uploadManager.handlePierceFirewall(token: token, connection: connection)
            return
        }

        logger.debug("No pending download/upload for PierceFirewall token \(token)")
    }

    // MARK: - CantConnectToPeer Handling

    /// Server tells us the peer couldn't connect to us — fail-fast instead of waiting for timeout
    private func handleCantConnectToPeer(token: UInt32) {
        // Check if this matches a racing download waiting for indirect connection
        if var state = pendingIndirectStates[token] {
            logger.warning("CantConnectToPeer for download token \(token) — failing indirect wait")
            state.failed = true
            pendingIndirectStates[token] = state
            return
        }

        // Check if this is for a pending upload
        if let uploadManager, uploadManager.hasPendingUpload(token: token) {
            logger.warning("CantConnectToPeer for upload token \(token) — failing upload")
            uploadManager.handleCantConnectToPeer(token: token)
            return
        }

        logger.debug("CantConnectToPeer token \(token) — no matching pending transfer")
    }

    // MARK: - Periodic Re-Queue (nicotine+ style)

    /// Periodically re-send QueueDownload for waiting/queued downloads to keep queue position alive
    private func startReQueueTimer() {
        reQueueTimer?.cancel()
        reQueueTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                await self.reQueueWaitingDownloads()
            }
        }
    }

    /// Re-send QueueDownload and PlaceInQueueRequest for waiting/queued downloads
    /// If no connection exists, re-initiate the download from scratch
    private func reQueueWaitingDownloads() async {
        guard let transferState, let networkClient else { return }

        let waitingDownloads = transferState.downloads.filter {
            $0.status == .queued || $0.status == .waiting
        }
        guard !waitingDownloads.isEmpty else { return }

        logger.info("Re-queuing \(waitingDownloads.count) waiting downloads")

        // Group by username to avoid duplicate connection attempts
        let byUser = Dictionary(grouping: waitingDownloads, by: { $0.username })

        for (username, transfers) in byUser {
            // Try to find an existing connection to this user
            if let connection = await networkClient.peerConnectionPool.getConnectionForUser(username) {
                for transfer in transfers {
                    do {
                        // Re-send QueueDownload to keep our spot in the remote queue
                        try await connection.queueDownload(filename: transfer.filename)
                        // Ask for our queue position so the UI shows it
                        try await connection.sendPlaceInQueueRequest(filename: transfer.filename)
                        logger.debug("Re-queued + requested position: \(transfer.filename)")
                    } catch {
                        logger.debug("Failed to re-queue \(transfer.filename): \(error.localizedDescription)")
                    }
                }
            } else {
                // No connection exists - re-initiate the first download from scratch
                // (handlePeerAddress will handle all downloads for this user)
                logger.info("No connection to \(username), re-initiating download")
                let transfer = transfers[0]

                // Only re-initiate if not already being handled by a pending download
                let alreadyPending = pendingDownloads.values.contains { $0.username == username }
                if !alreadyPending {
                    await startDownload(transfer: transfer)
                }
            }
        }
    }

    // MARK: - Connection Retry Timer (every 3 minutes)

    /// Retry downloads that failed due to connection issues
    private func startConnectionRetryTimer() {
        connectionRetryTimer?.cancel()
        connectionRetryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))  // 3 minutes
                guard let self, !Task.isCancelled else { return }
                await self.retryFailedConnectionDownloads()
            }
        }
    }

    /// Re-initiate downloads that failed due to connection timeouts/errors
    private func retryFailedConnectionDownloads() async {
        guard let transferState else { return }

        let failedDownloads = transferState.downloads.filter {
            $0.status == .failed && $0.direction == .download &&
            isRetriableError($0.error ?? "")
        }
        guard !failedDownloads.isEmpty else { return }

        logger.info("Connection retry: \(failedDownloads.count) failed downloads to retry")

        // Group by username and stagger
        let byUser = Dictionary(grouping: failedDownloads, by: { $0.username })
        var staggerIndex = 0
        for (username, transfers) in byUser {
            // Skip if already has a pending download for this user
            let alreadyPending = pendingDownloads.values.contains { $0.username == username }
            if alreadyPending { continue }

            let transfer = transfers[0]
            transferState.updateTransfer(id: transfer.id) { t in
                t.status = .queued
                t.error = nil
            }

            let currentDelay = Double(staggerIndex) * 1.0
            Task {
                if currentDelay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(currentDelay * 1000)))
                }
                await startDownload(transfer: transfer)
            }
            staggerIndex += 1
        }
    }

    // MARK: - Queue Position Update Timer (every 5 minutes)

    /// Periodically request queue positions for waiting downloads
    private func startQueuePositionTimer() {
        queuePositionTimer?.cancel()
        queuePositionTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))  // 5 minutes
                guard let self, !Task.isCancelled else { return }
                await self.updateQueuePositions()
            }
        }
    }

    /// Send PlaceInQueueRequest for all waiting downloads to get updated queue positions
    private func updateQueuePositions() async {
        guard let transferState, let networkClient else { return }

        let waitingDownloads = transferState.downloads.filter {
            $0.status == .waiting
        }
        guard !waitingDownloads.isEmpty else { return }

        logger.info("Updating queue positions for \(waitingDownloads.count) waiting downloads")

        for transfer in waitingDownloads {
            if let connection = await networkClient.peerConnectionPool.getConnectionForUser(transfer.username) {
                do {
                    try await connection.sendPlaceInQueueRequest(filename: transfer.filename)
                } catch {
                    logger.debug("Failed to request queue position for \(transfer.filename)")
                }
            }
        }
    }

    // MARK: - Stale Download Recovery Timer (every 15 minutes)

    /// Recover downloads stuck in waiting state for too long
    private func startStaleRecoveryTimer() {
        staleRecoveryTimer?.cancel()
        staleRecoveryTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))  // 15 minutes
                guard let self, !Task.isCancelled else { return }
                await self.recoverStaleDownloads()
            }
        }
    }

    /// Re-initiate downloads stuck in .waiting for more than 10 minutes
    private func recoverStaleDownloads() async {
        guard let transferState else { return }

        let staleThreshold = Date().addingTimeInterval(-600)  // 10 minutes ago

        let staleDownloads = transferState.downloads.filter {
            $0.status == .waiting && $0.direction == .download &&
            ($0.startTime ?? Date()) < staleThreshold
        }
        guard !staleDownloads.isEmpty else { return }

        logger.info("Recovering \(staleDownloads.count) stale waiting downloads")

        let byUser = Dictionary(grouping: staleDownloads, by: { $0.username })
        for (username, transfers) in byUser {
            let alreadyPending = pendingDownloads.values.contains { $0.username == username }
            if alreadyPending { continue }

            let transfer = transfers[0]
            transferState.updateTransfer(id: transfer.id) { t in
                t.status = .queued
                t.error = nil
            }
            await startDownload(transfer: transfer)
        }
    }

    // MARK: - Queue Position Updates

    /// Called when peer tells us our queue position for a file
    private func handlePlaceInQueueReply(username: String, filename: String, position: UInt32) {
        guard let transferState else { return }

        // Find matching download by username + filename
        if let transfer = transferState.downloads.first(where: {
            $0.username == username && $0.filename == filename &&
            ($0.status == .queued || $0.status == .waiting || $0.status == .connecting)
        }) {
            transferState.updateTransfer(id: transfer.id) { t in
                t.queuePosition = Int(position)
            }
            logger.info("Updated queue position for \(filename) from \(username): \(position)")
        }
    }

    // MARK: - Upload Denied/Failed Handling

    /// Called when peer denies our download request
    func handleUploadDenied(filename: String, reason: String) {
        logger.info("Upload denied: \(filename) - \(reason)")

        // Find pending download by filename
        guard let (token, pending) = pendingDownloads.first(where: { $0.value.filename == filename }) else {
            logger.debug("No pending download for denied file: \(filename)")
            return
        }

        logger.warning("Download denied for \(filename): \(reason)")

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "Denied: \(reason)"
        }

        pendingDownloads.removeValue(forKey: token)
    }

    /// Called when peer's upload to us fails
    func handleUploadFailed(filename: String) {
        logger.info("Upload failed: \(filename)")

        // Find pending download by filename
        guard let (token, pending) = pendingDownloads.first(where: { $0.value.filename == filename }) else {
            logger.debug("No pending download for failed file: \(filename)")
            return
        }

        // Check if we attempted a resume - if so, delete partial and retry from scratch
        let destPath = computeDestPath(for: pending.filename, username: pending.username)
        if FileManager.default.fileExists(atPath: destPath.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destPath.path),
               let existingSize = attrs[.size] as? UInt64,
               existingSize > 0 {
                // We had a partial file - the peer might not support resume
                // Delete partial and retry from scratch
                logger.warning("Upload failed after resume attempt - deleting partial file and retrying from scratch")
                try? FileManager.default.removeItem(at: destPath)

                // Mark for retry with status .queued
                transferState?.updateTransfer(id: pending.transferId) { t in
                    t.status = .queued
                    t.bytesTransferred = 0
                    t.error = nil
                }

                // Schedule automatic retry
                let transferId = pending.transferId
                let username = pending.username
                let filenameCopy = pending.filename
                let size = pending.size

                pendingDownloads.removeValue(forKey: token)

                Task {
                    try? await Task.sleep(for: .seconds(2))
                    self.logger.info("Retrying download from scratch: \(filenameCopy)")
                    await self.startDownload(transferId: transferId, username: username, filename: filenameCopy, size: size)
                }
                return
            }
        }

        logger.warning("Upload failed for \(filename)")

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "Upload failed on peer side"
        }

        pendingDownloads.removeValue(forKey: token)
    }

    // MARK: - Retry Logic (nicotine+ style)

    /// Check if an error is retriable
    private func isRetriableError(_ error: String?) -> Bool {
        guard let error = error?.lowercased() else { return false }

        // Don't retry on explicit denials or user-initiated cancels
        let nonRetriablePatterns = [
            "denied",
            "not shared",
            "cancelled",
            "not available",
            "file not found",
            "too many"
        ]

        for pattern in nonRetriablePatterns {
            if error.contains(pattern) {
                return false
            }
        }

        // Retry on connection issues
        let retriablePatterns = [
            "timeout",
            "connection",
            "network",
            "unreachable",
            "firewall",
            "incomplete"
        ]

        for pattern in retriablePatterns {
            if error.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Schedule automatic retry for a failed transfer with exponential backoff
    private func scheduleRetry(transferId: UUID, username: String, filename: String, size: UInt64, retryCount: Int) {
        guard retryCount < self.maxRetries else {
            logger.info("Max retries (\(self.maxRetries)) reached for \(filename)")
            return
        }

        // Exponential backoff: 5s, 15s, 45s
        let delay = baseRetryDelay * pow(3.0, Double(retryCount))
        logger.info("Scheduling retry #\(retryCount + 1) for \(filename) in \(delay)s")

        // Update status to show pending retry
        transferState?.updateTransfer(id: transferId) { t in
            t.error = "Retrying in \(Int(delay))s..."
        }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))

            guard let self, !Task.isCancelled else { return }

            await MainActor.run {
                self.pendingRetries.removeValue(forKey: transferId)
                self.retryDownload(transferId: transferId, username: username, filename: filename, size: size, retryCount: retryCount + 1)
            }
        }

        pendingRetries[transferId] = task
    }

    /// Actually retry a download
    private func retryDownload(transferId: UUID, username: String, filename: String, size: UInt64, retryCount: Int) {
        logger.info("Retrying download: \(filename) (attempt \(retryCount))")

        // Update the existing transfer record
        transferState?.updateTransfer(id: transferId) { t in
            t.status = .queued
            t.error = nil
            t.bytesTransferred = 0
            t.retryCount = retryCount
        }

        // Re-initiate the download
        Task {
            await requestDownload(username: username, filename: filename, size: size, existingTransferId: transferId)
        }
    }

    /// Public method to manually retry a failed download
    func retryFailedDownload(transferId: UUID) {
        guard let transfer = transferState?.getTransfer(id: transferId),
              transfer.status == .failed || transfer.status == .cancelled else {
            return
        }

        retryDownload(
            transferId: transferId,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size,
            retryCount: transfer.retryCount + 1
        )
    }

    /// Cancel a pending retry
    func cancelRetry(transferId: UUID) {
        if let task = pendingRetries.removeValue(forKey: transferId) {
            task.cancel()
            logger.info("Cancelled pending retry for transfer \(transferId)")
        }
    }

    /// Request download with optional existing transfer ID (for retries)
    private func requestDownload(username: String, filename: String, size: UInt64, existingTransferId: UUID?) async {
        guard let networkClient else { return }

        // Get or create transfer
        let transferId: UUID
        if let existing = existingTransferId {
            transferId = existing
        } else {
            let transfer = Transfer(
                username: username,
                filename: filename,
                size: size,
                direction: .download,
                status: .queued
            )
            transferState?.addDownload(transfer)
            transferId = transfer.id
        }

        do {
            // Request peer address to establish connection
            // This will trigger the normal download flow via handlePeerAddress callback
            let token = UInt32.random(in: 1...UInt32.max)
            pendingDownloads[token] = PendingDownload(
                transferId: transferId,
                username: username,
                filename: filename,
                size: size
            )

            try await networkClient.getUserAddress(username)
            logger.info("Requested peer address for retry: \(username)")
        } catch {
            logger.error("Retry download failed: \(error.localizedDescription)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
        }
    }
}
