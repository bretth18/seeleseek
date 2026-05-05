import Foundation
import Network
import os


/// Manages the download queue and file transfers
@Observable
@MainActor
public final class DownloadManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "DownloadManager")

    // MARK: - Dependencies
    private weak var networkClient: NetworkClient?
    private weak var transferState: (any TransferTracking)?
    private weak var statisticsState: (any StatisticsRecording)?
    private weak var uploadManager: UploadManager?
    private weak var settings: (any DownloadSettingsProviding)?

    // MARK: - Pending Downloads
    // Maps token to pending download info
    private var pendingDownloads: [UInt32: PendingDownload] = [:]

    // Maps username to pending file transfers (waiting for F connection)
    // Array-based to support multiple concurrent downloads from same user
    private var pendingFileTransfersByUser: [String: [PendingFileTransfer]] = [:]

    // MARK: - Post-Download Processing
    private var metadataReader: (any MetadataReading)?
    /// Directories that already have folder icons applied (avoid redundant work)
    private var iconAppliedDirs: Set<URL> = []

    // MARK: - Retry Configuration
    // Mixed ladder: a quick 10s first retry catches transient blips (TCP
    // resets, brief connectivity flaps, momentary peer slowness) without
    // making the user wait. Subsequent delays climb into minutes/hours
    // because Soulseek peer upload queues commonly drain on that timescale
    // — a retry too soon arrives before the queue has moved and gets
    // silently dropped from `pendingDownloads`.
    private let retryDelays: [TimeInterval] = [10, 30, 120, 600, 1800]  // 10s, 30s, 2m, 10m, 30m
    private var maxRetries: Int { retryDelays.count }
    private var pendingRetries: [UUID: Task<Void, Never>] = [:]  // Track retry tasks
    private var reQueueTimer: Task<Void, Never>?  // Periodic re-queue timer (60s)
    private var connectionRetryTimer: Task<Void, Never>?  // Retry failed connections (3 min)
    private var queuePositionTimer: Task<Void, Never>?  // Update queue positions (5 min)
    private var staleRecoveryTimer: Task<Void, Never>?  // Recover stale downloads (15 min)

    public struct PendingDownload {
        public let transferId: UUID
        public let username: String
        public let filename: String
        public var size: UInt64
        // We deliberately do NOT cache a PeerConnection here. The pool is the
        // single source of truth for live connections — caching one on the
        // pending entry leads to stale references when the original
        // connection dies between queueing the download and the peer
        // actually delivering its TransferRequest hours later. Look up the
        // current connection via `peerConnectionPool.getConnectionForUser`
        // at send time, or use the connection that delivered the event you
        // are reacting to.
        public var peerIP: String?       // Store peer IP for outgoing F connection
        public var peerPort: Int?        // Store peer port for outgoing F connection
        public var resumeOffset: UInt64 = 0  // For resuming partial downloads
    }

    // Track partial downloads for resume
    private var partialDownloads: [String: URL] = [:]  // filename -> partial file path

    public struct PendingFileTransfer {
        public let transferId: UUID
        public let username: String
        public let filename: String
        public let size: UInt64
        public let downloadToken: UInt32   // The original download token
        public let transferToken: UInt32   // The token from TransferRequest - sent on F connection
        public let offset: UInt64          // File offset (usually 0 for new downloads)
    }

    // MARK: - Errors

    public enum DownloadError: Error, LocalizedError {
        case invalidPort
        case connectionCancelled
        case connectionClosed
        case cannotCreateFile
        case timeout
        case incompleteTransfer(expected: UInt64, actual: UInt64)
        case verificationFailed

        public var errorDescription: String? {
            switch self {
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

    public init() {}

    public func configure(networkClient: NetworkClient, transferState: any TransferTracking, statisticsState: any StatisticsRecording, uploadManager: UploadManager, settings: any DownloadSettingsProviding, metadataReader: any MetadataReading) {
        self.networkClient = networkClient
        self.transferState = transferState
        self.statisticsState = statisticsState
        self.uploadManager = uploadManager
        self.settings = settings
        self.metadataReader = metadataReader

        // Connection establishment for downloads now goes through
        // NetworkClient.establishPeerConnection (which is shared with
        // browse/folder-contents/user-info). That means DownloadManager no
        // longer needs to react to GetPeerAddress responses or
        // incomingConnectionMatched — the establishment helper drives the
        // ConnectToPeer + direct/indirect race itself, so the previous
        // addPeerAddressHandler / onIncomingConnectionMatched registrations
        // are intentionally absent.

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
        networkClient.onUploadDenied = { [weak self] username, filename, reason in
            Task { @MainActor in
                self?.handleUploadDenied(username: username, filename: filename, reason: reason)
            }
        }

        // Set up callback for upload failed
        networkClient.onUploadFailed = { [weak self] username, filename in
            Task { @MainActor in
                self?.handleUploadFailed(username: username, filename: filename)
            }
        }

        // Set up callback for pool-level TransferRequests (arrives on connections not directly managed by us,
        // e.g. stale direct connections when PierceFirewall won the race, or fresh
        // incoming connections opened later when the peer's upload queue drains).
        networkClient.onTransferRequest = { [weak self] request, connection in
            Task { @MainActor in
                await self?.handlePoolTransferRequest(request, connection: connection)
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
    public func resumeDownloadsOnConnect() {
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

        // Refresh queue positions for any `.waiting` downloads right
        // away. Without this, positions are stale until the 5-minute
        // `queuePositionTimer` fires — so the user reconnects, sees
        // last-known position from minutes/hours ago, and has no way to
        // tell whether the queue has moved.
        Task { [weak self] in
            await self?.updateQueuePositions()
        }
    }

    /// Queue a file for download
    public func queueDownload(from result: SearchResult) {
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

        transferState.updateTransfer(id: transfer.id) { t in
            t.status = .connecting
        }

        pendingDownloads[token] = PendingDownload(
            transferId: transfer.id,
            username: transfer.username,
            filename: transfer.filename,
            size: transfer.size,
            peerIP: nil,
            peerPort: nil
        )

        do {
            // Single shared establishment dance — the same one browse,
            // folder-contents, and user-info use. Reuses an existing pool
            // connection if there is one; otherwise races direct vs
            // PierceFirewall. Concurrent calls for the same peer are
            // coalesced inside NetworkClient, so a folder-batch of N
            // downloads opens one connection, not N.
            let connection = try await networkClient.establishPeerConnection(for: transfer.username)
            await queueOnConnection(token: token, connection: connection)
        } catch {
            logger.error("startDownload(\(transfer.filename)): \(error.localizedDescription)")
            failPending(token: token, reason: error.localizedDescription)
        }
    }

    /// Send QueueDownload + PlaceInQueueRequest for a pending download on a
    /// live connection. Used by every "kick this download forward" call site
    /// (start, resume, periodic re-queue, salvage). Does NOT cache the
    /// connection — see `PendingDownload`'s docstring.
    private func queueOnConnection(token: UInt32, connection: PeerConnection) async {
        guard let pending = pendingDownloads[token] else { return }

        // Stash IP/port for the F-fallback path in handleTransferRequest →
        // initiateOutgoingFileConnection. Acceptable to cache here because
        // the F-fallback only runs within ~60s of TransferRequest arrival;
        // the peer's listen address is unlikely to change in that window.
        // (If they restart their app or move networks the F-fallback will
        // fail, the user gets a "Peer unreachable" and the retry path
        // re-resolves the address. Not catastrophic.)
        let info = connection.peerInfo
        if !info.ip.isEmpty, info.port > 0 {
            pendingDownloads[token]?.peerIP = info.ip
            pendingDownloads[token]?.peerPort = info.port
        }

        do {
            try await connection.queueDownload(filename: pending.filename)
            do {
                try await connection.sendPlaceInQueueRequest(filename: pending.filename)
            } catch {
                logger.warning("PlaceInQueueRequest(\(pending.filename)) failed: \(error.localizedDescription)")
            }
            logger.info("Queued \(pending.filename) with \(pending.username)")
            // After 60s with no PlaceInQueueReply or TransferRequest, flip
            // .connecting → .waiting so the UI doesn't claim we're still
            // mid-handshake when really we're sitting in the peer's queue.
            // Fire-and-forget — the Task sleeps 60s then exits; if the
            // manager is deinit'd in that window the [weak self] check
            // makes it a no-op. Per-startDownload, so a busy folder
            // download spawns N of these (acceptable; each is one Task,
            // sleeping with no allocations).
            Task { [weak self] in
                await self?.markWaitingIfStillConnecting(token: token)
            }
        } catch {
            logger.error("queueOnConnection(\(pending.filename)): \(error.localizedDescription)")
            failPending(token: token, reason: error.localizedDescription)
        }
    }

    private func markWaitingIfStillConnecting(token: UInt32) async {
        try? await Task.sleep(for: .seconds(60))
        guard let transferState, let pending = pendingDownloads[token] else { return }
        if let current = transferState.getTransfer(id: pending.transferId), current.status == .connecting {
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .waiting
            }
        }
    }

    /// Fail a pending download, remove its entry, and schedule a retry if
    /// eligible. Centralizes the error-handling that used to be sprinkled
    /// across startDownload/handlePeerAddress/queue paths.
    private func failPending(token: UInt32, reason: String) {
        guard let transferState, let pending = pendingDownloads[token] else { return }
        let currentRetryCount = transferState.getTransfer(id: pending.transferId)?.retryCount ?? 0
        transferState.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = reason
        }
        pendingDownloads.removeValue(forKey: token)
        if isRetriableError(reason) && currentRetryCount < maxRetries {
            scheduleRetry(
                transferId: pending.transferId,
                username: pending.username,
                filename: pending.filename,
                size: pending.size,
                retryCount: currentRetryCount
            )
        }
    }

    private func matchPendingDownload(for request: TransferRequest) -> UInt32? {
        Self.matchPendingDownload(request: request, pending: pendingDownloads)
    }

    /// Token → (username, filename). The earlier filename-only fallback
    /// could misroute when two different peers happened to be sending the
    /// same filename; it was only needed because `request.username` used
    /// to arrive empty on reused connections. `handlePoolTransferRequest`
    /// now normalizes the request with the connection's authoritative
    /// `peerInfo.username` before calling this, so the fallback is gone.
    static func matchPendingDownload(
        request: TransferRequest,
        pending: [UInt32: PendingDownload]
    ) -> UInt32? {
        if pending[request.token] != nil {
            return request.token
        }
        return pending.first { (_, p) in
            p.username == request.username && p.filename == request.filename
        }?.key
    }

    private func handlePoolTransferRequest(_ request: TransferRequest, connection: PeerConnection) async {
        // Authoritative peer username: prefer the live connection's peerInfo
        // over `request.username`, which is empty when the request arrives on
        // a connection whose handshake didn't carry a username (e.g. a peer
        // reusing a stream they identified on earlier).
        let peerUsername = request.username.isEmpty ? connection.peerInfo.username : request.username
        let normalizedRequest = request.username.isEmpty && !peerUsername.isEmpty
            ? TransferRequest(direction: request.direction, token: request.token, filename: request.filename, size: request.size, username: peerUsername)
            : request

        if let token = matchPendingDownload(for: normalizedRequest) {
            logger.info("Pool TransferRequest matched pending download: user=\(peerUsername) file=\(request.filename)")
            await handleTransferRequest(token: token, request: normalizedRequest, connection: connection)
            return
        }

        // Salvage path: the peer is offering a file we don't have in
        // pendingDownloads (cleared by app restart, or not yet registered
        // because resumeDownloadsOnConnect hasn't reached it). Walk
        // transferState for a matching user-intent entry and lift it into
        // pendingDownloads.
        //
        // Guards (added in response to review):
        //   1. Skip if any pendingDownload already exists for (peer, file).
        //      Without this, a peer that re-sends TransferRequest before our
        //      file-connection timeout fires would create a second pending
        //      entry with a fresh random token; both would race to receive
        //      the F-connection.
        //   2. Refuse to salvage `.failed` transfers — if the user (or our
        //      retry logic) gave up, accepting the peer's offer anyway
        //      would silently restart a download the user thought was dead.
        //      A retry will move it back to .queued via scheduleRetry/
        //      retryFailedDownload, at which point the next TransferRequest
        //      is salvageable again.
        //   3. Use stable tiebreak (oldest startTime) when transferState
        //      has multiple matching candidates. Pre-fix `first(where:)`
        //      depended on dictionary ordering.
        let alreadyPending = pendingDownloads.values.contains {
            $0.username == peerUsername && $0.filename == request.filename
        }
        // Salvage lookup goes through the `salvageableDownloadIDs` index on
        // TransferState (O(1)) rather than filtering all of `.downloads`.
        // Index already restricts to `.queued | .waiting | .connecting`, so
        // the status guard is redundant here but kept defensive. The old
        // `.min(by: startTime)` tiebreak is gone — the index is keyed by
        // `(user, filename)` so it holds at most one entry per key, which
        // was the effective behavior anyway.
        if !peerUsername.isEmpty,
           !alreadyPending,
           let transfer = transferState?.findSalvageableDownload(
               username: peerUsername,
               filename: request.filename
           ),
           transfer.direction == .download
        {
            let salvagedToken = UInt32.random(in: 1...UInt32.max)
            let info = connection.peerInfo
            pendingDownloads[salvagedToken] = PendingDownload(
                transferId: transfer.id,
                username: transfer.username,
                filename: transfer.filename,
                size: request.size,
                peerIP: info.ip.isEmpty ? nil : info.ip,
                peerPort: info.port > 0 ? info.port : nil
            )
            logger.info("Pool TransferRequest salvaged from transferState: user=\(peerUsername) file=\(request.filename) (token=\(salvagedToken))")
            await handleTransferRequest(token: salvagedToken, request: normalizedRequest, connection: connection)
            return
        }

        logger.info("Pool TransferRequest dropped — no pending or transferState match: user=\(peerUsername) file=\(request.filename)")
    }

    private func handleTransferRequest(token: UInt32, request: TransferRequest, connection: PeerConnection) async {
        guard let transferState, let pending = pendingDownloads[token] else { return }

        let directionStr = request.direction == .upload ? "upload" : "download"
        logger.info("Transfer request received: direction=\(directionStr) size=\(request.size) from \(request.username)")

        if request.direction == .upload {
            // Peer is ready to upload to us — send acceptance reply on the
            // connection that delivered THIS request, not on a cached one.
            // The cached one is often dead by the time the peer's queue
            // drains; replying on it surfaces as "send() - no connection!"
            // and the peer never gets our acceptance.
            do {
                try await connection.sendTransferReply(token: request.token, allowed: true)
                logger.info("Sent transfer reply accepting upload for token \(request.token)")
            } catch {
                logger.error("Failed to send transfer reply: \(error.localizedDescription)")
                pendingDownloads.removeValue(forKey: token)
                failDownload(
                    transferId: pending.transferId,
                    username: pending.username,
                    filename: pending.filename,
                    size: pending.size,
                    reason: "Failed to accept transfer: \(error.localizedDescription)"
                )
                return
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

            // Earliest unambiguous signal the peer is responding. Drop
            // any retry Task that may have been scheduled from a prior
            // timeout/failure so it can't wake up and stomp this
            // in-flight transfer back to `.queued` later.
            cancelRetry(transferId: pending.transferId)

            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .transferring
                t.startTime = Date()
                t.queuePosition = nil
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
                    self.failDownload(
                        transferId: pending.transferId,
                        username: pending.username,
                        filename: pending.filename,
                        size: pending.size,
                        reason: "File connection timeout"
                    )
                }
            }
        }
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

            // Use an ephemeral source port (bindTo: nil). Pinning to listenPort
            // collides with concurrent F-connections to the same peer on the
            // same 4-tuple (POSIX EEXIST/17) and offers no NAT benefit.
            let connection = try await openFileConnectionOnce(to: endpoint, bindTo: nil)

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

            // A retry may have been scheduled when the transfer first
            // appeared to fail — cancel it before stomping the new
            // `.completed` status, otherwise the retry Task will fire
            // later and reset the row back to `.queued`.
            cancelRetry(transferId: pending.transferId)

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = fileSize
                t.localPath = destPath
                t.error = nil
            }

            logger.info("Download complete (outgoing F): \(filename) -> \(destPath.path)")
            ActivityLogger.shared?.logDownloadCompleted(filename: filename)
            applyFolderArtworkIfNeeded(for: destPath)
            organizeCompletedDownload(currentPath: destPath, soulseekFilename: pending.filename, username: username, transferId: pending.transferId)

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

    private func openFileConnectionOnce(
        to endpoint: NWEndpoint,
        bindTo localPort: UInt16?,
        timeout: TimeInterval = 10
    ) async throws -> NWConnection {
        let params = PeerConnection.makeOutboundParameters(bindTo: localPort, remoteEndpoint: endpoint)
        let connection = NWConnection(to: endpoint, using: params)

        // Race the connection against a timeout. Without this, an NWConnection
        // that sits in `.preparing` or `.waiting` (peer unreachable, NAT
        // dropping SYNs) parks here forever — the outer 60s F-connection
        // watchdog never gets to its `Task.sleep` because the await above
        // never returns. On timeout we cancel the NWConnection so the
        // state-update handler fires `.cancelled`, the continuation
        // resolves, and we surface a clean `.timeout` instead of stranding
        // the download.
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            connection.stateUpdateHandler = { [weak connection] state in
                                switch state {
                                case .ready:
                                    connection?.stateUpdateHandler = nil
                                    continuation.resume()
                                case .failed(let error):
                                    connection?.stateUpdateHandler = nil
                                    continuation.resume(throwing: error)
                                case .cancelled:
                                    connection?.stateUpdateHandler = nil
                                    continuation.resume(throwing: DownloadError.connectionCancelled)
                                default:
                                    break
                                }
                            }
                            connection.start(queue: .global(qos: .userInitiated))
                        }
                    } onCancel: {
                        connection.cancel()
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw DownloadError.timeout
                }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            // Make sure we don't leak a half-started connection on the
            // timeout path (the cancellation handler covers Task-cancellation
            // but a raw `.timeout` throw exits the group before that fires
            // for the receive child if it had already returned).
            connection.cancel()
            throw error
        }
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
        // Cancel the underlying NWConnection on timeout. group.cancelAll()
        // alone only signals Swift Task cancellation — the receive callback
        // never fires, so the orphan child stays suspended and the task
        // group never returns. Calling connection.cancel() forces the
        // receive completion handler to fire (with error), the continuation
        // resumes, the child exits, and the timeout actually times out.
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
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
                } onCancel: {
                    connection.cancel()
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

        let rawFileHandle: FileHandle

        if resumeOffset > 0 && FileManager.default.fileExists(atPath: destPath.path) {
            // Resume mode - append to existing file
            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open file handle for resume at \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            try handle.seekToEnd()
            rawFileHandle = handle
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
            rawFileHandle = handle
        }

        // Hand the FileHandle off to a non-MainActor actor — same rationale
        // as `receiveFileDataFromPeer` / `sendFileDataViaPeerConnection`.
        let fileIO = TransferFileIO(handle: rawFileHandle)

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

            try await fileIO.write(chunk)
            bytesReceived += UInt64(chunk.count)
            networkClient?.peerConnectionPool.recordBytesReceived(UInt64(chunk.count))

            // Update progress
            let elapsed = Date().timeIntervalSince(startTime)
            let speed = elapsed > 0 ? Int64(Double(bytesReceived) / elapsed) : 0

            transferState?.updateTransfer(id: transferId) { t in
                t.bytesTransferred = bytesReceived
                t.speed = speed
            }

            // If this was the final chunk, exit loop
            if isComplete {
                break
            }
        }

        // Flush data to disk before verifying
        try await fileIO.synchronize()
        await fileIO.close()

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
        if let override = _downloadDirectoryOverride { return override }
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
        let template = settings?.activeDownloadTemplate ?? "{username}/{folders}/{filename}"
        let relativePath = DownloadManager.resolveDownloadPath(
            soulseekPath: soulseekPath,
            username: username,
            template: template
        )

        // Split into components, sanitize each, and build the URL
        let resultComponents = relativePath.split(separator: "/").map(String.init)
        var destURL = downloadDir
        for component in resultComponents {
            destURL = destURL.appendingPathComponent(sanitizeFilename(component))
        }

        return destURL
    }

    /// Resolve a SoulSeek path into a relative download path using a template.
    /// Prefers metadata values (artist, album) over folder-derived values when available.
    /// Returns a relative path string (no leading/trailing slashes).
    nonisolated static func resolveDownloadPath(
        soulseekPath: String,
        username: String,
        template: String,
        metadata: AudioFileMetadata? = nil
    ) -> String {
        // Parse the SoulSeek path (uses backslash separators)
        var pathComponents = soulseekPath.split(separator: "\\").map(String.init)

        // Remove the root share marker (e.g., "@@music", "@@downloads")
        if !pathComponents.isEmpty && pathComponents[0].hasPrefix("@@") {
            pathComponents.removeFirst()
        }

        // Need at least a filename
        guard !pathComponents.isEmpty else {
            let fallbackName = (soulseekPath as NSString).lastPathComponent
            return fallbackName.isEmpty ? "unknown" : fallbackName
        }

        // Extract filename (last component) and folders (everything else)
        let filename = pathComponents.last!
        let folderComponents = Array(pathComponents.dropLast())
        let folders = folderComponents.joined(separator: "/")

        // Derive artist and album from folder hierarchy:
        // Artist/Album/file.mp3 → artist=Artist, album=Album
        // Genre/Artist/Album/file.mp3 → artist=Artist, album=Album
        let folderAlbum = folderComponents.last ?? ""
        let folderArtist = folderComponents.count >= 2 ? folderComponents[folderComponents.count - 2] : ""

        // Prefer metadata values when available
        let artist = metadata?.artist ?? folderArtist
        let album = metadata?.album ?? folderAlbum

        // Substitute tokens
        var result = template
            .replacingOccurrences(of: "{username}", with: username)
            .replacingOccurrences(of: "{folders}", with: folders)
            .replacingOccurrences(of: "{artist}", with: artist)
            .replacingOccurrences(of: "{album}", with: album)
            .replacingOccurrences(of: "{filename}", with: filename)

        // Clean up double slashes from empty tokens (e.g. empty folders)
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        // Trim leading/trailing slashes
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return result
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
            guard let metadataReader else { return }
            let applied = await metadataReader.applyArtworkAsFolderIcon(for: directory)
            if applied {
                logger.info("Applied album art as folder icon for \(directory.lastPathComponent)")
            }
        }
    }

    /// Re-organize a completed download using actual audio metadata (artist, album).
    /// If the active template uses {artist} or {album} tokens, reads metadata from the file
    /// and moves it to the metadata-derived path if different. Fire-and-forget.
    private func organizeCompletedDownload(
        currentPath: URL,
        soulseekFilename: String,
        username: String,
        transferId: UUID
    ) {
        let template = settings?.activeDownloadTemplate ?? "{username}/{folders}/{filename}"

        // Only worth doing if the template uses artist or album tokens
        guard template.contains("{artist}") || template.contains("{album}") else { return }

        let downloadDir = getDownloadDirectory()

        Task.detached { [metadataReader, logger, transferState = self.transferState] in
            guard let metadataReader,
                  let metadata = await metadataReader.extractAudioMetadata(from: currentPath) else {
                return
            }

            // Re-resolve path with metadata
            let newRelativePath = DownloadManager.resolveDownloadPath(
                soulseekPath: soulseekFilename,
                username: username,
                template: template,
                metadata: metadata
            )

            // Build the new full path with sanitized components
            let newComponents = newRelativePath.split(separator: "/").map(String.init)
            var newPath = downloadDir
            for component in newComponents {
                // Inline the same sanitization logic
                var sanitized = component
                if sanitized == ".." || sanitized == "." { sanitized = "unnamed" }
                for char: Character in [":", "/", "\\", "\0"] {
                    sanitized = sanitized.replacingOccurrences(of: String(char), with: "_")
                }
                while sanitized.contains("..") {
                    sanitized = sanitized.replacingOccurrences(of: "..", with: "_")
                }
                sanitized = sanitized.replacingOccurrences(of: "~", with: "_")
                sanitized = sanitized.trimmingCharacters(in: .whitespaces)
                if sanitized.hasPrefix(".") { sanitized = "_" + sanitized.dropFirst() }
                if sanitized.isEmpty { sanitized = "unnamed" }
                newPath = newPath.appendingPathComponent(sanitized)
            }

            // If the path didn't change, nothing to do
            guard newPath != currentPath else { return }

            let fm = FileManager.default

            // Create parent directories
            let newDir = newPath.deletingLastPathComponent()
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)

            // Move the file
            do {
                // If a file already exists at destination, skip (don't overwrite)
                guard !fm.fileExists(atPath: newPath.path) else {
                    logger.debug("Metadata-organized path already exists, skipping move")
                    return
                }
                try fm.moveItem(at: currentPath, to: newPath)
                logger.info("Reorganized download: \(currentPath.lastPathComponent) → \(newRelativePath)")

                // Update the transfer's localPath on the main actor
                await MainActor.run {
                    transferState?.updateTransfer(id: transferId) { t in
                        t.localPath = newPath
                    }
                }

                // Clean up empty parent directories from the old location
                var oldDir = currentPath.deletingLastPathComponent()
                while oldDir != downloadDir {
                    let contents = (try? fm.contentsOfDirectory(atPath: oldDir.path)) ?? []
                    // Only remove if truly empty (ignore .DS_Store)
                    let meaningful = contents.filter { $0 != ".DS_Store" }
                    guard meaningful.isEmpty else { break }
                    try? fm.removeItem(at: oldDir)
                    oldDir = oldDir.deletingLastPathComponent()
                }
            } catch {
                logger.warning("Failed to reorganize download: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Incoming Connection Handling

    // The old `handleIncomingConnection(username:token:connection:)` lived
    // here. It was wired to `NetworkClient.onIncomingConnectionMatched`, which
    // fires when an incoming PeerInit's token matches `pendingConnections` in
    // the pool. Nothing populates `pendingConnections` (no caller of
    // `addPendingConnection`), so the path was dead. The
    // ConnectToPeer/PierceFirewall race is now owned end-to-end by
    // NetworkClient.establishPeerConnection.

    /// Called when a peer opens a file transfer connection to us (type "F")
    /// Per SoulSeek protocol: After PeerInit, uploader sends FileTransferInit token (4 bytes)
    public func handleFileTransferConnection(username: String, token: UInt32, connection: PeerConnection) async {
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
                cancelRetry(transferId: pending.transferId)
                // Drop the corresponding pendingDownloads entry too —
                // otherwise a late peer message (UploadFailed /
                // UploadDenied) finds the stale entry by filename and
                // tries to re-queue an already-finished transfer. The
                // other completion paths already do this; the
                // incoming-F path was the missing one.
                pendingDownloads.removeValue(forKey: pending.downloadToken)
                transferState?.updateTransfer(id: pending.transferId) { t in
                    t.status = .completed
                    t.bytesTransferred = pending.size
                    t.localPath = destPath
                    t.error = nil
                }
                ActivityLogger.shared?.logDownloadCompleted(filename: destPath.lastPathComponent)
                applyFolderArtworkIfNeeded(for: destPath)
                organizeCompletedDownload(currentPath: destPath, soulseekFilename: pending.filename, username: pending.username, transferId: pending.transferId)
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

            cancelRetry(transferId: pending.transferId)

            // Mark as completed with local path for Finder reveal
            transferState.updateTransfer(id: pending.transferId) { t in
                t.status = .completed
                t.bytesTransferred = pending.size
                t.localPath = destPath
                t.error = nil
            }

            logger.info("Download complete: \(filename) -> \(destPath.path)")
            ActivityLogger.shared?.logDownloadCompleted(filename: filename)
            applyFolderArtworkIfNeeded(for: destPath)
            organizeCompletedDownload(currentPath: destPath, soulseekFilename: pending.filename, username: pending.username, transferId: pending.transferId)

            logger.debug("Recording download stats: \(filename), size=\(pending.size), duration=\(duration)")
            if let stats = statisticsState {
                stats.recordTransfer(
                    filename: filename,
                    username: pending.username,
                    size: pending.size,
                    duration: duration,
                    isDownload: true
                )
                logger.debug("Stats recorded for download of \(pending.filename)")
            } else {
                logger.warning("statisticsState is nil")
            }

            // Clean up the original download tracking
            pendingDownloads.removeValue(forKey: pending.downloadToken)

        } catch {
            logger.error("File transfer failed: \(error.localizedDescription)")

            let errorMsg = error.localizedDescription
            let currentRetryCount = transferState.getTransfer(id: pending.transferId)?.retryCount ?? 0

            pendingDownloads.removeValue(forKey: pending.downloadToken)
            failDownload(
                transferId: pending.transferId,
                username: pending.username,
                filename: pending.filename,
                size: pending.size,
                reason: errorMsg,
                retryCount: currentRetryCount
            )
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

        // Open the file handle on MainActor (file creation is fast),
        // then hand it off to a `TransferFileIO` actor that owns the handle
        // for the rest of the function. Every per-chunk write hops to that
        // actor so the synchronous `write(contentsOf:)` runs off the main
        // thread — without this, a slow disk could block UI updates and
        // delay the timeout watchdog enough to make 30 s look like 60 s.
        let rawFileHandle: FileHandle

        if resumeOffset > 0 && FileManager.default.fileExists(atPath: destPath.path) {
            // Resume mode - open existing file and seek to end
            guard let handle = try? FileHandle(forWritingTo: destPath) else {
                logger.error("Failed to open existing file for resume: \(destPath.path)")
                throw DownloadError.cannotCreateFile
            }
            try handle.seekToEnd()
            rawFileHandle = handle
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
            rawFileHandle = handle
        }

        let fileIO = TransferFileIO(handle: rawFileHandle)

        var bytesReceived: UInt64 = resumeOffset  // Start from resume offset if resuming
        let startTime = Date()

        logger.info("Receiving file data from peer, expected size: \(expectedSize) bytes")
        logger.info("Start receive: \(destPath.lastPathComponent), expected=\(expectedSize) bytes")

        // First, drain any data that was buffered by the receive loop before it stopped
        let bufferedFileData = await connection.getFileTransferBuffer()
        if !bufferedFileData.isEmpty {
            logger.debug("Writing \(bufferedFileData.count) bytes from file transfer buffer")
            try await fileIO.write(bufferedFileData)
            bytesReceived += UInt64(bufferedFileData.count)

            // Update progress
            transferState?.updateTransfer(id: transferId) { t in
                t.bytesTransferred = bytesReceived
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
                // 30s no-data window matches Nicotine+'s stall threshold. The
                // previous 60s value let half-dead peers freeze the row at e.g.
                // 30% for a full minute before the row failed and retry kicked
                // in — by then the user had already clicked "Retry" twice.
                //
                // On timeout we forcibly disconnect the underlying PeerConnection
                // via the cancellation handler. Without that, the receive
                // callback inside `receiveFileChunk` never fires, the child
                // task's continuation stays pending, and the task group waits
                // on the orphan forever — defeating the timeout entirely.
                chunkResult = try await withThrowingTaskGroup(of: PeerConnection.FileChunkResult.self) { group in
                    group.addTask {
                        try await withTaskCancellationHandler {
                            try await connection.receiveFileChunk()
                        } onCancel: {
                            // PeerConnection.disconnect() is actor-isolated; hop
                            // briefly to call it. The receive callback fires
                            // with `connectionClosed`, the continuation resolves,
                            // and this child completes.
                            Task { await connection.disconnect() }
                        }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
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
                        try await fileIO.write(remainingBuffer)
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
                    try await fileIO.write(chunk)
                    bytesReceived += UInt64(chunk.count)
                    networkClient?.peerConnectionPool.recordBytesReceived(UInt64(chunk.count))
                    lastDataTime = Date()  // Reset timeout tracker

                    // Update progress periodically (not every chunk to reduce UI overhead)
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Int64(Double(bytesReceived) / elapsed) : 0

                    transferState?.updateTransfer(id: transferId) { t in
                        t.bytesTransferred = bytesReceived
                        t.speed = speed
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
                    try await fileIO.write(remainingBuffer)
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

                    try await fileIO.write(extraChunk)
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
            try await fileIO.write(finalBuffer)
            bytesReceived += UInt64(finalBuffer.count)
        }

        // Flush data to disk before verifying
        try await fileIO.synchronize()
        await fileIO.close()

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

    /// Called when a peer sends PierceFirewall — indirect connection established.
    /// NetworkClient already routes browse/folder/userinfo/download race winners
    /// via `handlePierceFirewallForBrowse` (since downloads now use the shared
    /// `establishPeerConnection` path). What's left to handle here is the
    /// upload-side delegation: PierceFirewall arrives in response to a peer's
    /// pending upload, and UploadManager owns that flow.
    public func handlePierceFirewall(token: UInt32, connection: PeerConnection) async {
        logger.debug("handlePierceFirewall: token=\(token)")

        if let uploadManager, uploadManager.hasPendingUpload(token: token) {
            logger.debug("PierceFirewall token \(token) delegated to UploadManager")
            await uploadManager.handlePierceFirewall(token: token, connection: connection)
            return
        }

        logger.debug("No pending upload for PierceFirewall token \(token)")
    }

    // MARK: - CantConnectToPeer Handling

    /// Server tells us the peer couldn't connect to us — fail fast instead of
    /// waiting for the 30s timeout. Browse/folder/userinfo/download races all
    /// share `pendingBrowseStates` in NetworkClient, so we forward there;
    /// uploads have their own pending tracking in UploadManager.
    private func handleCantConnectToPeer(token: UInt32) {
        networkClient?.failPendingBrowse(token: token, reason: "Peer unreachable (CantConnectToPeer)")

        if let uploadManager, uploadManager.hasPendingUpload(token: token) {
            logger.warning("CantConnectToPeer for upload token \(token) — failing upload")
            uploadManager.handleCantConnectToPeer(token: token)
            return
        }

        logger.debug("CantConnectToPeer token \(token) — forwarded to pending-browse + upload paths")
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
    public func handleUploadDenied(username: String, filename: String, reason: String) {
        logger.info("Upload denied from \(username): \(filename) - \(reason)")

        guard let (token, pending) = pendingDownloadEntry(username: username, filename: filename) else {
            logger.debug("No pending download for denied file: \(filename) from \(username)")
            return
        }

        if let current = transferState?.getTransfer(id: pending.transferId) {
            // Bytes already flowing — the F-connection receive loop is the
            // authoritative source of truth. An UploadDenied here is either
            // stale (for an earlier attempt) or redundant with a connection
            // close that will trigger the receive loop's own retry path.
            // Drop the message but DO NOT remove pendingDownloads — the
            // receive loop is still using that entry.
            if current.status == .transferring {
                logger.info("Ignoring upload-denied for \(filename): transfer is .transferring")
                return
            }
            // Late message for a row whose fate is already decided
            // (`.completed` / `.failed` / `.cancelled`). Drop and clean
            // the stale pendingDownloads entry so it doesn't leak.
            if !current.status.isLiveDownloadAttempt {
                logger.info("Ignoring late upload-denied for \(filename): transfer is .\(String(describing: current.status))")
                pendingDownloads.removeValue(forKey: token)
                return
            }
        }

        logger.warning("Download denied for \(filename): \(reason)")

        transferState?.updateTransfer(id: pending.transferId) { t in
            t.status = .failed
            t.error = "Denied: \(reason)"
        }

        pendingDownloads.removeValue(forKey: token)
    }

    /// Called when peer's upload to us fails
    public func handleUploadFailed(username: String, filename: String) {
        logger.info("Upload failed from \(username): \(filename)")

        guard let (token, pending) = pendingDownloadEntry(username: username, filename: filename) else {
            logger.debug("No pending download for failed file: \(filename) from \(username)")
            return
        }

        if let current = transferState?.getTransfer(id: pending.transferId) {
            // Bytes already flowing — defer to the F-connection receive
            // loop. See `handleUploadDenied` for the same guard's
            // rationale. Note: must NOT remove pendingDownloads while
            // the receive loop is still reading from it.
            if current.status == .transferring {
                logger.info("Ignoring upload-failed for \(filename): transfer is .transferring")
                return
            }
            // Late "upload failed" for an already-finalized transfer
            // would otherwise delete the local file (see the resume
            // branch below) and reset the row to `.queued` with bytes=0.
            if !current.status.isLiveDownloadAttempt {
                logger.info("Ignoring late upload-failed for \(filename): transfer is .\(String(describing: current.status))")
                pendingDownloads.removeValue(forKey: token)
                return
            }
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

        pendingDownloads.removeValue(forKey: token)
        failDownload(
            transferId: pending.transferId,
            username: pending.username,
            filename: pending.filename,
            size: pending.size,
            reason: "Upload failed on peer side"
        )
    }

    // MARK: - Retry Logic (nicotine+ style)

    private func pendingDownloadEntry(username: String, filename: String) -> (UInt32, PendingDownload)? {
        // Username is authoritative — `PeerConnectionPool` fills it from
        // its connection-level `username` parameter before the event
        // reaches us. An empty value here means we genuinely don't know
        // who sent the message, so dropping is safer than guessing: the
        // old filename-only fallback would mark the wrong row failed
        // when the same file was queued from multiple peers.
        guard !username.isEmpty else {
            logger.warning("Dropping upload-failure message for \(filename): empty peer username")
            return nil
        }
        return pendingDownloads.first { $0.value.username == username && $0.value.filename == filename }
    }

    private func failDownload(
        transferId: UUID,
        username: String,
        filename: String,
        size: UInt64,
        reason: String,
        retryCount explicitRetryCount: Int? = nil
    ) {
        let currentRetryCount = explicitRetryCount
            ?? transferState?.getTransfer(id: transferId)?.retryCount
            ?? 0

        transferState?.updateTransfer(id: transferId) { t in
            t.status = .failed
            t.error = reason
        }

        if isRetriableError(reason) && currentRetryCount < maxRetries {
            scheduleRetry(
                transferId: transferId,
                username: username,
                filename: filename,
                size: size,
                retryCount: currentRetryCount
            )
        }
    }

    /// Classify a download-failure reason as retriable. Used by both the
    /// scheduled-retry path (after a transient failure) and
    /// `resumeDownloadsOnConnect` (to decide which persisted `.failed` rows
    /// to resurrect on next login).
    ///
    /// Retry-by-default. The old implementation used an allowlist of
    /// substrings ("timeout", "connection", "network", …) and returned
    /// false for anything unmatched, which meant common failure reasons
    /// like `NetworkError.notConnected`'s "Not connected to server" or
    /// `NWError.canceled`'s "Operation canceled" (American spelling vs our
    /// British "cancelled") dropped straight through to "not retriable" —
    /// no retry ever scheduled, no resume on reconnect. With the retry
    /// count capped at `maxRetries = 4` the downside of an over-eager
    /// retry is bounded, so we now flip the default: retry unless the
    /// error matches an explicit user- or peer-driven stop reason.
    static func isRetriableError(_ error: String?) -> Bool {
        guard let lowered = error?.lowercased(), !lowered.isEmpty else {
            return false
        }

        // Known terminal reasons — user action or peer-side decisions
        // that re-asking won't change. `cancel` (bare stem) matches both
        // "cancelled" and "canceled" spellings. Mirror UploadManager.
        let terminalPatterns = [
            "cancel",
            "denied",
            "not shared",
            "not available",
            "file not found",
            "too many",
            "banned",
            "blocked",
            "disallowed",
            "pending shutdown",
        ]
        for pattern in terminalPatterns {
            if lowered.contains(pattern) { return false }
        }
        return true
    }

    private func isRetriableError(_ error: String?) -> Bool {
        Self.isRetriableError(error)
    }

    private static func formatRetryDelay(_ delay: TimeInterval) -> String {
        let seconds = Int(delay)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return "\(minutes)m"
    }

    /// Schedule automatic retry for a failed transfer with backoff measured
    /// in minutes (see `retryDelays`).
    private func scheduleRetry(transferId: UUID, username: String, filename: String, size: UInt64, retryCount: Int) {
        guard retryCount < self.maxRetries else {
            logger.info("Max retries (\(self.maxRetries)) reached for \(filename)")
            return
        }

        let delay = retryDelays[retryCount]
        let fireAt = Date().addingTimeInterval(delay)
        logger.info("Scheduling retry #\(retryCount + 1) for \(filename) in \(delay)s")

        // Update status to show pending retry. `nextRetryAt` is persisted
        // so a quit + relaunch in the middle of a 30-minute backoff still
        // honors the original schedule (see `rearmPersistedRetries`).
        transferState?.updateTransfer(id: transferId) { t in
            t.error = "Retrying in \(Self.formatRetryDelay(delay))..."
            t.nextRetryAt = fireAt
        }

        // Cancel any prior pending retry for this transfer first —
        // assigning into `pendingRetries[...]` only drops the dict
        // reference; without this the old Task keeps sleeping and
        // could fire later (its `.failed` guard usually catches it,
        // but we don't want the orphan around).
        if let existing = pendingRetries.removeValue(forKey: transferId) {
            existing.cancel()
        }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))

            guard let self, !Task.isCancelled else { return }

            await MainActor.run {
                self.pendingRetries.removeValue(forKey: transferId)

                // Only proceed if the transfer is still in a failed
                // state. Between schedule and wake, the original attempt
                // may have completed (late data), transitioned into
                // `.transferring`/`.connecting`, been `.cancelled` by
                // the user, or been re-queued manually. In all those
                // cases this scheduled retry is stale — firing it would
                // stomp a good transfer back to `.queued` with
                // `bytesTransferred = 0`.
                guard let current = self.transferState?.getTransfer(id: transferId),
                      current.status == .failed else {
                    self.logger.info("Skipping scheduled retry for \(filename): no longer in .failed state")
                    return
                }

                self.retryDownload(
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

    /// Reset a previously-failed (or cancelled) transfer so `startDownload`
    /// can re-run from byte zero. Callers MUST ensure the transfer is
    /// eligible first — the scheduled-retry path checks `.failed` before
    /// calling this; `retryFailedDownload` checks `.failed || .cancelled`.
    private func retryDownload(transferId: UUID, username: String, filename: String, size: UInt64, retryCount: Int) {
        logger.info("Retrying download: \(filename) (attempt \(retryCount))")

        // Update the existing transfer record. Reset to .queued so
        // `startDownload` (which sets it to .connecting) sees a clean slate.
        // Clear `nextRetryAt` — the scheduled retry just fired and the row
        // is moving forward, so the persisted timestamp is stale.
        transferState?.updateTransfer(id: transferId) { t in
            t.status = .queued
            t.error = nil
            t.bytesTransferred = 0
            t.retryCount = retryCount
            t.nextRetryAt = nil
        }

        // Re-initiate via the normal startDownload path so the retry uses
        // the same `establishPeerConnection` + `queueOnConnection` flow as
        // a fresh download. The old `requestDownload` helper bypassed this
        // (called `getUserAddress` directly and relied on the now-removed
        // `handlePeerAddress` to drive forward).
        let transfer = Transfer(
            id: transferId,
            username: username,
            filename: filename,
            size: size,
            direction: .download,
            status: .queued,
            retryCount: retryCount
        )
        Task {
            await startDownload(transfer: transfer)
        }
    }

    /// Public method to manually retry a failed download.
    ///
    /// `.queued` is in the eligible set because `TransfersView`'s Retry
    /// button calls `transferState.retryTransfer(id:)` first — which sets
    /// status to `.queued` — and THEN calls this method. Pre-fix the
    /// guard rejected `.queued` and the manual retry was a silent no-op
    /// (the row went `.failed → .queued` and just sat there until the
    /// next reconnect, where `resumeDownloadsOnConnect` picked it up).
    public func retryFailedDownload(transferId: UUID) {
        guard let transfer = transferState?.getTransfer(id: transferId),
              transfer.status == .failed || transfer.status == .cancelled || transfer.status == .queued else {
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

    /// Cancel a pending retry. Drops the in-memory `Task` AND clears the
    /// persisted `nextRetryAt` so a subsequent rearm-on-launch doesn't
    /// resurrect this scheduled retry on top of the new flow that just
    /// took the row out of a retriable state.
    public func cancelRetry(transferId: UUID) {
        if let task = pendingRetries.removeValue(forKey: transferId) {
            task.cancel()
            logger.info("Cancelled pending retry for transfer \(transferId)")
        }
        transferState?.updateTransfer(id: transferId) { t in
            t.nextRetryAt = nil
        }
    }

    /// Rearm in-memory retry timers for any persisted `.failed` rows that
    /// were mid-backoff when the app last quit. Without this, a row that
    /// was scheduled to retry in 28 minutes but interrupted by a quit
    /// just sits at `.failed` forever (the in-memory Task died). Past-due
    /// rows fire immediately with a small per-row stagger so 50 pending
    /// retries don't flood the network on launch. Call once at startup
    /// after `transferState.loadPersisted()` completes.
    public func rearmPersistedRetries() {
        guard let transferState else { return }
        let now = Date()
        let candidates = transferState.downloads.filter {
            $0.status == .failed && $0.nextRetryAt != nil && $0.retryCount < self.maxRetries
        }
        guard !candidates.isEmpty else { return }
        logger.info("Rearming \(candidates.count) persisted download retries")
        for (index, transfer) in candidates.enumerated() {
            guard let fireAt = transfer.nextRetryAt else { continue }
            let remaining = fireAt.timeIntervalSince(now)
            // Stagger past-due rows by 0.5s each. Future rows already
            // have a natural spread from the original scheduling.
            let stagger = remaining <= 0 ? Double(index) * 0.5 : 0
            let delay = max(0, remaining) + stagger
            let transferId = transfer.id
            let username = transfer.username
            let filename = transfer.filename
            let size = transfer.size
            let retryCount = transfer.retryCount

            if let existing = pendingRetries.removeValue(forKey: transferId) {
                existing.cancel()
            }
            let task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.pendingRetries.removeValue(forKey: transferId)
                    guard let current = self.transferState?.getTransfer(id: transferId),
                          current.status == .failed else {
                        self.logger.info("Skipping rearmed retry for \(filename): no longer in .failed state")
                        return
                    }
                    self.retryDownload(
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
    }

    // MARK: - Test-only accessors

    internal var _pendingDownloadCount: Int { pendingDownloads.count }

    internal func _pendingDownloadFor(username: String, filename: String) -> PendingDownload? {
        pendingDownloads.values.first { $0.username == username && $0.filename == filename }
    }

    internal func _seedPendingDownloadForTest(_ pending: PendingDownload, token: UInt32) {
        pendingDownloads[token] = pending
    }

    /// Test-only re-entry into the salvage path. Real callers go through the
    /// pool event stream wired in `configure(...)`.
    internal func _handlePoolTransferRequestForTest(
        _ request: TransferRequest,
        connection: PeerConnection
    ) async {
        await handlePoolTransferRequest(request, connection: connection)
    }

    /// Test-only: evaluate the routing DECISION for an incoming pool
    /// TransferRequest without actually executing handleTransferRequest
    /// (which would try to send TransferReply on `connection` and clean up
    /// on failure — racy to test on a synthetic non-connected PeerConnection).
    /// Returns what the routing layer would do and, for `salvaged`,
    /// transitions pendingDownloads to the post-salvage state so the caller
    /// can inspect the new entry.
    internal enum PoolTransferDecision: Equatable {
        case matched(token: UInt32)
        case salvaged(token: UInt32, transferId: UUID)
        case dropped
    }

    internal func _evaluatePoolTransferRequestForTest(
        _ request: TransferRequest,
        connection: PeerConnection
    ) -> PoolTransferDecision {
        let peerUsername = request.username.isEmpty ? connection.peerInfo.username : request.username
        let normalized = request.username.isEmpty && !peerUsername.isEmpty
            ? TransferRequest(direction: request.direction, token: request.token, filename: request.filename, size: request.size, username: peerUsername)
            : request

        if let token = matchPendingDownload(for: normalized) {
            return .matched(token: token)
        }

        let alreadyPending = pendingDownloads.values.contains {
            $0.username == peerUsername && $0.filename == request.filename
        }
        guard !peerUsername.isEmpty, !alreadyPending else {
            return .dropped
        }
        guard let transfer = transferState?.downloads
            .filter({ t in
                t.direction == .download &&
                t.username == peerUsername &&
                t.filename == request.filename &&
                (t.status == .queued || t.status == .waiting || t.status == .connecting)
            })
            .min(by: { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) })
        else {
            return .dropped
        }

        let salvagedToken = UInt32.random(in: 1...UInt32.max)
        let info = connection.peerInfo
        pendingDownloads[salvagedToken] = PendingDownload(
            transferId: transfer.id,
            username: transfer.username,
            filename: transfer.filename,
            size: request.size,
            peerIP: info.ip.isEmpty ? nil : info.ip,
            peerPort: info.port > 0 ? info.port : nil
        )
        return .salvaged(token: salvagedToken, transferId: transfer.id)
    }

    /// Inject a TransferTracking implementation without going through full
    /// `configure(...)` (which requires a NetworkClient). Tests use this to
    /// drive logic that only touches transferState.
    ///
    /// The real `transferState` property is `weak` (production owns its
    /// lifecycle). For tests we additionally retain the mock strongly via
    /// `_testStrongTransferState` so it survives across awaits — without
    /// this, test-local mocks get released by ARC before the assertion
    /// runs, the weak ref nils out, and the salvage path's
    /// `transferState?.downloads` lookup returns nil.
    internal func _setTransferStateForTest(_ tracking: any TransferTracking) {
        self._testStrongTransferState = tracking
        self.transferState = tracking
    }

    private var _testStrongTransferState: (any TransferTracking)?

    /// Redirect `getDownloadDirectory()` to a test-controlled URL so file
    /// I/O paths (resume detection, partial-file deletion) can run against
    /// a temp directory instead of `~/Downloads/SeeleSeek`.
    internal func _setDownloadDirectoryOverrideForTest(_ url: URL?) {
        _downloadDirectoryOverride = url
    }

    private var _downloadDirectoryOverride: URL?
}
