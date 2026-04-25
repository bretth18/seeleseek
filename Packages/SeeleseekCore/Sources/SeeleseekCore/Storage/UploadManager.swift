import Foundation
import Network
import os
import Synchronization

/// Manages upload queue and file transfers to peers
@Observable
@MainActor
public final class UploadManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "UploadManager")

    // MARK: - Dependencies
    private weak var networkClient: NetworkClient?
    private weak var transferState: (any TransferTracking)?
    private weak var shareManager: ShareManager?
    private weak var statisticsState: (any StatisticsRecording)?

    // MARK: - Upload Queue
    private var uploadQueue: [QueuedUpload] = []
    private var activeUploads: [UUID: ActiveUpload] = [:]
    private var pendingTransfers: [UInt32: PendingUpload] = [:]  // token -> pending
    /// Per-token timeout for "peer didn't reply to TransferRequest". Cancelled
    /// by handleTransferResponse so the timer doesn't fire after the response
    /// arrives — without this, the same `pendingTransfers[token]` entry that
    /// gets re-registered for PierceFirewall handling would be falsely
    /// flagged as a no-response timeout 60s after the original TransferRequest.
    private var transferResponseTimeouts: [UInt32: Task<Void, Never>] = [:]

    // Configuration
    public private(set) var maxConcurrentUploads = 5
    public var maxQueuedPerUser = 50  // Max files queued per user (nicotine+ default)
    public var uploadSpeedLimit: Int64? = nil  // bytes per second, nil = unlimited

    /// Update the concurrent-upload cap. If the cap grew, kick `processQueue()`
    /// so waiting uploads can pick up the newly freed slots without having to
    /// wait for the next QueueUpload / TransferResponse to arrive.
    public func setMaxConcurrentUploads(_ value: Int) {
        let clamped = max(1, value)
        guard clamped != maxConcurrentUploads else { return }
        let grew = clamped > maxConcurrentUploads
        maxConcurrentUploads = clamped
        logger.info("maxConcurrentUploads set to \(clamped)")
        if grew {
            Task { await self.processQueue() }
        }
    }

    /// Highest valid upload-speed sample observed this session, in B/s.
    /// Used to avoid overwriting our server-side profile speed with noisy
    /// samples (small files, throttled peers, TCP slow-start). Session-only
    /// by design — next good upload after a restart re-establishes it.
    private var peakReportedSpeed: UInt32 = 0

    // MARK: - Retry Configuration

    /// Backoff schedule mirrors `DownloadManager.retryDelays`. Length sets
    /// `maxRetries`; after `maxRetries` attempts the upload is left
    /// permanently `.failed` (the user can still retry manually).
    private let retryDelays: [TimeInterval] = [30, 120, 600, 1800]
    private var maxRetries: Int { retryDelays.count }
    /// Sleeping retry tasks keyed by transferId. Cancelled when the user
    /// takes the row out of a retriable state (cancel, remove, manual retry,
    /// clear failed) so the Task doesn't wake up to 30 min later and stomp
    /// a row that has moved on. The status guard inside the Task already
    /// makes the no-op safe; this just stops the wasted sleep.
    private var pendingRetries: [UUID: Task<Void, Never>] = [:]

    /// Called to check if an upload should be allowed (checks blocklist + leech status)
    /// Set by AppState to delegate to SocialState
    public var uploadPermissionChecker: ((String) -> Bool)?

    // MARK: - Types

    public struct QueuedUpload: Identifiable {
        public let id = UUID()
        public let username: String
        public let filename: String
        public let localPath: String
        public let size: UInt64
        public let queuedAt: Date
        /// Set on retries so `startUpload` reuses the original Transfer
        /// record instead of allocating a fresh one. Without this, every
        /// auto-retry leaves the original row stuck at `.queued` and
        /// spawns a duplicate upload row, polluting persisted history.
        /// Nil for fresh QueueUpload requests from a peer.
        public let existingTransferId: UUID?
        // We deliberately do NOT cache a PeerConnection here. The cached
        // connection is the one the peer used at the moment of QueueUpload;
        // by the time we get around to broadcasting queue positions or
        // starting the upload it's often dead, and `send()` fails silently
        // on a closed connection. Resolve via
        // `peerConnectionPool.getConnectionForUser(username)` at every send
        // site instead. Same fix as the DownloadManager refactor.

        public init(
            username: String,
            filename: String,
            localPath: String,
            size: UInt64,
            queuedAt: Date,
            existingTransferId: UUID? = nil
        ) {
            self.username = username
            self.filename = filename
            self.localPath = localPath
            self.size = size
            self.queuedAt = queuedAt
            self.existingTransferId = existingTransferId
        }
    }

    public struct ActiveUpload {
        public let transferId: UUID
        public let username: String
        public let filename: String
        public let localPath: String
        public let size: UInt64
        public let token: UInt32
        public var bytesSent: UInt64 = 0
        public var startTime: Date?
    }

    public struct PendingUpload {
        public let transferId: UUID
        public let username: String
        public let filename: String
        public let localPath: String
        public let size: UInt64
        public let token: UInt32
        // No cached PeerConnection — see QueuedUpload's docstring for why.
    }

    // MARK: - Errors

    public enum UploadError: Error, LocalizedError {
        case fileNotFound
        case fileNotShared
        case cannotReadFile
        case connectionFailed
        case peerRejected
        case timeout

        public var errorDescription: String? {
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

    public init() {}

    public func configure(networkClient: NetworkClient, transferState: any TransferTracking, shareManager: ShareManager, statisticsState: any StatisticsRecording) {
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
        networkClient.onTransferResponse = { [weak self] token, allowed, _, reason, connection in
            guard let self else { return }
            _ = await MainActor.run {
                Task {
                    await self.handleTransferResponse(token: token, allowed: allowed, reason: reason, connection: connection)
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

        // Peer-address resolution for uploads now uses
        // `NetworkClient.getPeerAddress(for:timeout:)` directly inside
        // `handleTransferResponse` (await-style with timeout). The previous
        // addPeerAddressHandler + pendingAddressLookups dance was a manual
        // re-implementation of the same coalescing logic.

        logger.info("UploadManager configured")
    }

    // MARK: - Queue Management

    /// Get current queue position for a file (1-based, 0 = not queued)
    public func getQueuePosition(for filename: String, username: String) -> UInt32 {
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
                    try await connection.sendUploadDenied(filename: filename, reason: "File not shared.")
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
        guard let pool = networkClient?.peerConnectionPool else { return }
        for (index, upload) in uploadQueue.enumerated() {
            let position = UInt32(index + 1)
            // Resolve the live connection at send time. Caching the one the
            // peer used at QueueUpload meant broadcasts often went to a dead
            // connection and the failure was silent (logged at .debug).
            // If the peer has no live connection, skip — they'll reconnect
            // and re-request position when they want it.
            guard let connection = await pool.getConnectionForUser(upload.username) else {
                logger.debug("No live connection to \(upload.username) — skipping queue-position broadcast")
                continue
            }
            do {
                try await connection.sendPlaceInQueue(filename: upload.filename, place: position)
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
                try await connection.sendUploadDenied(filename: filename, reason: "File not shared.")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Visibility gate. Buddy-only files must not be served to
        // non-buddies even if they know the sharedPath — a peer could
        // know the path from a previous session (when they were a
        // buddy, or when the folder was public), and without this
        // gate the shares-reply filter is one QueueUpload message away
        // from being bypassed. Present the same "not shared" response
        // we use for unknown files so non-buddies can't probe for
        // buddy-only path existence.
        if indexedFile.visibility == .buddies {
            let isBuddy = networkClient?.isBuddyChecker?(username) ?? false
            if !isBuddy {
                logger.info("QueueUpload denied (buddy-only file, non-buddy requester): \(username) \(filename)")
                ActivityLogger.shared?.logInfo(
                    "Denied upload of buddy-only file to \(username)",
                    detail: filename
                )
                do {
                    try await connection.sendUploadDenied(filename: filename, reason: "File not shared.")
                } catch {
                    logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
                }
                return
            }
        }

        // Check if file exists locally
        guard FileManager.default.fileExists(atPath: indexedFile.localPath) else {
            logger.warning("Local file missing: \(indexedFile.localPath)")
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "File not shared.")
            } catch {
                logger.error("Failed to send UploadDenied: \(error.localizedDescription)")
            }
            return
        }

        // Check if upload is allowed (blocklist + leech detection)
        if let checker = uploadPermissionChecker, !checker(username) {
            logger.info("Upload denied for \(username): blocked or leech")
            ActivityLogger.shared?.logInfo(
                "Denied upload request from \(username)",
                detail: filename
            )
            do {
                try await connection.sendUploadDenied(filename: filename, reason: "File not shared.")
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
                try await connection.sendUploadDenied(filename: filename, reason: "Too many files")
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

        // Reuse the existing transfer record on retries; otherwise create
        // a fresh one. Without this, a retry spawns a duplicate row and
        // strands the original at `.queued`.
        let transferId: UUID
        if let existing = upload.existingTransferId {
            transferId = existing
            transferState?.updateTransfer(id: existing) { t in
                t.status = .connecting
                t.error = nil
                t.bytesTransferred = 0
                t.startTime = nil
                t.speed = 0
            }
        } else {
            let transfer = Transfer(
                username: upload.username,
                filename: upload.filename,
                size: upload.size,
                direction: .upload,
                status: .connecting
            )
            transferState?.addUpload(transfer)
            transferId = transfer.id
        }

        // Track pending transfer
        let pending = PendingUpload(
            transferId: transferId,
            username: upload.username,
            filename: upload.filename,
            localPath: upload.localPath,
            size: upload.size,
            token: token
        )
        pendingTransfers[token] = pending

        logger.info("Starting upload: \(upload.filename) to \(upload.username), token=\(token)")

        // Always look up the connection fresh — the one the peer used to
        // send QueueUpload may have died waiting in our queue.
        guard let connection = await networkClient?.peerConnectionPool.getConnectionForUser(upload.username) else {
            logger.warning("No active connection to \(upload.username), upload cannot proceed")
            failUpload(transferId: transferId, error: "Peer disconnected")
            pendingTransfers.removeValue(forKey: token)
            await processQueue()
            return
        }

        // Send TransferRequest (direction=1=upload, meaning we're ready to upload to them)
        do {
            try await connection.sendTransferRequest(
                direction: .upload,
                token: token,
                filename: upload.filename,
                size: upload.size
            )
            logger.info("Sent TransferRequest for \(upload.filename)")

            // Schedule a 60s "no TransferResponse" timeout. The Task is
            // tracked in `transferResponseTimeouts` so handleTransferResponse
            // can cancel it when the peer replies — otherwise the timer
            // would fire later and stomp the entry that we re-register for
            // PierceFirewall handling.
            transferResponseTimeouts[token] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                self.transferResponseTimeouts.removeValue(forKey: token)
                if let pending = self.pendingTransfers.removeValue(forKey: token) {
                    self.failUpload(transferId: pending.transferId, error: "Timeout waiting for peer response")
                }
            }
        } catch {
            logger.error("Failed to send TransferRequest: \(error.localizedDescription)")
            failUpload(transferId: transferId, error: error.localizedDescription)
            pendingTransfers.removeValue(forKey: token)
            transferResponseTimeouts.removeValue(forKey: token)?.cancel()
        }
    }

    /// Handle TransferResponse from peer (they accepted or rejected our upload offer).
    ///
    /// Rejection semantics per protocol: `reason` carries a short string
    /// distinguishing recoverable states ("Queued", where the peer accepted
    /// the request and will follow up with PlaceInQueueReply/QueueUpload)
    /// from hard rejections ("Cancelled", arbitrary errors). We map these to
    /// the right TransferStatus so the row doesn't misleadingly show as
    /// Failed when the peer is actually in the process of queuing us.
    private func handleTransferResponse(token: UInt32, allowed: Bool, reason: String?, connection: PeerConnection) async {
        // Cancel the no-response timeout — peer replied. Without this, the
        // timer would fire 60s after our original TransferRequest and stomp
        // the same `pendingTransfers[token]` entry that we re-register
        // below for PierceFirewall handling.
        transferResponseTimeouts.removeValue(forKey: token)?.cancel()

        guard let pending = pendingTransfers.removeValue(forKey: token) else {
            logger.debug("No pending upload for token \(token)")
            return
        }

        if !allowed {
            let detail = reason ?? "Peer rejected transfer"
            let status = Self.status(forReject: reason)
            logger.warning("Peer rejected upload for \(pending.filename): \(detail) (→ \(status.rawValue))")
            // `.queued` (peer accepted, queueing) and `.cancelled` (peer
            // explicit cancel) are not failures — keep them as-is. Only
            // route true `.failed` rejects through `failUpload` so the
            // retry classifier sees the reason text.
            if status == .failed {
                failUpload(transferId: pending.transferId, error: detail)
            } else {
                transferState?.updateTransfer(id: pending.transferId) { t in
                    t.status = status
                    t.error = detail
                }
            }
            return
        }

        logger.info("Peer accepted upload for \(pending.filename), opening F connection")

        // Peer accepted - now we need to open an F (file) connection to their listen port
        guard let networkClient else {
            logger.error("NetworkClient not available")
            return
        }

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .transferring
            t.startTime = Date()
        }

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

        // Send ConnectToPeer (type "F") first so the server forwards our
        // connection request to the peer in parallel; if our direct
        // connection fails the peer will connect back to us via PierceFirewall.
        await networkClient.sendConnectToPeer(token: token, username: pending.username, connectionType: "F")
        logger.debug("Sent ConnectToPeer to server for upload to \(pending.username)")

        // Re-register pending transfer so PierceFirewall can find it. (The
        // 60s response-timeout above is already cancelled, so it can't fire
        // and falsely fail this re-registration.)
        pendingTransfers[token] = pending
        logger.debug("Registered pending upload token=\(token) for PierceFirewall")

        // Resolve the peer's listen port (NOT the ephemeral source port from
        // the existing P-connection) and open the direct F-connection.
        let ip: String
        let port: Int
        do {
            // F (file) connections use raw TCP with no peer-message framing after
            // the opening PierceFirewall, so the obfuscated P-port is not used
            // here — upload to the peer's advertised plain listen port.
            let address = try await networkClient.getPeerAddress(for: pending.username, timeout: .seconds(10))
            ip = address.ip
            port = address.port
        } catch {
            logger.error("Failed to get peer address: \(error.localizedDescription)")
            failUpload(transferId: pending.transferId, error: "Failed to connect to peer")
            activeUploads.removeValue(forKey: pending.transferId)
            pendingTransfers.removeValue(forKey: token)
            return
        }

        logger.info("Received peer address for upload to \(pending.username): \(ip):\(port)")

        guard port > 0 else {
            logger.warning("Invalid port for \(pending.username)")
            failUpload(transferId: pending.transferId, error: "Could not get peer address")
            activeUploads.removeValue(forKey: pending.transferId)
            pendingTransfers.removeValue(forKey: token)
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
            failUpload(transferId: pending.transferId, error: "Invalid peer port")
            activeUploads.removeValue(forKey: pending.transferId)
            return
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: nwPort
        )

        // Use an ephemeral source port (bindTo: nil). Pinning to listenPort
        // collides with concurrent F-connections to the same peer on the
        // same 4-tuple (POSIX EEXIST/17) and offers no NAT benefit.
        let attemptResult = await Self.attemptFileConnect(to: endpoint, bindTo: nil)

        let connected: Bool
        let connection: NWConnection
        switch attemptResult {
        case .ready(let conn):
            connected = true
            connection = conn
        case .failed(let conn), .bindFailed(let conn):
            connected = false
            connection = conn
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
                        self.failUpload(transferId: stale.transferId, error: "Peer connection timeout (firewall)")
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

        // Direct connection succeeded -- remove from pendingTransfers so PierceFirewall path
        // doesn't also start a transfer, and timeout doesn't mark it as failed
        pendingTransfers.removeValue(forKey: token)

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
            failUpload(transferId: pending.transferId, error: "Failed to initiate file transfer")
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
            failUpload(transferId: pending.transferId, error: "Failed to start file transfer")
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
            failUpload(transferId: transferId, error: "Cannot read file")
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
                failUpload(transferId: transferId, error: "Failed to seek in file")
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
                networkClient?.peerConnectionPool.recordBytesSent(UInt64(chunk.count))

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

            // Measure transfer duration at the moment the last application
            // byte has been handed to TCP — the 500 ms flush sleep below is
            // transport teardown, not transfer time, so must not inflate the
            // denominator.
            let duration = Date().timeIntervalSince(startTime)

            // Give TCP stack time to flush any remaining buffered data.
            // This is important because cancel() might tear down the
            // connection before TCP sends all data.
            try? await Task.sleep(for: .milliseconds(500))

            logger.info("Upload complete: \(bytesSent) bytes sent in \(String(format: "%.1f", duration))s")

            let filename = (filePath as NSString).lastPathComponent
            let uploadUsername = activeUploads[transferId]?.username ?? "unknown"

            // Report upload speed to server (filtered, peak-tracked)
            await reportUploadSpeedIfValid(bytesTransferred: bytesSent - offset, elapsed: duration)

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
            ActivityLogger.shared?.logUploadCompleted(filename: filename)

            // Process queue for next upload
            await processQueue()

        } catch {
            logger.error("Upload failed: \(error.localizedDescription)")

            await MainActor.run { [self] in
                self.failUpload(transferId: transferId, error: error.localizedDescription)
            }

            // Notify peer so they can re-queue
            if let active = activeUploads[transferId] {
                await sendUploadFailedToPeer(username: active.username, filename: active.filename)
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

    // MARK: - Upload Speed Reporting

    /// Report a completed upload's throughput to the Soulseek server, but only
    /// if the sample is trustworthy AND exceeds the best sample we've seen
    /// this session.
    ///
    /// Why: the server's `SendUploadSpeed` (code 121) simply overwrites the
    /// profile's stored value. Reporting every completed file — including
    /// small files dominated by TCP slow-start and uploads throttled by a
    /// slow peer — silently ratchets the displayed speed downward. Peak
    /// tracking + noise filtering ensures the profile reflects our actual
    /// sustained throughput on representative transfers.
    ///
    /// Filters:
    /// - `bytesTransferred < 1 MiB`: dominated by connection setup and TCP
    ///   slow-start, not a measurement of sustained throughput.
    /// - `elapsed < 2 s`: too short for the transport to reach steady state.
    /// - `sample > 1 GiB/s`: implausible on any consumer uplink — almost
    ///   certainly loopback or a measurement bug. Rejected to protect the
    ///   peak from getting stuck at an unreachable value.
    private func reportUploadSpeedIfValid(bytesTransferred: UInt64, elapsed: TimeInterval) async {
        let minBytes: UInt64 = 1_048_576                    // 1 MiB
        let minElapsed: TimeInterval = 2.0                  // seconds
        let maxPlausibleSpeed: Double = 1_073_741_824       // 1 GiB/s

        guard bytesTransferred >= minBytes, elapsed >= minElapsed else {
            logger.debug("Upload speed sample rejected: bytes=\(bytesTransferred) elapsed=\(elapsed)")
            return
        }

        let sample = Double(bytesTransferred) / elapsed
        guard sample > 0, sample < maxPlausibleSpeed else {
            logger.debug("Upload speed sample rejected: implausible rate \(sample) B/s")
            return
        }

        let sampleU32 = UInt32(sample)
        guard sampleU32 > peakReportedSpeed else {
            logger.debug("Upload speed sample \(sampleU32) B/s ≤ session peak \(self.peakReportedSpeed), not reporting")
            return
        }

        peakReportedSpeed = sampleU32
        logger.info("New upload-speed peak this session: \(sampleU32) B/s — reporting to server")
        try? await networkClient?.reportUploadSpeed(sampleU32)
    }

    // MARK: - Public API

    /// Get current upload queue
    public var queuedUploads: [QueuedUpload] { uploadQueue }

    /// Get number of active uploads
    public var activeUploadCount: Int { activeUploads.count }

    /// Number of items waiting in queue
    public var queueDepth: Int { uploadQueue.count }

    /// Summary string for upload slots (e.g. "2/3")
    public var slotsSummary: String { "\(activeUploads.count)/\(maxConcurrentUploads)" }

    /// Cancel a queued upload
    public func cancelQueuedUpload(_ id: UUID) {
        uploadQueue.removeAll { $0.id == id }
    }

    /// Cancel an active upload
    public func cancelActiveUpload(_ transferId: UUID) async {
        if let upload = activeUploads.removeValue(forKey: transferId) {
            // "Cancelled" is a terminal reason in the retry classifier, so
            // routing through `failUpload` correctly suppresses any retry.
            cancelRetry(transferId: transferId)
            failUpload(transferId: transferId, error: "Cancelled")
            logger.info("Cancelled upload: \(upload.filename)")
        }
    }

    // MARK: - PierceFirewall Handling

    /// Check if we have a pending upload for this token
    public func hasPendingUpload(token: UInt32) -> Bool {
        return pendingTransfers[token] != nil
    }

    /// Handle CantConnectToPeer — server tells us the peer couldn't reach us, fail the upload
    public func handleCantConnectToPeer(token: UInt32) {
        guard let pending = pendingTransfers.removeValue(forKey: token) else { return }
        logger.warning("CantConnectToPeer for upload \(pending.filename) — peer unreachable")
        failUpload(transferId: pending.transferId, error: "Peer unreachable (firewall)")
        activeUploads.removeValue(forKey: pending.transferId)
        Task { await processQueue() }
    }

    /// Handle PierceFirewall for upload (indirect connection from peer)
    public func handlePierceFirewall(token: UInt32, connection: PeerConnection) async {
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
            failUpload(transferId: pending.transferId, error: error.localizedDescription)
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
            failUpload(transferId: transferId, error: "File not found")
            activeUploads.removeValue(forKey: transferId)
            return
        }

        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            logger.error("Could not open file: \(filePath)")
            failUpload(transferId: transferId, error: "Could not open file")
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
            failUpload(transferId: transferId, error: "Could not seek in file")
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

            // Report upload speed to server (filtered, peak-tracked)
            await reportUploadSpeedIfValid(bytesTransferred: bytesTransferred, elapsed: elapsed)

            transferState?.updateTransfer(id: transferId) { t in
                t.status = .completed
                t.bytesTransferred = bytesSent
                t.error = nil
            }

            activeUploads.removeValue(forKey: transferId)
            ActivityLogger.shared?.logUploadCompleted(filename: (filePath as NSString).lastPathComponent)

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

            failUpload(transferId: transferId, error: error.localizedDescription)

            // Notify peer so they can re-queue
            if let active = activeUploads[transferId] {
                await sendUploadFailedToPeer(username: active.username, filename: active.filename)
            }

            activeUploads.removeValue(forKey: transferId)
            await processQueue()
        }
    }

    /// Send UploadFailed to peer over a P connection so they can re-queue the download
    private func sendUploadFailedToPeer(username: String, filename: String) async {
        guard let pool = networkClient?.peerConnectionPool else { return }
        if let pConn = await pool.getConnectionForUser(username) {
            do {
                try await pConn.sendUploadFailed(filename: filename)
                logger.info("Sent UploadFailed to \(username) for \(filename)")
            } catch {
                logger.debug("Could not send UploadFailed to \(username): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Retry Logic

    /// Classify an upload-failure reason as retriable. Mirrors
    /// `DownloadManager.isRetriableError` so the two halves of the transfer
    /// system stay in sync — same backoff, same terminal patterns. Bare
    /// stem `cancel` matches both British/American spellings; `not shared`
    /// catches our own `sendUploadDenied` reasons coming back round when
    /// the peer rejects.
    public static func isRetriableError(_ error: String?) -> Bool {
        guard let lowered = error?.lowercased(), !lowered.isEmpty else {
            return false
        }
        let terminalPatterns = [
            "cancel",
            "denied",
            "not shared",
            "not available",
            "file not found",
            "too many",
        ]
        for pattern in terminalPatterns where lowered.contains(pattern) {
            return false
        }
        return true
    }

    private static func formatRetryDelay(_ delay: TimeInterval) -> String {
        let seconds = Int(delay)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    /// Single point where an upload transitions to `.failed`. Sets the row's
    /// status + error, then schedules an automatic retry if the reason is
    /// classified retriable and we haven't hit `maxRetries`. Caller still
    /// owns cleanup (`pendingTransfers` / `activeUploads`); retry re-enters
    /// via `uploadQueue` + `processQueue()`, not via those dictionaries.
    private func failUpload(transferId: UUID, error: String) {
        guard let transfer = transferState?.getTransfer(id: transferId) else {
            logger.warning("failUpload: no transfer for \(transferId)")
            return
        }
        let currentRetryCount = transfer.retryCount
        transferState?.updateTransfer(id: transferId) { t in
            t.status = .failed
            t.error = error
        }
        guard Self.isRetriableError(error) else {
            logger.info("Upload \(transfer.filename) terminal-failed: \(error)")
            return
        }
        guard currentRetryCount < maxRetries else {
            logger.info("Upload \(transfer.filename) hit max retries (\(self.maxRetries))")
            return
        }
        scheduleUploadRetry(
            transferId: transferId,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size,
            retryCount: currentRetryCount
        )
    }

    /// Schedule automatic retry for a failed upload using `retryDelays`.
    private func scheduleUploadRetry(
        transferId: UUID,
        username: String,
        filename: String,
        size: UInt64,
        retryCount: Int
    ) {
        guard retryCount < self.maxRetries else { return }
        let delay = retryDelays[retryCount]
        logger.info("Scheduling upload retry #\(retryCount + 1) for \(filename) in \(delay)s")

        transferState?.updateTransfer(id: transferId) { t in
            t.error = "Retrying in \(Self.formatRetryDelay(delay))..."
        }

        // Cancel any prior retry Task before overwriting the dict slot —
        // the orphan would otherwise sleep on and could fire later.
        if let existing = pendingRetries.removeValue(forKey: transferId) {
            existing.cancel()
        }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.pendingRetries.removeValue(forKey: transferId)
                // Between schedule and wake the row may have completed
                // (a late TransferResponse landed), been cancelled, or
                // been re-queued manually. Only proceed if it's still
                // sitting in `.failed`.
                guard let current = self.transferState?.getTransfer(id: transferId),
                      current.status == .failed else {
                    self.logger.info("Skipping scheduled upload retry for \(filename): no longer in .failed state")
                    return
                }
                self.retryUploadInternal(
                    transferId: transferId,
                    username: username,
                    filename: filename,
                    size: size,
                    retryCount: retryCount + 1
                )
            }
        }
        pendingRetries[transferId] = task
    }

    /// Re-resolve the file via `ShareManager` and put it back on the queue.
    /// Shared by the scheduled-retry path and `retryFailedUpload`.
    ///
    /// Dedup is keyed on `transferId`, not `(username, filename)`: if THIS
    /// row is already queued/pending/active (a scheduled retry fired moments
    /// before a manual click, or vice versa) we just bail without touching
    /// the row state — the in-flight attempt will resolve it. Mutating to
    /// `.queued` *before* the dedup check (the previous shape) would strand
    /// the row at `.queued` because the in-flight attempt owns a different
    /// `pendingTransfers` token / `activeUploads` slot and never updates
    /// this transferId. A genuine `(username, filename)` duplicate with a
    /// different transferId is a separate row from the user's perspective
    /// and is intentionally not dedup'd here.
    private func retryUploadInternal(
        transferId: UUID,
        username: String,
        filename: String,
        size: UInt64,
        retryCount: Int
    ) {
        let alreadyDriven = uploadQueue.contains(where: { $0.existingTransferId == transferId })
            || pendingTransfers.values.contains(where: { $0.transferId == transferId })
            || activeUploads.keys.contains(transferId)
        if alreadyDriven {
            logger.debug("Upload retry skipped (transfer already in flight): \(filename)")
            return
        }

        // Re-resolve the share's `localPath` (not on the Transfer record).
        // Same lookup `handleQueueUpload` uses on first request. If the
        // file has been removed from shares between attempts, drop the
        // retry and leave the row terminal so it doesn't loop.
        guard let shareManager,
              let indexedFile = shareManager.fileIndex.first(where: { $0.sharedPath == filename }) else {
            logger.warning("Upload retry aborted, file no longer shared: \(filename)")
            transferState?.updateTransfer(id: transferId) { t in
                t.status = .failed
                t.error = "File no longer shared"
                t.retryCount = retryCount
            }
            return
        }

        logger.info("Retrying upload: \(filename) (attempt \(retryCount))")
        transferState?.updateTransfer(id: transferId) { t in
            t.status = .queued
            t.error = nil
            t.bytesTransferred = 0
            t.retryCount = retryCount
        }

        // existingTransferId routes startUpload to reuse this row instead
        // of allocating a new Transfer + addUpload, which would leave the
        // original behind in `.queued` forever.
        let queued = QueuedUpload(
            username: username,
            filename: filename,
            localPath: indexedFile.localPath,
            size: indexedFile.size,
            queuedAt: Date(),
            existingTransferId: transferId
        )
        uploadQueue.append(queued)
        Task { await self.processQueue() }
    }

    /// Manual retry from the Retry button. Drops any pending automatic
    /// retry, then re-runs `retryUploadInternal` immediately.
    public func retryFailedUpload(transferId: UUID) {
        guard let transfer = transferState?.getTransfer(id: transferId),
              transfer.direction == .upload else {
            return
        }
        // The Retry button calls `transferState.retryTransfer(id:)` first,
        // which sets `.queued` — so accept `.failed`, `.cancelled`, and
        // `.queued` here rather than gating on `.failed` only.
        let eligible: Set<Transfer.TransferStatus> = [.failed, .cancelled, .queued]
        guard eligible.contains(transfer.status) else { return }
        cancelRetry(transferId: transferId)
        retryUploadInternal(
            transferId: transferId,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size,
            retryCount: transfer.retryCount + 1
        )
    }

    /// Resume retriable failed uploads from a prior session.
    ///
    /// `pendingRetries` is in-memory, so a quit during the 30-min backoff
    /// window leaves the persisted `.failed` row stranded. This is the
    /// upload-side counterpart to `DownloadManager.resumeDownloadsOnConnect`.
    /// Called from `LoginView` once the server connection is `.connected`.
    ///
    /// `ShareManager.fileIndex` may still be empty when this fires (rescan
    /// runs async at app launch). Without coordinating with the rescan
    /// we'd see every retriable row as "File no longer shared" and mark
    /// it terminal, defeating the resume. So we wait for `isScanning ==
    /// false` before sweeping.
    public func resumeUploadsOnConnect() {
        guard let transferState else {
            logger.error("TransferState not configured for upload resume")
            return
        }

        let retriable = transferState.uploads.filter {
            $0.status == .failed
                && $0.direction == .upload
                && Self.isRetriableError($0.error)
        }
        guard !retriable.isEmpty else {
            logger.info("No uploads to resume on connect")
            return
        }

        logger.info("Resuming \(retriable.count) failed uploads on connect")

        // Reset the persisted retry counter — these are stale from a
        // prior session, so each row gets a fresh four-attempt budget.
        // Mirrors `resumeDownloadsOnConnect`.
        for transfer in retriable {
            transferState.updateTransfer(id: transfer.id) { t in
                t.retryCount = 0
            }
        }

        // If shareManager is still rescanning, wait. Polling is enough
        // here — there's no rescan-complete callback today and the worst
        // case is one polling Task that exits on its own.
        Task { [weak self] in
            while let manager = self?.shareManager, manager.isScanning {
                try? await Task.sleep(for: .seconds(2))
            }
            guard let self else { return }
            await MainActor.run {
                // Stagger to avoid a connection storm. retryUploadInternal
                // is dedup-safe via transferId, so a duplicate trigger
                // (e.g. user reconnects twice fast) just no-ops.
                for (index, transfer) in retriable.enumerated() {
                    let delay = Double(index) * 0.5
                    Task {
                        if delay > 0 {
                            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                        }
                        await MainActor.run {
                            self.retryUploadInternal(
                                transferId: transfer.id,
                                username: transfer.username,
                                filename: transfer.filename,
                                size: transfer.size,
                                retryCount: 1
                            )
                        }
                    }
                }
            }
        }
    }

    /// Drop a sleeping retry Task. Called by `AppState` whenever the
    /// user takes the transfer out of a retriable state.
    public func cancelRetry(transferId: UUID) {
        if let task = pendingRetries.removeValue(forKey: transferId) {
            task.cancel()
            logger.info("Cancelled pending upload retry for \(transferId)")
        }
    }

    // MARK: - Test-only seams

    /// Inject a `TransferTracking` without going through `configure`. Used
    /// by retry-row-reuse tests to drive `retryUploadInternal` against a
    /// MockTransferTracking, mirroring `DownloadManager._setTransferStateForTest`.
    internal func _setTransferStateForTest(_ state: any TransferTracking) {
        self.transferState = state
    }

    internal func _setShareManagerForTest(_ manager: ShareManager) {
        self.shareManager = manager
    }

    /// Direct entry point for retry-internal tests. Real callers go through
    /// `failUpload` (auto) or `retryFailedUpload` (manual).
    internal func _retryUploadForTest(
        transferId: UUID,
        username: String,
        filename: String,
        size: UInt64,
        retryCount: Int
    ) {
        retryUploadInternal(
            transferId: transferId,
            username: username,
            filename: filename,
            size: size,
            retryCount: retryCount
        )
    }

    /// Read the in-memory upload queue (for assertions about
    /// `existingTransferId` routing).
    internal var _uploadQueueForTest: [QueuedUpload] { uploadQueue }

    /// Seed a pending entry to exercise the dedup branch of
    /// `retryUploadInternal` without driving a real handshake.
    internal func _seedPendingUploadForTest(_ pending: PendingUpload, token: UInt32) {
        pendingTransfers[token] = pending
    }

    /// Maps a TransferReply rejection `reason` string to the closest
    /// TransferStatus. Exposed for unit tests.
    static func status(forReject reason: String?) -> Transfer.TransferStatus {
        // Normalise for case-insensitive prefix matching so minor server
        // variants ("Queued.", "Queued\0") still classify correctly.
        let trimmed = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            .lowercased() ?? ""

        switch trimmed {
        case "queued":
            // Peer accepted the request and will follow up with queue
            // position / upload readiness. Not a failure.
            return .queued
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .failed
        }
    }
}

