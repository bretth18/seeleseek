import Foundation
import Network
import os
import Synchronization

/// Manages upload queue and file transfers to peers
@Observable
@MainActor
final class UploadManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "UploadManager")

    // MARK: - Dependencies
    private weak var networkClient: NetworkClient?
    private weak var transferState: TransferState?
    private weak var shareManager: ShareManager?
    private weak var statisticsState: StatisticsState?

    // MARK: - Upload Queue
    private var uploadQueue: [QueuedUpload] = []
    private var activeUploads: [UUID: ActiveUpload] = [:]
    private var pendingTransfers: [UInt32: PendingUpload] = [:]  // token -> pending
    private var pendingAddressLookups: [String: [(PendingUpload, UInt32)]] = [:]  // username -> [(pending, token)]

    // Configuration
    var maxConcurrentUploads = 3
    var maxQueuedPerUser = 50  // Max files queued per user (nicotine+ default)
    var uploadSpeedLimit: Int64? = nil  // bytes per second, nil = unlimited

    // MARK: - Types

    struct QueuedUpload: Identifiable {
        let id = UUID()
        let username: String
        let filename: String
        let localPath: String
        let size: UInt64
        let connection: PeerConnection
        let queuedAt: Date
    }

    struct ActiveUpload {
        let transferId: UUID
        let username: String
        let filename: String
        let localPath: String
        let size: UInt64
        let token: UInt32
        var bytesSent: UInt64 = 0
        var startTime: Date?
    }

    struct PendingUpload {
        let transferId: UUID
        let username: String
        let filename: String
        let localPath: String
        let size: UInt64
        let token: UInt32
        let connection: PeerConnection
    }

    // MARK: - Errors

    enum UploadError: Error, LocalizedError {
        case fileNotFound
        case fileNotShared
        case cannotReadFile
        case connectionFailed
        case peerRejected
        case timeout

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "File not found"
            case .fileNotShared: return "File not in shared folders"
            case .cannotReadFile: return "Cannot read file"
            case .connectionFailed: return "Connection to peer failed"
            case .peerRejected: return "Peer rejected the transfer"
            case .timeout: return "Transfer timed out"
            }
        }
    }

    // MARK: - Configuration

    func configure(networkClient: NetworkClient, transferState: TransferState, shareManager: ShareManager, statisticsState: StatisticsState) {
        self.networkClient = networkClient
        self.transferState = transferState
        self.shareManager = shareManager
        self.statisticsState = statisticsState

        // Set up callback for QueueUpload requests (peer wants to download from us)
        networkClient.onQueueUpload = { [weak self] username, filename, connection in
            guard let self else { return }
            _ = await MainActor.run {
                Task {
                    await self.handleQueueUpload(username: username, filename: filename, connection: connection)
                }
            }
        }

        // Set up callback for TransferResponse (peer accepted/rejected our upload offer)
        networkClient.onTransferResponse = { [weak self] token, allowed, filesize, connection in
            guard let self else { return }
            _ = await MainActor.run {
                Task {
                    await self.handleTransferResponse(token: token, allowed: allowed, connection: connection)
                }
            }
        }

        // Set up callback for PlaceInQueueRequest (peer wants to know their queue position)
        networkClient.onPlaceInQueueRequest = { [weak self] username, filename, connection in
            guard let self else { return }
            _ = await MainActor.run {
                Task {
                    await self.handlePlaceInQueueRequest(username: username, filename: filename, connection: connection)
                }
            }
        }

        // Set up callback for peer address using multi-listener pattern
        // This replaces the fragile callback chaining approach that could break if
        // DownloadManager was configured after UploadManager
        networkClient.addPeerAddressHandler { [weak self] username, ip, port in
            self?.logger.debug("Peer address handler called: \(username) @ \(ip):\(port)")
            guard let self else { return }
            Task { @MainActor in
                await self.handlePeerAddressForUpload(username: username, ip: ip, port: port)
            }
        }

        logger.info("UploadManager configured")
    }

    // MARK: - Queue Management

    /// Get current queue position for a file (1-based, 0 = not queued)
    func getQueuePosition(for filename: String, username: String) -> UInt32 {
        guard let index = uploadQueue.firstIndex(where: { $0.filename == filename && $0.username == username }) else {
            return 0
        }
        return UInt32(index + 1)
    }

    // MARK: - Place In Queue Request

    /// Handle PlaceInQueueRequest - peer wants to know their queue position
    private func handlePlaceInQueueRequest(username: String, filename: String, connection: PeerConnection) async {
        logger.info("PlaceInQueueRequest from \(username) for: \(filename)")

        let position = getQueuePosition(for: filename, username: username)

        if position == 0 {
            // Not in queue - maybe file doesn't exist or isn't shared
            logger.debug("File not in queue: \(filename)")
            // Could send UploadDenied here if file doesn't exist
            guard let shareManager else { return }

            if shareManager.fileIndex.first(where: { $0.sharedPath == filename }) == nil {
                do {
                    try await connection.sendUploadDenied(filename: filename, reason: "File not shared")
                } catch {
                    logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
                }
            }
            return
        }

        // Send queue position
        do {
            try await connection.sendPlaceInQueue(filename: filename, place: position)
            logger.info("Sent queue position \(position) for \(filename) to \(username)")
        } catch {
            logger.error("Failed to send PlaceInQueue: \(error.localizedDescription)")
        }
    }

    /// Process the upload queue - start uploads if slots available
    private func processQueue() async {
        let inFlightCount = activeUploads.count + pendingTransfers.count
        guard inFlightCount < maxConcurrentUploads else {
            // Still broadcast updated positions to queued peers
            await broadcastQueuePositions()
            return
        }
        guard !uploadQueue.isEmpty else { return }

        let availableSlots = maxConcurrentUploads - inFlightCount
        let uploadsToStart = uploadQueue.prefix(availableSlots)

        for upload in uploadsToStart {
            await startUpload(upload)
        }

        // Broadcast updated positions to remaining queued peers
        await broadcastQueuePositions()
    }

    /// Tell all queued peers their updated queue position
    private func broadcastQueuePositions() async {
        for (index, upload) in uploadQueue.enumerated() {
            let position = UInt32(index + 1)
            do {
                try await upload.connection.sendPlaceInQueue(filename: upload.filename, place: position)
            } catch {
                logger.debug("Failed to send queue position to \(upload.username): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Upload Flow

    /// Handle incoming QueueUpload request from a peer
    private func handleQueueUpload(username: String, filename: String, connection: PeerConnection) async {
        logger.info("QueueUpload from \(username): \(filename)")

        guard let shareManager else {
            logger.error("ShareManager not configured")
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "Server error")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Look up the file in our shares
        // The filename from SoulSeek uses backslashes as path separators
        guard let indexedFile = shareManager.fileIndex.first(where: { $0.sharedPath == filename }) else {
            logger.warning("File not found in shares: \(filename)")
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "File not shared")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Check if file exists locally
        guard FileManager.default.fileExists(atPath: indexedFile.localPath) else {
            logger.warning("Local file missing: \(indexedFile.localPath)")
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "File not available")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Check per-user queue limit (like nicotine+)
        let userQueueCount = uploadQueue.filter { $0.username == username }.count
        if userQueueCount >= maxQueuedPerUser {
            logger.warning("User \(username) has too many queued uploads (\(userQueueCount))")
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "Too many files queued")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Check for duplicate (same user + same file)
        if uploadQueue.contains(where: { $0.username == username && $0.filename == filename }) {
            logger.debug("File already queued for user: \(filename)")
            let position = getQueuePosition(for: filename, username: username)
            do {
                try await connection.sendPlaceInQueue(filename: filename, place: position)
            } catch {
                logger.error("Failed to send PlaceInQueue: \(error.localizedDescription)")
            }
            return
        }

        // Add to queue
        let queued = QueuedUpload(
            username: username,
            filename: filename,
            localPath: indexedFile.localPath,
            size: indexedFile.size,
            connection: connection,
            queuedAt: Date()
        )
        uploadQueue.append(queued)

        logger.info("Added to upload queue: \(filename) for \(username), position: \(self.uploadQueue.count)")

        // If we have free slots, start immediately, otherwise send queue position
        let inFlightCount = activeUploads.count + pendingTransfers.count
        if inFlightCount < maxConcurrentUploads {
            await startUpload(queued)
        } else {
            // Send queue position
            let position = getQueuePosition(for: filename, username: username)
            do {
                try await connection.sendPlaceInQueue(filename: filename, place: position)
                logger.info("Sent queue position \(position) for \(filename)")
            } catch {
                logger.error("Failed to send PlaceInQueue: \(error.localizedDescription)")
            }
        }
    }

    /// Start an upload - send TransferRequest to peer
    private func startUpload(_ upload: QueuedUpload) async {
        // Remove from queue
        uploadQueue.removeAll { $0.id == upload.id }

        let token = UInt32.random(in: 0...UInt32.max)

        // Create transfer record
        let transfer = Transfer(
            username: upload.username,
            filename: upload.filename,
            size: upload.size,
            direction: .upload,
            status: .connecting
        )
        transferState?.addUpload(transfer)

        // Track pending transfer
        let pending = PendingUpload(
            transferId: transfer.id,
            username: upload.username,
            filename: upload.filename,
            localPath: upload.localPath,
            size: upload.size,
            token: token,
            connection: upload.connection
        )
        pendingTransfers[token] = pending

        logger.info("Starting upload: \(upload.filename) to \(upload.username), token=\(token)")

        // Send TransferRequest (direction=1=upload, meaning we're ready to upload to them)
        do {
            try await upload.connection.sendTransferRequest(
                direction: .upload,
                token: token,
                filename: upload.filename,
                size: upload.size
            )
            logger.info("Sent TransferRequest for \(upload.filename)")

            // Wait for response (timeout after 60 seconds)
            Task {
                try? await Task.sleep(for: .seconds(60))
                if pendingTransfers[token] != nil {
                    // Timed out waiting for response
                    pendingTransfers.removeValue(forKey: token)
                    await MainActor.run {
                        self.transferState?.updateTransfer(id: transfer.id) { t in
                            t.status = .failed
                            t.error = "Timeout waiting for peer response"
                        }
                    }
                }
            }
        } catch {
            logger.error("Failed to send TransferRequest: \(error.localizedDescription)")
            transferState?.updateTransfer(id: transfer.id) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingTransfers.removeValue(forKey: token)
        }
    }

    /// Handle TransferResponse from peer (they accepted or rejected our upload offer)
    private func handleTransferResponse(token: UInt32, allowed: Bool, connection: PeerConnection) async {
        guard let pending = pendingTransfers.removeValue(forKey: token) else {
            logger.debug("No pending upload for token \(token)")
            return
        }

        if !allowed {
            logger.warning("Peer rejected upload for \(pending.filename)")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Peer rejected transfer"
            }
            return
        }

        logger.info("Peer accepted upload for \(pending.filename), opening F connection")

        // Peer accepted - now we need to open an F (file) connection to their listen port
        // First, we need to get their address
        guard let networkClient else {
            logger.error("NetworkClient not available")
            return
        }

        // Update status
        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .transferring
            t.startTime = Date()
        }

        // Track as active upload
        let active = ActiveUpload(
            transferId: pending.transferId,
            username: pending.username,
            filename: pending.filename,
            localPath: pending.localPath,
            size: pending.size,
            token: token,
            startTime: Date()
        )
        activeUploads[pending.transferId] = active

        // Per protocol: Send ConnectToPeer FIRST, then GetPeerAddress
        // ConnectToPeer (code 18) tells the server to forward our connection request to the peer
        // If our direct connection fails, the peer will connect back to us with PierceFirewall

        // Step 1: Send ConnectToPeer to server
        // Use type "F" since this is for a file transfer connection
        await networkClient.sendConnectToPeer(token: token, username: pending.username, connectionType: "F")
        logger.debug("Sent ConnectToPeer to server for upload to \(pending.username)")

        // Register pending transfer BEFORE getting address, so PierceFirewall can find it
        pendingTransfers[token] = pending
        logger.debug("Registered pending upload token=\(token) for PierceFirewall")

        // Step 2: Request peer address for direct F connection attempt
        // IMPORTANT: Always use getUserAddress to get the peer's actual LISTEN port,
        // not the ephemeral source port from the existing P connection
        do {
            logger.info("Requesting peer address for F connection to \(pending.username)")
            pendingAddressLookups[pending.username, default: []].append((pending, token))
            logger.info("Stored pending address lookup: \(pending.username) -> token=\(token)")
            try await networkClient.getUserAddress(pending.username)
            logger.debug("GetPeerAddress request sent for \(pending.username)")
            // The actual F connection will be triggered by handlePeerAddressForUpload callback

        } catch {
            logger.error("Failed to get peer address: \(error.localizedDescription)")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Failed to connect to peer"
            }
            activeUploads.removeValue(forKey: pending.transferId)
        }
    }

    /// Handle peer address callback for pending uploads
    private func handlePeerAddressForUpload(username: String, ip: String, port: Int) async {
        guard var entries = pendingAddressLookups[username], !entries.isEmpty else {
            return
        }

        // Pop the first pending upload for this user
        let (pending, token) = entries.removeFirst()
        if entries.isEmpty {
            pendingAddressLookups.removeValue(forKey: username)
        } else {
            pendingAddressLookups[username] = entries
            // Re-request address for remaining entries (server only sends one response per request)
            Task {
                try? await networkClient?.getUserAddress(username)
            }
        }

        logger.info("Received peer address for upload to \(username): \(ip):\(port)")

        guard port > 0 else {
            logger.warning("Invalid port for \(username)")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Could not get peer address"
            }
            activeUploads.removeValue(forKey: pending.transferId)
            return
        }

        // Now open F connection
        await openFileConnection(to: ip, port: port, pending: pending, token: token)
    }

    /// Open an F (file) connection to peer and send file data
    private func openFileConnection(to ip: String, port: Int, pending: PendingUpload, token: UInt32) async {
        logger.info("Opening F connection to \(ip):\(port) for \(pending.filename)")

        guard let networkClient else { return }

        // Validate port
        guard port > 0, port <= Int(UInt16.max), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            logger.error("Invalid port: \(port)")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Invalid peer port"
            }
            activeUploads.removeValue(forKey: pending.transferId)
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: nwPort
        )

        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        // Wait for connection
        let hasResumed = Mutex(false)
        let connected: Bool = await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    guard hasResumed.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            // Timeout
            Task {
                try? await Task.sleep(for: .seconds(30))
                guard hasResumed.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(returning: false)
            }
        }

        guard connected else {
            logger.error("Failed direct F connection to peer \(pending.username)")

            // Direct connection failed (likely NAT/firewall)
            // We already sent ConnectToPeer to the server before GetPeerAddress,
            // so the server has already forwarded our request to the peer.
            // The peer will now attempt to connect to us via PierceFirewall.
            // We registered pendingTransfers[token] before GetPeerAddress, so we're ready.
            // NOTE: Do NOT send CantConnectToPeer - that's what the PEER sends if THEY can't connect to US

            // Only update status if this upload is still pending
            // (PierceFirewall may have already arrived and completed the upload while we were waiting)
            if pendingTransfers[token] != nil {
                logger.info("Waiting for peer \(pending.username) to connect via PierceFirewall (token=\(token))")

                transferState?.updateTransfer(id: pending.transferId) { t in
                    t.status = .connecting
                    t.error = "Waiting for peer to connect (firewall)"
                }

                // Timeout: fail the upload if PierceFirewall doesn't arrive within 30s
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard let self else { return }
                    if let stale = self.pendingTransfers.removeValue(forKey: token) {
                        self.logger.warning("PierceFirewall timeout for upload \(stale.filename) to \(stale.username)")
                        self.transferState?.updateTransfer(id: stale.transferId) { t in
                            t.status = .failed
                            t.error = "Peer connection timeout (firewall)"
                        }
                        self.activeUploads.removeValue(forKey: stale.transferId)
                        await self.processQueue()
                    }
                }
            } else {
                logger.debug("Upload already completed via PierceFirewall for token=\(token)")
            }

            return
        }

        logger.info("F connection established to \(ip):\(port)")

        // Send PeerInit with type "F" and token 0 (always 0 for F connections per protocol)
        // PeerInit format: [length][code=1][username][type="F"][token=0]
        let username = networkClient.username
        var initPayload = Data()
        initPayload.appendUInt8(1)  // PeerInit code
        initPayload.appendString(username)
        initPayload.appendString("F")
        initPayload.appendUInt32(0)  // Token is always 0 for F connections

        var initMessage = Data()
        initMessage.appendUInt32(UInt32(initPayload.count))
        initMessage.append(initPayload)

        do {
            try await sendData(connection: connection, data: initMessage)
            logger.info("Sent PeerInit for F connection")
        } catch {
            logger.error("Failed to send PeerInit: \(error.localizedDescription)")
            connection.cancel()
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Failed to initiate file transfer"
            }
            activeUploads.removeValue(forKey: pending.transferId)
            return
        }

        // Per SoulSeek/nicotine+ protocol on F connections (uploader side):
        // 1. Uploader sends PeerInit (done above)
        // 2. UPLOADER sends FileTransferInit (token - 4 bytes)
        // 3. DOWNLOADER sends FileOffset (offset - 8 bytes)
        // 4. Uploader sends raw file data
        // See: https://nicotine-plus.org/doc/SLSKPROTOCOL.md step 8-9

        do {
            // Step 2: Send FileTransferInit (token - 4 bytes)
            var tokenData = Data()
            tokenData.appendUInt32(token)
            logger.debug("Sending FileTransferInit: token=\(token)")
            try await sendData(connection: connection, data: tokenData)
            logger.info("Sent FileTransferInit: token=\(token)")

            // Step 3: Receive FileOffset from downloader (offset - 8 bytes)
            logger.debug("Waiting for FileOffset from downloader")
            let offsetData = try await receiveExact(connection: connection, length: 8)
            guard offsetData.count == 8 else {
                throw UploadError.connectionFailed
            }

            let offset = offsetData.readUInt64(at: 0) ?? 0
            logger.info("Received FileOffset: offset=\(offset)")

            // Step 4: Send file data starting from offset
            await sendFileData(
                connection: connection,
                filePath: pending.localPath,
                offset: offset,
                transferId: pending.transferId,
                totalSize: pending.size
            )

        } catch {
            logger.error("Failed during F connection handshake: \(error.localizedDescription)")
            connection.cancel()
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = "Failed to start file transfer"
            }
            activeUploads.removeValue(forKey: pending.transferId)
        }
    }

    /// Send file data over the connection
    private func sendFileData(
        connection: NWConnection,
        filePath: String,
        offset: UInt64,
        transferId: UUID,
        totalSize: UInt64
    ) async {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            logger.error("Cannot open file: \(filePath)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "Cannot read file"
            }
            activeUploads.removeValue(forKey: transferId)
            connection.cancel()
            return
        }
        defer {
            try? fileHandle.close()
            connection.cancel()
        }

        // Seek to offset
        if offset > 0 {
            do {
                try fileHandle.seek(toOffset: offset)
            } catch {
                logger.error("Failed to seek to offset: \(error.localizedDescription)")
                transferState?.updateTransfer(id: transferId) { t in
                    t.status = .failed
                    t.error = "Failed to seek in file"
                }
                activeUploads.removeValue(forKey: transferId)
                return
            }
        }

        var bytesSent: UInt64 = offset
        let startTime = Date()
        let chunkSize = 65536  // 64KB chunks

        logger.info("Sending file data: \(filePath) from offset \(offset)")

        do {
            while bytesSent < totalSize {
                // Read chunk
                guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }

                // Send chunk
                try await sendData(connection: connection, data: chunk)
                bytesSent += UInt64(chunk.count)

                // Update progress
                let elapsed = Date().timeIntervalSince(startTime)
                let speed = elapsed > 0 ? Int64(Double(bytesSent - offset) / elapsed) : 0

                await MainActor.run { [transferState] in
                    transferState?.updateTransfer(id: transferId) { t in
                        t.bytesTransferred = bytesSent
                        t.speed = speed
                    }
                }

                // Respect speed limit if set
                if let limit = uploadSpeedLimit, speed > limit {
                    let delay = Double(chunk.count) / Double(limit)
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                }
            }

            // Signal EOF to the connection to ensure all data is flushed
            // This sends an empty final message which triggers TCP to push remaining data
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }

            // Give TCP stack time to flush any remaining buffered data
            // This is important because cancel() might tear down the connection before TCP sends all data
            try? await Task.sleep(for: .milliseconds(500))

            // Complete
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Upload complete: \(bytesSent) bytes sent in \(String(format: "%.1f", duration))s")

            let filename = (filePath as NSString).lastPathComponent
            let uploadUsername = activeUploads[transferId]?.username ?? "unknown"

            await MainActor.run { [transferState, statisticsState] in
                transferState?.updateTransfer(id: transferId) { t in
                    t.status = .completed
                    t.bytesTransferred = bytesSent
                }

                // Record in statistics
                statisticsState?.recordTransfer(
                    filename: filename,
                    username: uploadUsername,
                    size: bytesSent,
                    duration: duration,
                    isDownload: false
                )
            }

            activeUploads.removeValue(forKey: transferId)
            ActivityLog.shared.logUploadCompleted(filename: filename)

            // Process queue for next upload
            await processQueue()

        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")

            await MainActor.run { [transferState] in
                transferState?.updateTransfer(id: transferId) { t in
                    t.status = .failed
                    t.error = error.localizedDescription
                }
            }

            activeUploads.removeValue(forKey: transferId)

            // Process queue for next upload
            await processQueue()
        }
    }

    // MARK: - Network Helpers

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

    private func receiveExact(connection: NWConnection, length: Int, timeout: TimeInterval = 30) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: UploadError.connectionFailed)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw UploadError.timeout
            }

            guard let result = try await group.next() else {
                throw UploadError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Public API

    /// Get current upload queue
    var queuedUploads: [QueuedUpload] { uploadQueue }

    /// Get number of active uploads
    var activeUploadCount: Int { activeUploads.count }

    /// Cancel a queued upload
    func cancelQueuedUpload(_ id: UUID) {
        uploadQueue.removeAll { $0.id == id }
    }

    /// Cancel an active upload
    func cancelActiveUpload(_ transferId: UUID) async {
        if let upload = activeUploads.removeValue(forKey: transferId) {
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "Cancelled"
            }
            logger.info("Cancelled upload: \(upload.filename)")
        }
    }

    // MARK: - PierceFirewall Handling

    /// Check if we have a pending upload for this token
    func hasPendingUpload(token: UInt32) -> Bool {
        return pendingTransfers[token] != nil
    }

    /// Handle CantConnectToPeer — server tells us the peer couldn't reach us, fail the upload
    func handleCantConnectToPeer(token: UInt32) {
        guard let pending = pendingTransfers.removeValue(forKey: token) else { return }
        logger.warning("CantConnectToPeer for upload \(pending.filename) — peer unreachable")
        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "Peer unreachable (firewall)"
        }
        activeUploads.removeValue(forKey: pending.transferId)
        Task { await processQueue() }
    }

    /// Handle PierceFirewall for upload (indirect connection from peer)
    func handlePierceFirewall(token: UInt32, connection: PeerConnection) async {
        guard let pending = pendingTransfers.removeValue(forKey: token) else {
            logger.warning("No pending upload for PierceFirewall token \(token)")
            return
        }

        logger.info("PierceFirewall matched to pending upload: \(pending.filename)")

        // Update the connection's username (PierceFirewall doesn't include PeerInit with username)
        await connection.setPeerUsername(pending.username)

        // Also update the pool's connection info so Network Monitor shows the correct username
        await networkClient?.peerConnectionPool.updateConnectionUsername(connection: connection, username: pending.username)

        // Update transfer status
        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .connecting
            t.error = nil
        }

        // Continue with file transfer using this connection
        await continueUploadWithConnection(pending: pending, connection: connection)
    }

    /// Continue upload after indirect connection established via PierceFirewall
    private func continueUploadWithConnection(pending: PendingUpload, connection: PeerConnection) async {
        guard networkClient != nil else {
            logger.error("NetworkClient is nil in continueUploadWithConnection")
            return
        }

        // Track as active upload
        let active = ActiveUpload(
            transferId: pending.transferId,
            username: pending.username,
            filename: pending.filename,
            localPath: pending.localPath,
            size: pending.size,
            token: pending.token,
            startTime: Date()
        )
        activeUploads[pending.transferId] = active

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .transferring
            t.startTime = Date()
        }

        do {
            // For INDIRECT connections (via PierceFirewall), we do NOT send PeerInit.
            // The connection is already identified by the token in PierceFirewall.
            // PeerInit is only sent when WE initiate an outgoing connection.
            //
            // Per protocol for F connections after PierceFirewall:
            // 1. Uploader sends FileTransferInit (just uint32 token, NO length prefix)
            // 2. Downloader sends FileOffset (just uint64 offset, NO length prefix)
            // 3. Uploader sends raw file data

            logger.debug("Sending FileTransferInit for token=\(pending.token)")
            let connState = await connection.getState()
            logger.debug("Connection state: \(String(describing: connState))")

            // Send FileTransferInit - just the token, no length prefix
            var tokenData = Data()
            tokenData.appendUInt32(pending.token)

            try await connection.sendRaw(tokenData)
            logger.debug("FileTransferInit sent for token=\(pending.token)")

            // Receive FileOffset from downloader (8 bytes, no length prefix)
            logger.debug("Waiting for FileOffset from downloader (8 bytes, 30s timeout)")
            let offsetData = try await connection.receiveRawBytes(count: 8, timeout: 30)
            let offset = offsetData.readUInt64(at: 0) ?? 0
            logger.debug("Received FileOffset: offset=\(offset)")

            // Send file data starting from offset
            await sendFileDataViaPeerConnection(
                connection: connection,
                filePath: pending.localPath,
                offset: offset,
                transferId: pending.transferId,
                totalSize: pending.size
            )
        } catch {
            logger.error("Failed to continue upload via PierceFirewall: \(error.localizedDescription)")
            let failState = await connection.getState()
            logger.debug("Connection state at failure: \(String(describing: failState))")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            activeUploads.removeValue(forKey: pending.transferId)
        }
    }

    /// Send file data over a PeerConnection (for indirect/PierceFirewall uploads)
    private func sendFileDataViaPeerConnection(
        connection: PeerConnection,
        filePath: String,
        offset: UInt64,
        transferId: UUID,
        totalSize: UInt64
    ) async {
        logger.info("Starting file transfer via PeerConnection: \(filePath) offset=\(offset)")

        guard FileManager.default.fileExists(atPath: filePath) else {
            logger.error("File not found: \(filePath)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "File not found"
            }
            activeUploads.removeValue(forKey: transferId)
            return
        }

        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            logger.error("Could not open file: \(filePath)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "Could not open file"
            }
            activeUploads.removeValue(forKey: transferId)
            return
        }

        defer {
            try? fileHandle.close()
        }

        do {
            try fileHandle.seek(toOffset: offset)
        } catch {
            logger.error("Could not seek to offset \(offset): \(error)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "Could not seek in file"
            }
            activeUploads.removeValue(forKey: transferId)
            return
        }

        let chunkSize = 65536  // 64KB chunks (match direct upload path)
        var bytesSent: UInt64 = offset
        let startTime = Date()
        var lastProgressUpdate = Date()

        do {
            while bytesSent < totalSize {
                // Read chunk from file
                guard let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }

                // Send chunk - AWAIT the send to ensure ordering and catch errors
                try await connection.sendRaw(chunk)
                bytesSent += UInt64(chunk.count)

                // Update progress periodically
                if Date().timeIntervalSince(lastProgressUpdate) >= 0.5 {
                    lastProgressUpdate = Date()
                    let elapsed = Date().timeIntervalSince(startTime)
                    let bytesTransferred = bytesSent - offset
                    let speed = elapsed > 0 ? Int64(Double(bytesTransferred) / elapsed) : 0

                    transferState?.updateTransfer(id: transferId) { t in
                        t.bytesTransferred = bytesSent
                        t.speed = speed
                    }
                }
            }

            // Complete
            let elapsed = Date().timeIntervalSince(startTime)
            let bytesTransferred = bytesSent - offset
            let avgSpeed = elapsed > 0 ? Double(bytesTransferred) / elapsed : 0

            logger.info("Upload complete: \(filePath) (\(bytesTransferred) bytes in \(String(format: "%.1f", elapsed))s, \(Int64(avgSpeed)) B/s)")

            transferState?.updateTransfer(id: transferId) { t in
                t.status = .completed
                t.bytesTransferred = bytesSent
                t.error = nil
            }

            activeUploads.removeValue(forKey: transferId)
            ActivityLog.shared.logUploadCompleted(filename: (filePath as NSString).lastPathComponent)

            // Record statistics
            if let transfer = transferState?.getTransfer(id: transferId) {
                statisticsState?.recordTransfer(
                    filename: transfer.filename,
                    username: transfer.username,
                    size: UInt64(bytesTransferred),
                    duration: elapsed,
                    isDownload: false
                )
            }

            // Process queue for next upload
            await processQueue()

        } catch {
            logger.error("Upload failed via PeerConnection: \(error.localizedDescription)")

            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }

            activeUploads.removeValue(forKey: transferId)
            await processQueue()
        }
    }
}

