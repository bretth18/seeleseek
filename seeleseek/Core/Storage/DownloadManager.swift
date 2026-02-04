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

    // MARK: - Pending Downloads
    // Maps token to pending download info
    private var pendingDownloads: [UInt32: PendingDownload] = [:]

    // Maps username to pending file transfers (waiting for F connection)
    // We use username because PeerInit on F connections always has token=0
    private var pendingFileTransfersByUser: [String: PendingFileTransfer] = [:]

    struct PendingDownload {
        let transferId: UUID
        let username: String
        let filename: String
        var size: UInt64
        var peerConnection: PeerConnection?
        var peerIP: String?       // Store peer IP for outgoing F connection
        var peerPort: Int?        // Store peer port for outgoing F connection
    }

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

    func configure(networkClient: NetworkClient, transferState: TransferState, statisticsState: StatisticsState) {
        self.networkClient = networkClient
        self.transferState = transferState
        self.statisticsState = statisticsState

        // Set up callbacks for peer address responses
        print("🔧 DownloadManager: Setting up onPeerAddress callback")
        networkClient.onPeerAddress = { [weak self] username, ip, port in
            print("📞 DownloadManager.onPeerAddress closure called: \(username) @ \(ip):\(port)")
            Task { @MainActor in
                await self?.handlePeerAddress(username: username, ip: ip, port: port)
            }
        }
        print("✅ DownloadManager: onPeerAddress callback configured")

        // Set up callback for incoming connections that match pending downloads
        networkClient.onIncomingConnectionMatched = { [weak self] username, token, connection in
            guard let self else { return }
            Task { @MainActor in
                await self.handleIncomingConnection(username: username, token: token, connection: connection)
            }
        }

        // Set up callback for incoming file transfer connections
        print("🔧 DownloadManager: Setting up onFileTransferConnection callback")
        networkClient.onFileTransferConnection = { [weak self] username, token, connection in
            print("📁 DownloadManager callback invoked - username='\(username)' token=\(token)")
            guard let self else {
                print("❌ DownloadManager: self is nil in callback!")
                return
            }
            Task { @MainActor in
                await self.handleFileTransferConnection(username: username, token: token, connection: connection)
            }
        }
        print("✅ DownloadManager: onFileTransferConnection callback configured")

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
    }

    // MARK: - Download API

    /// Queue a file for download
    func queueDownload(from result: SearchResult) {
        print("")
        print("╔════════════════════════════════════════════════════════════╗")
        print("║  DOWNLOAD STARTED                                          ║")
        print("╠════════════════════════════════════════════════════════════╣")
        print("║  File: \(result.displayFilename)")
        print("║  From: \(result.username)")
        print("║  Size: \(result.formattedSize)")
        print("╚════════════════════════════════════════════════════════════╝")
        print("")

        guard let transferState else {
            print("❌ DownloadManager: TransferState not configured!")
            logger.error("TransferState not configured")
            return
        }

        guard networkClient != nil else {
            print("❌ DownloadManager: NetworkClient not configured!")
            logger.error("NetworkClient not configured")
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
        print("✅ Download queued: \(result.filename)")
        logger.info("Queued download: \(result.filename) from \(result.username)")

        // Start the download process
        Task {
            await startDownload(transfer: transfer)
        }
    }

    // MARK: - Download Flow

    private func startDownload(transfer: Transfer) async {
        print("📥 startDownload: \(transfer.filename) from \(transfer.username)")

        guard let networkClient, let transferState else {
            print("❌ startDownload: NetworkClient or TransferState is nil!")
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

        print("📥 Starting download from \(transfer.username), token=\(token)")
        logger.info("Starting download from \(transfer.username), token=\(token)")

        do {
            // Step 1: Get peer address
            print("📥 Requesting peer address for \(transfer.username)...")
            try await networkClient.getUserAddress(transfer.username)
            print("📥 Peer address request sent, waiting for callback...")

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
        print("")
        print("▶▶▶ PEER ADDRESS RECEIVED: \(username) @ \(ip):\(port)")
        print("")

        guard let networkClient, let transferState else {
            print("❌ handlePeerAddress: NetworkClient or TransferState is nil!")
            return
        }

        // Find pending download for this user
        guard let (token, pending) = pendingDownloads.first(where: { $0.value.username == username }) else {
            print("⚠️ No pending download for \(username)")
            logger.debug("No pending download for \(username)")
            return
        }

        print("📍 Found pending download for \(username), token=\(token)")
        logger.info("Got peer address for \(username): \(ip):\(port)")

        // Store peer address for potential outgoing F connection
        pendingDownloads[token]?.peerIP = ip
        pendingDownloads[token]?.peerPort = port

        // First, check if we already have a connection to this user (from incoming connections)
        if let existingConnection = networkClient.peerConnectionPool.getConnectionForUser(username) {
            print("✅ Reusing existing connection to \(username)")
            logger.info("Reusing existing connection to \(username)")

            pendingDownloads[token]?.peerConnection = existingConnection

            do {
                // Set up callback BEFORE sending QueueDownload to avoid race condition
                await setupTransferRequestCallback(token: token, connection: existingConnection)

                try await existingConnection.queueDownload(filename: pending.filename)
                print("📤 Sent QueueDownload for \(pending.filename)")
                logger.info("Sent QueueDownload for \(pending.filename)")

                await waitForTransferResponse(token: token)
            } catch {
                print("❌ Failed to queue download on existing connection: \(error)")
                logger.error("Failed to queue download: \(error.localizedDescription)")
                transferState.updateTransfer(id: pending.transferId) { t in
                    t.status = .failed
                    t.error = error.localizedDescription
                }
                pendingDownloads.removeValue(forKey: token)
            }
            return
        }

        print("📍 No existing connection, trying direct connection (10s timeout)...")

        // Try to connect to peer with a timeout
        do {
            // Use a simpler timeout approach
            let connectTask = Task {
                try await networkClient.peerConnectionPool.connect(
                    to: username,
                    ip: ip,
                    port: port,
                    token: token
                )
            }

            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(10))
                connectTask.cancel()
                print("⏰ TIMEOUT: Direct connection to \(username) timed out after 10s")
            }

            let connection: PeerConnection
            do {
                connection = try await connectTask.value
                timeoutTask.cancel()
                print("✅ Direct connection established to \(username)")
            } catch {
                timeoutTask.cancel()
                throw error
            }

            // Connected! Send queue download request
            pendingDownloads[token]?.peerConnection = connection

            // Set up callback BEFORE sending QueueDownload to avoid race condition
            await setupTransferRequestCallback(token: token, connection: connection)

            try await connection.queueDownload(filename: pending.filename)
            print("📤 Sent QueueDownload for \(pending.filename)")
            logger.info("Sent QueueDownload for \(pending.filename)")

            // Wait for transfer response
            await waitForTransferResponse(token: token)

        } catch {
            print("❌ Direct connection failed: \(error.localizedDescription)")
            logger.warning("Direct connection failed: \(error.localizedDescription)")

            // Update transfer status
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .connecting
                t.error = "Trying indirect connection..."
            }

            // Send CantConnectToPeer to request indirect connection
            print("📤 Sending CantConnectToPeer for \(username) token=\(token)")
            print("   ℹ️ Our listen port: \(networkClient.listenPort)")
            print("   ℹ️ If peer can't connect to us, ensure port \(networkClient.listenPort) is open in your firewall")
            await networkClient.sendCantConnectToPeer(token: token, username: username)

            // Register pending connection so incoming PierceFirewall can be matched
            networkClient.peerConnectionPool.addPendingConnection(username: username, token: token)

            // Wait for indirect connection via PierceFirewall
            // The server should tell the peer to connect to us
            logger.info("Waiting for indirect connection to \(username)")
            print("⏳ Waiting for indirect connection to \(username) (token=\(token))...")
            print("   The peer should connect to us with PierceFirewall message...")
            print("   If this fails, both parties may be behind restrictive NAT.")

            // Set a dedicated timeout for indirect connection
            Task {
                try? await Task.sleep(for: .seconds(15))

                // Check if still pending after 15 seconds
                if pendingDownloads[token] != nil && pendingDownloads[token]?.peerConnection == nil {
                    print("⏰ TIMEOUT: Indirect connection to \(username) timed out after 15s")
                    print("❌ Could not establish connection - both direct and indirect failed")
                    print("   Possible causes:")
                    print("   - Both you and the peer are behind NAT/firewall")
                    print("   - Try downloading from a different user")
                    print("   - Configure port forwarding for port \(networkClient.listenPort)")

                    transferState.updateTransfer(id: pending.transferId) { t in
                        t.status = .failed
                        t.error = "Connection failed - peer unreachable (NAT/firewall)"
                    }
                    pendingDownloads.removeValue(forKey: token)
                }
            }
        }
    }

    /// Set up callback for TransferRequest - must be called BEFORE sending QueueDownload
    private func setupTransferRequestCallback(token: UInt32, connection: PeerConnection) async {
        await connection.setOnTransferRequest { [weak self] request in
            guard let self else { return }
            await self.handleTransferRequest(token: token, request: request)
        }
        print("📝 TransferRequest callback set up for token=\(token)")
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
            let pendingTransfer = PendingFileTransfer(
                transferId: pending.transferId,
                username: pending.username,
                filename: pending.filename,
                size: request.size,
                downloadToken: token,
                transferToken: request.token,  // This is sent on F connection handshake
                offset: 0                       // Start from beginning
            )
            pendingFileTransfersByUser[pending.username] = pendingTransfer
            logger.info("Registered pending file transfer for \(pending.username): transferToken=\(request.token)")
            print("✅ Registered pendingFileTransfersByUser[\(pending.username)] - transferToken=\(request.token) size=\(request.size)")
            print("📋 Current pendingFileTransfersByUser keys: \(Array(pendingFileTransfersByUser.keys))")

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
                if pendingFileTransfersByUser[peerUsername] != nil {
                    print("⏰ No incoming F connection after 5s, trying outgoing F connection to \(peerUsername)")
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
                if pendingFileTransfersByUser[peerUsername] != nil {
                    pendingFileTransfersByUser.removeValue(forKey: peerUsername)
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
            }

            logger.info("Download complete: \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)

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
            print("❌ Cannot initiate outgoing F connection: missing peer address")
            logger.warning("Cannot initiate outgoing F connection to \(username): missing address")
            return
        }

        guard let transferState else { return }

        // Check if still pending
        guard let pending = pendingFileTransfersByUser[username] else {
            print("ℹ️ Outgoing F connection not needed - transfer no longer pending")
            return
        }

        print("🔌 Initiating outgoing F connection to \(username) at \(ip):\(port)")
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

            print("✅ Outgoing F connection established to \(username)")
            logger.info("Outgoing F connection established to \(username)")

            // Send PeerInit with type "F"
            guard let networkClient else {
                throw DownloadError.noPeerConnection
            }

            let peerInitMessage = MessageBuilder.peerInitMessage(
                username: networkClient.username,
                connectionType: "F",
                token: 0  // F connections always use token 0 in PeerInit
            )
            try await sendData(connection: connection, data: peerInitMessage)
            print("📤 Sent PeerInit type=F to \(username)")

            // Remove from pending (we're handling it now)
            pendingFileTransfersByUser.removeValue(forKey: username)

            // Send token + offset (same as handleFileTransferConnection)
            var handshakeData = Data()
            handshakeData.appendUInt32(transferToken)
            handshakeData.appendUInt64(0)  // offset = 0

            print("📤 Sending file transfer handshake: token=\(transferToken) offset=0")
            try await sendData(connection: connection, data: handshakeData)
            print("✅ File transfer handshake sent, receiving file data...")

            // Compute destination path preserving folder structure
            let destPath = computeDestPath(for: pending.filename, username: username)
            let filename = destPath.lastPathComponent

            // Receive file data
            try await receiveFileData(
                connection: connection,
                destPath: destPath,
                expectedSize: fileSize,
                transferId: pending.transferId
            )

            // Calculate transfer duration
            let duration = Date().timeIntervalSince(transferState.getTransfer(id: pending.transferId)?.startTime ?? Date())

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = fileSize
                t.localPath = destPath
            }

            logger.info("Download complete (outgoing F): \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)

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
            print("❌ Outgoing F connection failed: \(error)")
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

    private func receiveFileData(connection: NWConnection, destPath: URL, expectedSize: UInt64, transferId: UUID) async throws {
        // Ensure parent directory exists
        let parentDir = destPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create parent directory \(parentDir.path): \(error)")
            print("❌ Failed to create directory: \(parentDir.path) - \(error)")
            throw DownloadError.cannotCreateFile
        }

        // Create file for writing
        let created = FileManager.default.createFile(atPath: destPath.path, contents: nil)
        if !created {
            logger.error("Failed to create file at \(destPath.path)")
            print("❌ FileManager.createFile failed at: \(destPath.path)")
        }

        guard let fileHandle = try? FileHandle(forWritingTo: destPath) else {
            logger.error("Failed to open file handle for \(destPath.path)")
            print("❌ Cannot open file handle for: \(destPath.path)")
            throw DownloadError.cannotCreateFile
        }

        var bytesReceived: UInt64 = 0
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

        print("📏 File verification (NW):")
        print("   Expected size (from TransferRequest): \(expectedSize) bytes")
        print("   Bytes received in transfer loop: \(bytesReceived) bytes")
        print("   Actual file size on disk: \(actualSize) bytes")

        // If expected size is 0, something went wrong with TransferRequest parsing
        if expectedSize == 0 {
            logger.error("Expected size is 0 - TransferRequest parsing likely failed")
            print("❌ Expected size is 0! This indicates TransferRequest size was not parsed correctly.")
        }

        // Allow small discrepancy (up to 0.1% or 1KB, whichever is larger)
        let tolerance = max(1024, expectedSize / 1000)
        let sizeDiff = actualSize > expectedSize ? actualSize - expectedSize : expectedSize - actualSize

        print("   Size difference: \(sizeDiff) bytes, tolerance: \(tolerance) bytes")

        if expectedSize > 0 && sizeDiff > tolerance {
            logger.error("File size mismatch: expected \(expectedSize), got \(actualSize) (diff: \(sizeDiff))")
            print("❌ File size mismatch exceeds tolerance: \(sizeDiff) > \(tolerance)")
            throw DownloadError.incompleteTransfer(expected: expectedSize, actual: actualSize)
        }

        if actualSize != expectedSize && expectedSize > 0 {
            logger.warning("Minor size discrepancy: expected \(expectedSize), got \(actualSize) (diff: \(sizeDiff) bytes) - accepting")
            print("⚠️ Minor size discrepancy (\(sizeDiff) bytes) - within tolerance, accepting file")
        }

        connection.cancel()
        logger.info("File transfer complete and verified: \(actualSize) bytes received")
        print("✅ File transfer COMPLETE (NW): \(destPath.lastPathComponent) (\(actualSize) bytes)")
    }

    private func receiveChunkWithStatus(connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
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
            print("📁 Download directory: \(downloadsDir.path)")
        } catch {
            print("❌ Failed to create download directory: \(downloadsDir.path) - \(error)")
            // Fall back to app's document directory
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let fallbackDir = appSupport.appendingPathComponent("SeeleSeek/Downloads")
                try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
                print("📁 Using fallback directory: \(fallbackDir.path)")
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

        // Build path: username/Artist/Album/Song.mp3
        // Include username to avoid conflicts between different users' files
        var destURL = downloadDir.appendingPathComponent(username)
        for component in pathComponents {
            // Sanitize each component (remove invalid filesystem characters)
            let sanitized = sanitizeFilename(component)
            destURL = destURL.appendingPathComponent(sanitized)
        }

        return destURL
    }

    /// Sanitize a filename/folder name for the filesystem
    private func sanitizeFilename(_ name: String) -> String {
        // Remove/replace characters that are invalid in macOS filenames
        var sanitized = name
        let invalidChars: [Character] = [":", "/", "\0"]
        for char in invalidChars {
            sanitized = sanitized.replacingOccurrences(of: String(char), with: "_")
        }
        // Trim whitespace and dots from ends
        sanitized = sanitized.trimmingCharacters(in: .whitespaces)
        if sanitized.hasPrefix(".") {
            sanitized = "_" + sanitized.dropFirst()
        }
        return sanitized.isEmpty ? "unnamed" : sanitized
    }

    // MARK: - Incoming Connection Handling

    /// Called when we receive an indirect connection from a peer
    func handleIncomingConnection(username: String, token: UInt32, connection: PeerConnection) async {
        guard let pending = pendingDownloads[token] else {
            // Not a download we're waiting for
            return
        }

        guard let networkClient else {
            print("❌ NetworkClient is nil in handleIncomingConnection")
            return
        }

        logger.info("Indirect connection established with \(username) for token \(token)")

        pendingDownloads[token]?.peerConnection = connection

        // Send PeerInit + QueueDownload
        // Per protocol: We need to send PeerInit to identify ourselves before QueueUpload
        do {
            // Send PeerInit FIRST - identifies us to the peer (token=0 for P connections)
            try await connection.sendPeerInit(username: networkClient.username)
            print("📤 Sent PeerInit via indirect connection")

            // Set up callback BEFORE sending QueueDownload to avoid race condition
            await setupTransferRequestCallback(token: token, connection: connection)

            try await connection.queueDownload(filename: pending.filename)
            logger.info("Sent QueueDownload via indirect connection")

            await waitForTransferResponse(token: token)
        } catch {
            logger.error("Failed to queue download: \(error.localizedDescription)")
        }
    }

    /// Called when a peer opens a file transfer connection to us (type "F")
    /// Per SoulSeek protocol: After PeerInit, downloader sends token (4 bytes) + offset (8 bytes), then receives file data
    func handleFileTransferConnection(username: String, token: UInt32, connection: PeerConnection) async {
        print("🎯 handleFileTransferConnection CALLED - username='\(username)' token=\(token)")
        print("📋 Looking for pendingFileTransfersByUser keys: \(Array(pendingFileTransfersByUser.keys))")

        guard transferState != nil else {
            logger.error("TransferState not configured")
            print("❌ TransferState not configured!")
            return
        }

        // Look up the pending file transfer by USERNAME (not token, because PeerInit token is always 0 for F connections)
        // Try exact match first, then case-insensitive match
        var pending: PendingFileTransfer?
        var matchedKey: String?

        if let exactMatch = pendingFileTransfersByUser[username] {
            pending = exactMatch
            matchedKey = username
        } else {
            // Try case-insensitive lookup
            let lowercaseUsername = username.lowercased()
            for (key, value) in pendingFileTransfersByUser {
                if key.lowercased() == lowercaseUsername {
                    pending = value
                    matchedKey = key
                    print("📋 Case-insensitive match: '\(username)' -> '\(key)'")
                    break
                }
            }
        }

        guard let pending = pending, let matchedKey = matchedKey else {
            // If only one pending transfer, use it (common case)
            if pendingFileTransfersByUser.count == 1, let (onlyKey, onlyValue) = pendingFileTransfersByUser.first {
                print("📋 Using only pending transfer: '\(onlyKey)' (received username was '\(username)')")
                pendingFileTransfersByUser.removeValue(forKey: onlyKey)
                await handleFileTransferWithPending(onlyValue, connection: connection)
                return
            }

            logger.warning("No pending file transfer for username \(username)")
            print("⚠️ No pending file transfer for '\(username)' - available keys: \(Array(pendingFileTransfersByUser.keys))")
            return
        }

        pendingFileTransfersByUser.removeValue(forKey: matchedKey)

        print("✅ Found pending file transfer for '\(username)': \(pending.filename)")

        // Call the common handler to actually do the transfer
        await handleFileTransferWithPending(pending, connection: connection)
    }

    /// Common handler for file transfer with a pending transfer record
    private func handleFileTransferWithPending(_ pending: PendingFileTransfer, connection: PeerConnection) async {
        guard let transferState else {
            logger.error("TransferState not configured in handleFileTransferWithPending")
            return
        }

        logger.info("File transfer connection, sending transferToken=\(pending.transferToken) offset=\(pending.offset)")
        print("📁 F connection: transferToken=\(pending.transferToken) offset=\(pending.offset)")

        // Compute destination path preserving folder structure
        let destPath = computeDestPath(for: pending.filename, username: pending.username)
        let filename = destPath.lastPathComponent

        logger.info("Receiving file to: \(destPath.path)")

        do {
            // Stop the normal message receive loop
            await connection.stopReceiving()

            // CRITICAL: Per SoulSeek protocol, after PeerInit the DOWNLOADER must send:
            // 1. Transfer token (uint32, 4 bytes) - identifies this transfer
            // 2. File offset (uint64, 8 bytes) - where to start in the file (usually 0)
            // Then the uploader sends raw file data

            var handshakeData = Data()
            handshakeData.appendUInt32(pending.transferToken)
            handshakeData.appendUInt64(pending.offset)

            print("📤 Sending file transfer handshake: token=\(pending.transferToken) offset=\(pending.offset)")
            try await connection.sendRaw(handshakeData)
            print("✅ File transfer handshake sent, now receiving file data...")

            // Receive file data using the PeerConnection
            try await receiveFileDataFromPeer(
                connection: connection,
                destPath: destPath,
                expectedSize: pending.size,
                transferId: pending.transferId
            )

            // Calculate transfer duration
            let duration = Date().timeIntervalSince(transferState.getTransfer(id: pending.transferId)?.startTime ?? Date())

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = pending.size
                t.localPath = destPath
            }

            logger.info("Download complete: \(filename) -> \(destPath.path)")
            ActivityLog.shared.logDownloadCompleted(filename: filename)

            // Record in statistics
            print("📊 Recording download stats: \(filename), size=\(pending.size), duration=\(duration)")
            if let stats = statisticsState {
                stats.recordTransfer(
                    filename: filename,
                    username: pending.username,
                    size: pending.size,
                    duration: duration,
                    isDownload: true
                )
                print("📊 Stats recorded! Downloads: \(stats.filesDownloaded), Total: \(stats.totalDownloaded)")
            } else {
                print("❌ statisticsState is nil!")
            }

            // Clean up the original download tracking
            pendingDownloads.removeValue(forKey: pending.downloadToken)

        } catch {
            logger.error("File transfer failed: \(error.localizedDescription)")
            print("❌ File transfer failed: \(error)")
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingDownloads.removeValue(forKey: pending.downloadToken)
        }
    }

    /// Receive file data from a PeerConnection
    private func receiveFileDataFromPeer(
        connection: PeerConnection,
        destPath: URL,
        expectedSize: UInt64,
        transferId: UUID
    ) async throws {
        // Ensure parent directory exists
        let parentDir = destPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create parent directory \(parentDir.path): \(error)")
            print("❌ Failed to create directory: \(parentDir.path) - \(error)")
            throw DownloadError.cannotCreateFile
        }

        // Create file for writing
        let created = FileManager.default.createFile(atPath: destPath.path, contents: nil)
        if !created {
            logger.error("Failed to create file at \(destPath.path)")
            print("❌ FileManager.createFile failed at: \(destPath.path)")
        }

        guard let fileHandle = try? FileHandle(forWritingTo: destPath) else {
            logger.error("Failed to open file handle for \(destPath.path)")
            print("❌ Cannot open file handle for: \(destPath.path)")
            throw DownloadError.cannotCreateFile
        }

        var bytesReceived: UInt64 = 0
        let startTime = Date()

        logger.info("Receiving file data from peer, expected size: \(expectedSize) bytes")

        // Receive data in chunks - like nicotine+, we receive until connection closes
        // then check if we got enough bytes
        var lastDataTime = Date()
        let receiveTimeout: TimeInterval = 30  // 30 seconds without data = timeout

        receiveLoop: while true {
            // Check for timeout (no data received for too long)
            let timeSinceLastData = Date().timeIntervalSince(lastDataTime)
            if timeSinceLastData > receiveTimeout {
                logger.warning("Receive timeout after \(timeSinceLastData)s with no data")
                print("⚠️ Receive timeout - \(bytesReceived)/\(expectedSize) bytes received")
                break receiveLoop
            }

            // Receive with timeout
            let chunkResult: PeerConnection.FileChunkResult
            do {
                chunkResult = try await withThrowingTaskGroup(of: PeerConnection.FileChunkResult.self) { group in
                    group.addTask {
                        try await connection.receiveFileChunk()
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        return .connectionComplete  // Treat timeout as connection done
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
            } catch {
                logger.error("Receive error: \(error.localizedDescription)")
                break receiveLoop
            }

            switch chunkResult {
            case .data(let chunk), .dataWithCompletion(let chunk):
                if !chunk.isEmpty {
                    try fileHandle.write(contentsOf: chunk)
                    bytesReceived += UInt64(chunk.count)
                    lastDataTime = Date()  // Reset timeout

                    // Update progress
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Int64(Double(bytesReceived) / elapsed) : 0

                    await MainActor.run { [transferState] in
                        transferState?.updateTransfer(id: transferId) { t in
                            t.bytesTransferred = bytesReceived
                            t.speed = speed
                        }
                    }
                }

                // If this was the final chunk with completion signal, exit loop
                if case .dataWithCompletion = chunkResult {
                    logger.info("Connection complete with final data, bytesReceived=\(bytesReceived)")
                    break receiveLoop
                }

                // If we've received expected bytes, we're done (like nicotine+)
                if bytesReceived >= expectedSize {
                    logger.info("Received all expected bytes: \(bytesReceived)/\(expectedSize)")
                    break receiveLoop
                }

            case .connectionComplete:
                // Connection closed - drain any remaining buffer
                let remainingBuffer = await connection.getFileTransferBuffer()
                if !remainingBuffer.isEmpty {
                    try fileHandle.write(contentsOf: remainingBuffer)
                    bytesReceived += UInt64(remainingBuffer.count)
                    print("📁 Wrote \(remainingBuffer.count) remaining buffered bytes")
                }
                logger.info("Connection closed, bytesReceived=\(bytesReceived)")
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

        print("📏 File verification: expected=\(expectedSize), received=\(bytesReceived), disk=\(actualSize)")

        // Like nicotine+: Accept if we received >= expected bytes
        // The file is complete when bytesReceived >= expectedSize (connection closes after sending all data)
        if expectedSize > 0 && actualSize >= expectedSize {
            logger.info("Download complete: received \(actualSize) bytes (expected \(expectedSize))")
            print("✅ Download complete: \(actualSize) >= \(expectedSize) bytes")
        } else if expectedSize == 0 && actualSize > 0 {
            // Expected size was 0 (parsing issue) but we got data - accept it
            logger.warning("Expected size was 0 but received \(actualSize) bytes - accepting")
            print("⚠️ Expected size was 0, accepting \(actualSize) bytes")
        } else if actualSize < expectedSize && expectedSize > 0 {
            // Got less than expected - this is an incomplete transfer
            let percentComplete = Double(actualSize) / Double(expectedSize) * 100
            logger.error("Incomplete transfer: \(actualSize)/\(expectedSize) bytes (\(String(format: "%.1f", percentComplete))%)")
            print("❌ Incomplete: \(actualSize)/\(expectedSize) bytes (\(String(format: "%.1f", percentComplete))%)")
            throw DownloadError.incompleteTransfer(expected: expectedSize, actual: actualSize)
        }

        await connection.disconnect()
        logger.info("File transfer complete and verified: \(actualSize) bytes received")
        print("✅ File transfer COMPLETE: \(destPath.lastPathComponent) (\(actualSize) bytes)")
    }

    // MARK: - PierceFirewall Handling (Indirect Connections)

    /// Called when a peer sends PierceFirewall - they're connecting to us after we sent CantConnectToPeer
    func handlePierceFirewall(token: UInt32, connection: PeerConnection) async {
        print("🔓 handlePierceFirewall: token=\(token)")

        // Find pending download by token
        guard let pending = pendingDownloads[token] else {
            print("⚠️ No pending download for PierceFirewall token \(token)")
            logger.debug("No pending download for PierceFirewall token \(token)")
            return
        }

        guard let networkClient else {
            print("❌ NetworkClient is nil in handlePierceFirewall")
            return
        }

        logger.info("PierceFirewall matched to pending download: \(pending.filename)")
        print("✅ PierceFirewall matched: \(pending.filename) from \(pending.username)")

        // Store the connection
        pendingDownloads[token]?.peerConnection = connection

        // Now send PeerInit + QueueDownload and wait for transfer
        // Per protocol: After indirect connection established, we still need to send PeerInit to identify ourselves
        do {
            // Send PeerInit FIRST - identifies us to the peer (token=0 for P connections)
            try await connection.sendPeerInit(username: networkClient.username)
            print("📤 Sent PeerInit via PierceFirewall connection")

            // Set up callback BEFORE sending QueueDownload to avoid race condition
            await setupTransferRequestCallback(token: token, connection: connection)

            try await connection.queueDownload(filename: pending.filename)
            print("📤 Sent QueueDownload via PierceFirewall connection for \(pending.filename)")
            logger.info("Sent QueueDownload via PierceFirewall connection")

            await waitForTransferResponse(token: token)
        } catch {
            logger.error("Failed to queue download via PierceFirewall: \(error.localizedDescription)")
            print("❌ Failed to queue download via PierceFirewall: \(error)")
            transferState?.updateTransfer(id: pending.transferId) { t in
                t.status = .failed
                t.error = error.localizedDescription
            }
            pendingDownloads.removeValue(forKey: token)
        }
    }

    // MARK: - Upload Denied/Failed Handling

    /// Called when peer denies our download request
    func handleUploadDenied(filename: String, reason: String) {
        print("🚫 handleUploadDenied: \(filename) - \(reason)")

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
        print("❌ handleUploadFailed: \(filename)")

        // Find pending download by filename
        guard let (token, pending) = pendingDownloads.first(where: { $0.value.filename == filename }) else {
            logger.debug("No pending download for failed file: \(filename)")
            return
        }

        logger.warning("Upload failed for \(filename)")

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "Upload failed on peer side"
        }

        pendingDownloads.removeValue(forKey: token)
    }
}
