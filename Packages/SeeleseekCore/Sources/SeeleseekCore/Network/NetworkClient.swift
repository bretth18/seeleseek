import Foundation
import Network
import os
import Synchronization

/// The network control plane: server socket, login/reconnect, peer
/// coordination, protocol facade. An actor, so none of this work shares
/// the main thread with SwiftUI rendering — that rationale holds for every
/// actor in the package. The UI observes the `status` and `monitor`
/// mirrors and consumes `events`; app code awaits the methods directly.
public actor NetworkClient {
    nonisolated let logger = Logger(subsystem: "com.seeleseek", category: "NetworkClient")

    // MARK: - Status Mirror

    /// Connection-state mirror for the UI, fed by `publishStatus` on every
    /// didSet below. FIFO through one stream, so transitions
    /// (connecting → connected → disconnected) cannot reorder.
    public nonisolated let status: NetworkStatusState

    /// Statistics mirror for the monitor/diagnostics views, owned and fed
    /// by the pool.
    public nonisolated var monitor: NetworkMonitorState { peerConnectionPool.monitor }

    private let statusContinuation: AsyncStream<NetworkStatusSnapshot>.Continuation

    private func publishStatus() {
        var s = NetworkStatusSnapshot()
        s.isConnecting = isConnecting
        s.isConnected = isConnected
        s.connectionError = connectionError
        s.username = username
        s.loggedIn = loggedIn
        s.listenPort = listenPort
        s.obfuscatedPort = obfuscatedPort
        s.externalIP = externalIP
        s.localIP = localIP
        s.natGateway = natGateway
        s.natMappings = natMappings
        s.acceptDistributedChildren = acceptDistributedChildren
        s.distributedBranchLevel = distributedBranchLevel
        s.distributedBranchRoot = distributedBranchRoot
        s.distributedChildrenCount = distributedChildren.count
        statusContinuation.yield(s)
    }

    // MARK: - Connection State
    public private(set) var isConnecting = false {
        didSet { publishStatus() }
    }
    public private(set) var isConnected = false {
        didSet { publishStatus() }
    }
    public private(set) var connectionError: String? {
        didSet { publishStatus() }
    }

    // MARK: - User Info
    public private(set) var username: String = "" {
        didSet { publishStatus() }
    }
    public private(set) var loggedIn = false {
        didSet { publishStatus() }
    }

    // MARK: - Network Info
    public private(set) var listenPort: UInt16 = 0 {
        didSet { publishStatus() }
    }
    public private(set) var obfuscatedPort: UInt16 = 0 {
        didSet { publishStatus() }
    }
    public private(set) var externalIP: String? {
        didSet { publishStatus() }
    }

    /// Local interface IP (en0/en1). Set once at startup.
    public private(set) var localIP: String? {
        didSet { publishStatus() }
    }
    /// Router gateway discovered by UPnP or inferred from the local subnet.
    /// Nil until NAT setup runs.
    public private(set) var natGateway: String? {
        didSet { publishStatus() }
    }
    /// Port mappings we successfully registered via UPnP or NAT-PMP. Empty
    /// when mapping is disabled or all attempts failed.
    public private(set) var natMappings: [NATService.PortMapping] = [] {
        didSet { publishStatus() }
    }

    /// Classifies our listen port's reachability from other peers. Not
    /// RFC-grade NAT classification — just "can peers reach our port, and
    /// if not, why?" — which is what users need to know.
    ///
    /// The core signal is `peerInitCount`: it's only incremented when a peer
    /// reaches us directly and sends PeerInit. The server forwarding
    /// `ConnectToPeer` to us is the OPPOSITE signal — it means a peer
    /// couldn't reach our port and asked the server to forward their
    /// request instead.
    public enum Reachability: Sendable, Equatable {
        /// Not enough signal yet — no peer has tried to reach us.
        case unknown
        /// Peers are directly reaching our listen port (at least some of them).
        case direct
        /// Direct works AND we have a UPnP / NAT-PMP mapping active.
        case upnpMapped
        /// Only some peers reach us directly; others fall back to the server
        /// forwarding route because we're partially reachable (e.g. ISP CGNAT,
        /// symmetric-NAT peer on the other side).
        case partial
        /// Server is forwarding `ConnectToPeer` requests but no peer has
        /// reached our port directly. Port is effectively closed to the
        /// internet; we can only initiate outbound connections.
        case unreachable

        public var label: String {
            switch self {
            case .unknown: "Checking…"
            case .direct: "Port open — peers connect directly"
            case .upnpMapped: "Direct + UPnP mapping active"
            case .partial: "Partially reachable"
            case .unreachable: "Port unreachable — outbound only"
            }
        }
    }

    /// Pure classifier so views can compute reachability from the mirrors
    /// (`monitor.peerInitCount` / `monitor.connectToPeerCount` /
    /// `status.natMappings`) without touching this coordinator.
    public static func classifyReachability(
        directInbound: Int,
        indirectWanted: Int,
        hasActiveMapping: Bool
    ) -> Reachability {
        if directInbound > 0 {
            // At least one peer reached our port directly — definitively reachable.
            if hasActiveMapping { return .upnpMapped }
            // Some peers still fall back to server forwarding, which usually
            // means the other side is behind a symmetric NAT — not our fault.
            if indirectWanted > directInbound * 2 { return .partial }
            return .direct
        }

        // Server forwarded at least 10 ConnectToPeer and none have reached our
        // port directly — port is unreachable from the internet.
        if indirectWanted >= 10 {
            return .unreachable
        }

        return .unknown
    }

    // MARK: - Distributed Network
    public var acceptDistributedChildren = true {
        didSet { publishStatus() }
    }
    public internal(set) var distributedBranchLevel: UInt32 = 0 {
        didSet { publishStatus() }
    }
    public internal(set) var distributedBranchRoot: String = "" {
        didSet { publishStatus() }
    }
    public internal(set) var distributedChildren: [PeerConnection] = [] {
        didSet { publishStatus() }
    }

    // MARK: - Internal
    var serverConnection: ServerConnection?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    /// Success-or-throw: login success resumes with Void, a rejected login
    /// resumes by throwing `loginFailed`. There is deliberately no `false`
    /// value — a boolean resume could leave `isConnecting` stuck if a
    /// future resume site returned `false` without an else branch.
    private var loginContinuation: CheckedContinuation<Void, Error>?
    private var loginTimeoutTask: Task<Void, Never>?
    private var loginAttemptGeneration = 0

    // MARK: - Auto-Reconnect
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var shouldAutoReconnect = false
    private enum ConnectionAttemptOrigin: Equatable {
        case userInitiated
        case autoReconnect
    }
    private var lastServer: String?
    private var lastPort: UInt16?
    private var lastPassword: String?
    private var lastPreferredListenPort: UInt16?
    /// Base delays for exponential backoff: 5s, 10s, 30s, 60s, then cap at 60s
    private static let reconnectDelays: [TimeInterval] = [5, 10, 30, 60]
    /// Kept internal-only for deterministic reconnect integration tests.
    var reconnectDelayOverrideForTesting: TimeInterval?
    var skipNATSetupForTesting = false

    /// Host used for the current/last connect attempt. Exposed so the
    /// server-message handler can log the ACTUAL server instead of a
    /// hardcoded hostname.
    internal var serverHost: String? { lastServer }

    // MARK: - Server-Message Handling State
    // Owned by the handling code in ServerMessageHandler.swift (an
    // extension of this type — stored properties must live here).

    /// Track pending ConnectToPeer dials to avoid duplicates.
    var pendingConnections: Set<String> = []
    var serverConnectToPeerCount = 0
    var droppedConnectToPeerCount = 0
    var hasWarnedAboutListener = false

    // Rate limiting for outbound connections
    var lastConnectionAttempt = Date.distantPast
    let connectionRateLimit: TimeInterval = 0.05  // Max 20 connections per second
    var connectionQueue: [(username: String, type: String, ip: String, port: UInt32, token: UInt32)] = []
    var isProcessingQueue = false

    var distributedParentConnection: PeerConnection?
    var isConnectingToParent = false

    // MARK: - Keepalive Configuration
    /// Interval between ping messages (5 minutes)
    private static let pingInterval: TimeInterval = 300

    // Services
    private let listenerService = ListenerService()
    private let natService = NATService()

    public nonisolated let peerConnectionPool: PeerConnectionPool
    public nonisolated let shareManager: ShareManager
    public nonisolated let userInfoCache: UserInfoCache

    // Metadata reader for SeeleSeek artwork extension
    public private(set) var metadataReader: (any MetadataReading)?

    public func setMetadataReader(_ reader: any MetadataReading) {
        metadataReader = reader
    }

    // Stream consumer task (cancelled on disconnect for clean reconnect).
    // The pool-event and share-counts consumers are unstored: they hold
    // self weakly, live for the actor's lifetime, and end when their
    // streams tear down at deinit.
    private var listenerConsumerTask: Task<Void, Never>?

    // MARK: - Pending Peer Address Requests (for concurrent browse/folder requests)
    // Uses (continuation, requestID) to prevent double-resume when same user is requested multiple times
    var pendingPeerAddressRequests: [String: [(continuation: CheckedContinuation<(ip: String, port: Int, obfuscatedPort: Int), Error>, requestID: UUID)]] = [:]

    // MARK: - Pending Status Requests (for checking if user is online before browse/download)
    // Multi-waiter: concurrent callers for the same username all attach to
    // one server round-trip and get the same reply. Single-continuation
    // storage would silently orphan the earlier caller when a second call
    // overwrote the dict slot. Matches the shape of
    // `pendingPeerAddressRequests` — waiter identified by UUID so per-call
    // timeouts remove exactly one slot.
    typealias PendingStatusWaiter = (
        continuation: CheckedContinuation<(status: UserStatus, privileged: Bool), Never>,
        requestID: UUID
    )
    var pendingStatusRequests: [String: [PendingStatusWaiter]] = [:]

    // MARK: - Initialization

    /// `@MainActor`: the MainActor collaborators (`shareManager`,
    /// `userInfoCache`, `status`) are constructed inline, and the app/test
    /// call sites are all MainActor anyway.
    @MainActor
    public init() {
        logger.info("NetworkClient initializing...")

        self.peerConnectionPool = PeerConnectionPool()
        self.shareManager = ShareManager()
        self.userInfoCache = UserInfoCache()

        let status = NetworkStatusState()
        self.status = status
        self.statusContinuation = makeMirrorPipe(into: status) { $0.apply($1) }

        // Serial pool-event consumer: awaiting each handler in turn keeps
        // per-peer event order (a transferResponse can't leapfrog its
        // queueUpload). Weak self per iteration — a `guard let self` before
        // the loop would retain self until the stream ends, which only
        // happens at deinit: a cycle.
        let poolEvents = peerConnectionPool.events
        Task { [weak self] in
            for await event in poolEvents {
                await self?.handlePoolEvent(event)
            }
        }

        // Re-broadcast `SharedFoldersFiles` whenever the local share index
        // changes — the login broadcast races the disk rescan and usually
        // loses, leaving the server reporting "0 shared files".
        // `updateShareCounts` is a no-op while disconnected. The stream must
        // be obtained SYNCHRONOUSLY here, not inside the Task body: a
        // `Task { await rescanAll() }` queued on the same MainActor could
        // otherwise notify before the continuation registers, and AsyncStream
        // buffers post-registration yields only.
        let countsStream = shareManager.countsChangesStream()
        Task { [weak self] in
            for await _ in countsStream {
                await self?.updateShareCounts()
            }
        }

        logger.info("NetworkClient initialized")
    }

    /// Handles one pool event. Async and awaited serially by the consumer
    /// task in `init` — do NOT spawn per-event unstructured Tasks here, that
    /// loses cross-event ordering per peer and lets handlers interleave at
    /// suspension points.
    private func handlePoolEvent(_ event: PeerPoolEvent) async {
        switch event {
        case .searchResults(let token, let results):
            emit(.results(token: token, results: results))

        case .fileTransferConnection(let username, let token, let connection):
            emit(.fileTransferConnection(username: username, token: token, connection: connection))

        case .pierceFirewall(let token, let connection):
            if await handlePierceFirewallForBrowse(token: token, connection: connection) { return }
            emit(.pierceFirewall(token: token, connection: connection))

        case .uploadDenied(let username, let filename, let reason):
            emit(.uploadDenied(username: username, filename: filename, reason: reason))

        case .uploadFailed(let username, let filename):
            emit(.uploadFailed(username: username, filename: filename))

        case .queueUpload(let username, let filename, let connection):
            emit(.queueUpload(username: username, filename: filename, connection: connection))

        case .transferResponse(let token, let allowed, let filesize, let reason, let connection):
            emit(.transferResponse(token: token, allowed: allowed, filesize: filesize, reason: reason, connection: connection))

        case .folderContentsRequest(let username, let token, let folder, let connection):
            await handleFolderContentsRequest(username: username, token: token, folder: folder, connection: connection)

        case .folderContentsResponse(let token, let folder, let files):
            emit(.folderContentsResponse(token: token, folder: folder, files: files))

        case .transferRequest(let request, let connection):
            emit(.transferRequest(request, connection: connection))

        case .placeInQueueRequest(let username, let filename, let connection):
            emit(.placeInQueueRequest(username: username, filename: filename, connection: connection))

        case .placeInQueueReply(let username, let filename, let position):
            emit(.placeInQueueReply(username: username, filename: filename, position: position))

        case .sharesRequest(let username, let connection):
            await handleSharesRequest(username: username, connection: connection)

        case .userInfoRequest(let username, let connection):
            await handleUserInfoRequest(username: username, connection: connection)

        case .userInfoReply(let username, let info):
            handleUserInfoReplyEvent(username: username, info: info)

        case .artworkRequest(let username, let token, let filePath, let connection):
            await handleArtworkRequest(username: username, token: token, filePath: filePath, connection: connection)

        case .sharesReceived(let username, let files):
            logger.info("Received \(files.count) shared files from \(username) via pool")
            if let continuation = pendingBrowseSharesContinuations.removeValue(forKey: username) {
                continuation.resume(returning: files)
            }

        case .userIPDiscovered(let username, let ip):
            await userInfoCache.registerIP(ip, for: username)

        case .artworkReply(let token, let imageData):
            if let callback = artworkCallbacks.removeValue(forKey: token) {
                callback(imageData.isEmpty ? nil : imageData)
            }
        }
    }

    // MARK: - Pushed app config
    // The app pushes updated values down when its source data changes, so
    // hot-path handlers (per distributed query / per peer request) read
    // local state instead of calling back into the app layer.

    /// Our profile served in UserInfoResponse. See `updateProfileData`.
    public private(set) var profileData = ProfileData()

    public func updateProfileData(_ data: ProfileData) {
        profileData = data
    }

    /// How we answer distributed searches. See `updateSearchResponsePolicy`.
    public private(set) var searchResponsePolicy = SearchResponsePolicy()

    public func updateSearchResponsePolicy(_ policy: SearchResponsePolicy) {
        searchResponsePolicy = policy
    }

    /// Lowercased usernames of the user's buddy list, pushed by the app
    /// whenever it changes. Used by the shares-reply and distributed-search
    /// handlers to decide whether to expose folders marked `.buddies`.
    /// Empty until the app pushes, so shares default to public-only if the
    /// app forgot to wire this up.
    private var buddyUsernames: Set<String> = []

    public func updateBuddyList(_ lowercasedUsernames: Set<String>) {
        buddyUsernames = lowercasedUsernames
    }

    /// Case-insensitive buddy-list membership check against the pushed set.
    public func isBuddy(_ username: String) -> Bool {
        buddyUsernames.contains(username.lowercased())
    }

    // MARK: - Event Bus

    /// Multi-subscriber event surface. Subscribe during app wiring, strictly
    /// before `connect()` — events published before subscription are dropped.
    public nonisolated let events = NetworkEventBus()

    func emit(_ event: ChatEvent) {
        events.chat.publish(event)
    }

    func emit(_ event: SocialEvent) {
        events.social.publish(event)
    }

    func emit(_ event: SearchEvent) {
        events.search.publish(event)
    }

    func emit(_ event: ConnectionEvent) {
        events.connection.publish(event)
    }

    func emit(_ event: TransferNoticeEvent) {
        events.transferNotices.publish(event)
    }

    func emit(_ event: TransferEvent) {
        events.transfers.publish(event)
    }

    // MARK: - Connection

    public func connect(server: String, port: UInt16, username: String, password: String, preferredListenPort: UInt16? = nil) async {
        await performConnect(
            server: server,
            port: port,
            username: username,
            password: password,
            preferredListenPort: preferredListenPort,
            origin: .userInitiated
        )
    }

    private func performConnect(
        server: String,
        port: UInt16,
        username: String,
        password: String,
        preferredListenPort: UInt16?,
        origin: ConnectionAttemptOrigin
    ) async {
        guard !isConnecting && !isConnected else { return }

        if origin == .userInitiated {
            // A user-initiated connect starts a fresh reconnect lifecycle.
            // Auto-reconnect attempts must NOT run this block: cancelling
            // reconnectTask there cancels the task currently executing this
            // method, and resetting reconnectAttempt pins backoff at 5s.
            lastServer = server
            lastPort = port
            lastPassword = password
            lastPreferredListenPort = preferredListenPort
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
        }

        isConnecting = true
        connectionError = nil
        self.username = username
        await peerConnectionPool.setOurUsername(username)
        if origin == .userInitiated {
            emit(.statusChanged(.connecting))
        }

        logger.info("Starting connection to \(server):\(port) as \(username)")

        // Let any in-flight teardown finish before starting the listener —
        // otherwise the old teardown's listenerService.stop() can land
        // after the new start() and silently kill the fresh listener while
        // its port is still advertised to the server. (Safe re-entrancy:
        // isConnecting is already true, so a concurrent connect() bails at
        // the guard above.)
        await teardownTask?.value
        teardownTask = nil

        do {
            // Step 1: Start listener for incoming peer connections
            listenerConsumerTask?.cancel()
            let portDesc = preferredListenPort?.description ?? "auto"
            logger.info("Starting listener service (preferred port: \(portDesc))...")
            let ports = try await listenerService.start(preferredPort: preferredListenPort)
            listenPort = ports.port
            obfuscatedPort = ports.obfuscatedPort
            logger.info("Listening on port \(self.listenPort) (obfuscated: \(self.obfuscatedPort))")

            // Step 2: Consume incoming peer connections (after listener started, so we get the fresh stream).
            // Weak self per iteration — same retain-cycle trap as the
            // pool-event consumer in `init`.
            let connectionStream = await listenerService.newConnections
            listenerConsumerTask = Task { [weak self] in
                for await (connection, obfuscated) in connectionStream {
                    guard let self else { return }
                    await self.peerConnectionPool.handleIncomingConnection(connection, obfuscated: obfuscated)
                }
            }

            // Step 3: Connect to server FIRST (NAT runs in background)
            logger.info("Connecting to server...")
            let connection = ServerConnection(host: server, port: port)
            serverConnection = connection

            try await connection.connect()
            logger.info("Connected to server")

            // Step 4: Send login
            logger.info("Sending login...")

            let loginMessage = MessageBuilder.loginMessage(
                username: username,
                password: password
            )
            try await connection.send(loginMessage)

            // Start receiving messages (login response will come through here)
            startReceiving()

            // Wait for login response using continuation (resumed by setLoggedIn)
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.loginContinuation = continuation

                    // Timeout after 10 seconds so we don't wait forever.
                    // Generation-stamped: an uncancelled timer from attempt N
                    // must never resume attempt N+1's continuation (quick
                    // disconnect/reconnect inside the 10s window).
                    self.loginAttemptGeneration += 1
                    let generation = self.loginAttemptGeneration
                    self.loginTimeoutTask?.cancel()
                    self.loginTimeoutTask = Task {
                        try? await Task.sleep(for: .seconds(10))
                        guard !Task.isCancelled,
                              generation == self.loginAttemptGeneration,
                              let pending = self.loginContinuation else { return }
                        self.loginContinuation = nil
                        pending.resume(throwing: ServerConnection.ConnectionError.timeout)
                    }
                }
                loginTimeoutTask?.cancel()
                loginTimeoutTask = nil
            } catch {
                loginTimeoutTask?.cancel()
                loginTimeoutTask = nil
                // Only a credential rejection should disable auto-reconnect;
                // a timeout or socket error during the handshake is transient
                // and the user asked for a persistent connection.
                let credentialRejected: Bool
                if case ServerConnection.ConnectionError.loginFailed = error {
                    credentialRejected = true
                } else {
                    credentialRejected = false
                }
                await handleConnectionAttemptFailure(
                    error,
                    origin: origin,
                    credentialRejected: credentialRejected
                )
                return
            }

            // Step 5: Send listen port to server
            logger.info("Sending listen port...")
            // Advertise the obfuscated port whenever the listener managed
            // to bind it. SoulseekQt / Museek+ also default this on; if
            // the codec ever misbehaves the right fix is to fix it, not
            // to hide a toggle behind a settings UI.
            let portMessage = MessageBuilder.setListenPortMessage(
                port: UInt32(listenPort),
                obfuscatedPort: UInt32(obfuscatedPort)
            )
            try await connection.send(portMessage)
            lastAdvertisedListenPort = listenPort
            lastAdvertisedObfuscatedPort = obfuscatedPort

            // Step 6: Set online status
            let statusMessage = MessageBuilder.setOnlineStatusMessage(status: .online)
            try await connection.send(statusMessage)

            // Step 7: Report shared files
            let folders = await UInt32(shareManager.totalFolders)
            let files = await UInt32(shareManager.totalFiles)
            let sharesMessage = MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files)
            try await connection.send(sharesMessage)
            logger.info("Reported shares: \(folders) folders, \(files) files")

            // Step 8: Join distributed network for search propagation
            // Tell server we need a distributed parent
            let haveNoParentMessage = MessageBuilder.haveNoParent(true)
            try await connection.send(haveNoParentMessage)
            logger.info("Sent HaveNoParent(true) - requesting distributed network parent")

            // Advertise AcceptChildren(false): distributed child support is
            // NOT implemented. `addDistributedChild` has no callers — inbound
            // type-"D" PeerInit connections are created as `.peer` in the
            // pool and their distributed frames would parse as garbage.
            // Advertising `true` made the server route children at us that
            // could never work. To implement for real: route inbound PeerInit
            // type "D" from the pool into `addDistributedChild` and switch
            // those connections into distributed parsing mode — the
            // downstream plumbing (`forwardDistributedSearch`,
            // `sendBranchInfoToChildren`, `removeDistributedChild`) is
            // already in place for that future work.
            let acceptChildrenMessage = MessageBuilder.acceptChildren(false)
            try await connection.send(acceptChildrenMessage)
            logger.info("Sent AcceptChildren(false) — child support unimplemented")

            // Tell server our branch level (0 = not connected to distributed network yet)
            let branchLevelMessage = MessageBuilder.branchLevel(0)
            try await connection.send(branchLevelMessage)
            logger.info("Sent BranchLevel(0)")

            // Print diagnostic info
            logger.info("CONNECTION DIAGNOSTICS:")
            logger.info("  Listen port: \(self.listenPort)")
            logger.info("  Obfuscated port: \(self.obfuscatedPort)")
            if let extIP = self.externalIP {
                logger.info("  External IP: \(extIP)")
            } else {
                logger.info("  External IP: unknown (NAT mapping may have failed)")
            }

            isConnecting = false
            isConnected = true
            reconnectAttempt = 0  // Reset backoff on successful connection
            reconnectTask = nil
            // Armed only on login success — a session that never logged in
            // must fail visibly, not auto-retry.
            shouldAutoReconnect = true
            emit(.statusChanged(.connected))
            logger.info("Login successful!")

            // Start keepalive ping timer
            startPingTimer()

            // Run NAT mapping in background (don't block connection)
            if !skipNATSetupForTesting {
                Task {
                    await self.setupNATInBackground()
                }
            }

        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            await handleConnectionAttemptFailure(error, origin: origin)
        }
    }

    /// Tear down a failed connection attempt without bouncing the app through
    /// `.disconnected` when another automatic attempt is pending. Publishing
    /// `.disconnected` here made MainView flash LoginView on every retry, and
    /// logging it produced an unbounded wall of identical console entries.
    private func handleConnectionAttemptFailure(
        _ error: Error,
        origin: ConnectionAttemptOrigin,
        credentialRejected: Bool = false
    ) async {
        // A user-triggered disconnect already performed teardown and disabled
        // reconnect. Don't let the cancelled in-flight attempt do it again.
        if Task.isCancelled && !shouldAutoReconnect {
            isConnecting = false
            return
        }

        isConnecting = false
        connectionError = error.localizedDescription
        if credentialRejected {
            shouldAutoReconnect = false
        }
        let willReconnect = shouldAutoReconnect

        // During an automatic attempt reconnectTask is the task executing
        // this method. Drop the completed/failed handle before scheduling the
        // next task so scheduleReconnect doesn't cancel its own caller.
        if origin == .autoReconnect {
            reconnectTask = nil
        }

        performDisconnect(
            reportActivity: !willReconnect,
            publishDisconnectedStatus: !willReconnect
        )
        if willReconnect {
            // Publish `.reconnecting` immediately; teardown can continue in
            // parallel with the backoff sleep, and performConnect awaits it
            // before opening the next listener/socket.
            scheduleReconnect(reason: error.localizedDescription)
        }
        await teardownTask?.value
    }

    public func disconnect() {
        // User-initiated disconnect — stop auto-reconnect
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        performDisconnect()
    }

    /// Like `disconnect()` but awaits the listener / NAT / server-connection
    /// teardown before returning. Required for any flow that needs to
    /// immediately reissue `connect()` (e.g. applying a new listen port) —
    /// the sync path kicks teardown off in a fire-and-forget Task that
    /// races a follow-up `start()` on the listenerService actor and can
    /// leak the old listener while cancelling the new one.
    public func disconnectAsync() async {
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        performDisconnect()
        // performDisconnect stores the teardown Task so callers who need
        // to wait for socket-level cleanup can await it here.
        await teardownTask?.value
    }

    /// Tracks the in-flight async teardown spawned by `performDisconnect`
    /// so `disconnectAsync()` can await it. Kept as a property (not a
    /// local) so any subsequent disconnect can also wait on prior cleanup.
    private var teardownTask: Task<Void, Never>?

    /// Internal disconnect that preserves auto-reconnect eligibility
    private func performDisconnect(
        reportActivity: Bool = true,
        publishDisconnectedStatus: Bool = true
    ) {
        logger.info("Disconnecting...")
        if reportActivity {
            Task { @MainActor in ActivityLogger.shared?.logDisconnected() }
        }

        // Cancel any pending login wait
        if let continuation = loginContinuation {
            loginContinuation = nil
            continuation.resume(throwing: ServerConnection.ConnectionError.notConnected)
        }

        // Fail every in-flight peer-operation continuation so no waiter
        // survives across a reconnect into a server context where its
        // reply can never arrive. Previously only server/listener/NAT
        // state was torn down, and reconnects inherited stale continuations
        // + peer sockets — callers hung until their per-call timeout.
        failAllPendingPeerOperations(reason: "disconnected")

        // Session-scoped privileged flags — clearing here keeps the map
        // from growing unboundedly across long-lived reconnect cycles.
        lastKnownPrivileged.removeAll()

        receiveTask?.cancel()
        receiveTask = nil

        pingTask?.cancel()
        pingTask = nil

        listenerConsumerTask?.cancel()
        listenerConsumerTask = nil

        // Snapshot the previous teardown (if any) so the new teardown
        // chains after it — otherwise rapid disconnect/reconnect cycles
        // could interleave socket work on the listenerService actor.
        let priorTeardown = teardownTask
        let serverConn = serverConnection
        serverConnection = nil
        let pool = peerConnectionPool
        teardownTask = Task { [listenerService, natService, weak self] in
            await priorTeardown?.value
            await serverConn?.disconnect()
            await listenerService.stop()
            await natService.removeAllMappings()
            // Drop every peer socket. Without this, the next connect()
            // started dialing peers while the old sockets still existed,
            // and the pool's dict could carry ghost entries into the new
            // session — the "stale peer sockets" half of the auditor note.
            await pool.disconnectAll()
            // Distributed network teardown: the parent socket lives on
            // the server-message handler, the child sockets on self.
            // Both survive a reconnect without this, and the old parent
            // keeps feeding distributed search frames into the dead
            // session.
            await self?.tearDownDistributedParent()
            await self?.clearDistributedState()
        }

        isConnecting = false
        isConnected = false
        loggedIn = false
        listenPort = 0
        obfuscatedPort = 0
        externalIP = nil
        if publishDisconnectedStatus {
            emit(.statusChanged(.disconnected))
            logger.info("Disconnected")
        } else {
            logger.info("Connection teardown started for auto-reconnect")
        }
    }

    /// Called when connection drops unexpectedly — triggers auto-reconnect if eligible
    public func handleUnexpectedDisconnect(reason: String? = nil) {
        guard shouldAutoReconnect else { return }
        guard !isConnecting else { return }
        // A stale wake (late keepalive failure, an old receive loop ending
        // after teardown) must not tear down a session that's already gone —
        // or a healthy new one established since.
        guard isConnected else { return }

        // Record the actual connection loss once, but keep the public state
        // inside the reconnect flow so MainView never flashes LoginView.
        performDisconnect(reportActivity: true, publishDisconnectedStatus: false)
        scheduleReconnect(reason: reason)
    }

    /// Called when server sends Relogged (another client logged in) — no reconnect
    public func handleReloggedDisconnect() {
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        performDisconnect()
    }

    private func scheduleReconnect(reason: String? = nil) {
        guard shouldAutoReconnect,
              let server = lastServer,
              let port = lastPort,
              let password = lastPassword else { return }

        let delay = reconnectDelayOverrideForTesting
            ?? Self.reconnectDelay(afterFailedAttempts: reconnectAttempt)
        reconnectAttempt += 1

        let attempt = reconnectAttempt
        connectionError = reason ?? "Connection lost"
        emit(.statusChanged(.reconnecting))
        logger.info("Auto-reconnect attempt \(attempt) in \(delay)s")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return  // Cancelled
            }

            guard let self, await self.shouldAutoReconnect else { return }
            self.logger.info("Auto-reconnect attempt \(attempt) starting...")
            await self.performConnect(
                server: server,
                port: port,
                username: self.username,
                password: password,
                preferredListenPort: self.lastPreferredListenPort,
                origin: .autoReconnect
            )
        }
    }

    static func reconnectDelay(afterFailedAttempts count: Int) -> TimeInterval {
        let index = min(max(count, 0), reconnectDelays.count - 1)
        return reconnectDelays[index]
    }

    // MARK: - Keepalive

    /// Start periodic ping timer to keep connection alive
    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.pingInterval))
                    guard let self, await self.isConnected, let connection = await self.serverConnection else {
                        return
                    }
                    let pingMessage = MessageBuilder.pingMessage()
                    try await connection.send(pingMessage)
                    self.logger.debug("Sent keepalive ping")
                } catch is CancellationError {
                    return
                } catch {
                    self?.logger.error("Keepalive ping failed, connection is dead: \(error.localizedDescription)")
                    await self?.handleUnexpectedDisconnect(reason: "Keepalive failed")
                    return
                }
            }
        }
        logger.info("Keepalive ping timer started (interval: \(Self.pingInterval)s)")
    }

    // MARK: - NAT Setup (Background)

    /// NAT-PMP (and UPnP with a busy port) may grant a DIFFERENT external
    /// port than requested. Peers dial the external port, so the server must
    /// be re-told whenever the granted port differs from what login step 5
    /// advertised — otherwise peers dial a port the router doesn't forward.
    private var externalListenPort: UInt16 = 0      // 0 = no mapping / same as listenPort
    private var externalObfuscatedPort: UInt16 = 0
    private var lastAdvertisedListenPort: UInt16 = 0
    private var lastAdvertisedObfuscatedPort: UInt16 = 0

    /// A NAT lease refresh renumbered one of our external ports — record
    /// the new number and re-advertise to the server.
    private func applyExternalPortChange(internalPort: UInt16, newExternalPort: UInt16) async {
        if internalPort == listenPort {
            externalListenPort = newExternalPort
        } else if internalPort == obfuscatedPort {
            externalObfuscatedPort = newExternalPort
        } else {
            return
        }
        await readvertiseListenPortsIfNeeded()
    }

    private func readvertiseListenPortsIfNeeded() async {
        guard isConnected else { return }
        let effectivePort = externalListenPort > 0 ? externalListenPort : listenPort
        let effectiveObfuscated = externalObfuscatedPort > 0 ? externalObfuscatedPort : obfuscatedPort
        guard effectivePort != lastAdvertisedListenPort
                || effectiveObfuscated != lastAdvertisedObfuscatedPort else { return }
        do {
            let message = MessageBuilder.setListenPortMessage(
                port: UInt32(effectivePort),
                obfuscatedPort: UInt32(effectiveObfuscated)
            )
            try await requireConnectedServerConnection().send(message)
            lastAdvertisedListenPort = effectivePort
            lastAdvertisedObfuscatedPort = effectiveObfuscated
            logger.info("NAT: re-advertised external ports \(effectivePort) (obfuscated \(effectiveObfuscated)) to server")
        } catch {
            logger.warning("NAT: failed to re-advertise external port: \(error.localizedDescription)")
        }
    }

    private func setupNATInBackground() async {
        externalListenPort = 0
        externalObfuscatedPort = 0
        // Refresh can renumber a mapping (router reboot, lease churn) —
        // push the new external port to the server when it does.
        await natService.setOnExternalPortChanged { [weak self] internalPort, newExternalPort in
            Task { [weak self] in
                await self?.applyExternalPortChange(internalPort: internalPort, newExternalPort: newExternalPort)
            }
        }
        // Check if UPnP/NAT-PMP is enabled in settings
        let enableNAT = UserDefaults.standard.object(forKey: "settingsEnableUPnP") == nil
            ? true  // Default to enabled
            : UserDefaults.standard.bool(forKey: "settingsEnableUPnP")

        if !enableNAT {
            logger.info("NAT: Port mapping disabled in settings")
            // Still try to discover external IP via STUN/web service (non-invasive)
            if let extIP = await natService.discoverExternalIP() {
                externalIP = extIP
                logger.info("NAT: External IP: \(extIP)")
            }
            await syncNATDiagnostics()
            return
        }

        logger.info("NAT: Starting background port mapping...")

        // Add delay to avoid triggering IDS with rapid network activity at startup
        try? await Task.sleep(for: .seconds(2))

        // Try to map the listen port
        do {
            let mappedPort = try await natService.mapPort(listenPort)
            logger.info("NAT: Mapped port \(self.listenPort) -> \(mappedPort)")
            externalListenPort = mappedPort
        } catch {
            logger.warning("NAT: Port mapping failed (will rely on server-mediated connections)")
        }

        // Small delay between mapping attempts to avoid IDS triggers
        try? await Task.sleep(for: .milliseconds(500))

        // Try to map obfuscated port
        if obfuscatedPort > 0 {
            do {
                let mappedObfuscated = try await natService.mapPort(obfuscatedPort)
                logger.info("NAT: Mapped obfuscated port \(self.obfuscatedPort) -> \(mappedObfuscated)")
                externalObfuscatedPort = mappedObfuscated
            } catch {
                // Silent failure for obfuscated port
            }
        }

        // The router may have granted different external ports than the
        // ones login advertised — tell the server about the real ones.
        await readvertiseListenPortsIfNeeded()

        // Discover external IP
        if let extIP = await natService.discoverExternalIP() {
            externalIP = extIP
            logger.info("NAT: External IP: \(extIP)")
        }

        await syncNATDiagnostics()
        logger.info("NAT: Background setup complete")
    }

    /// Pulls the current gateway + mapping snapshot off the NAT actor and
    /// publishes it onto `self` for the diagnostics UI to observe. Cheap:
    /// called once after setup, not on every UI render.
    private func syncNATDiagnostics() async {
        let gateway = await natService.gatewayAddress
        let mappings = await natService.activeMappings
        let local = NATService.localInterfaceIP()
        natGateway = gateway
        natMappings = mappings
        localIP = local
    }

    // MARK: - Message Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self, let connection = await self.serverConnection else { return }

            for await message in connection.messages {
                await self.handleServerMessage(message)
            }

            // Stream ended. Only treat this as an unexpected disconnect when
            // the CONNECTION died — if `performDisconnect` cancelled this
            // task, teardown already ran and a second pass here would burn
            // an extra reconnect-backoff step (or, after a fast reconnect,
            // tear down the healthy new session).
            guard !Task.isCancelled else { return }
            await self.handleUnexpectedDisconnect(reason: "Connection closed")
        }
    }

    // MARK: - Peer-Operation State
    // Driven by NetworkClient+PeerOperations.swift (stored properties must
    // live in the type declaration, not extensions). Every pending dict
    // here must be covered by `failAllPendingPeerOperations` so no waiter
    // survives a disconnect.

    /// Coalesced concurrent `browseUser(_:)` calls.
    var pendingBrowseUserCalls: [String: Task<[SharedFile], Error>] = [:]

    /// Pending continuations for browse shares responses, keyed by username.
    /// At most one continuation per user at a time — guaranteed by the
    /// `pendingBrowseUserCalls` coalescing in `browseUser(_:)`.
    var pendingBrowseSharesContinuations: [String: CheckedContinuation<[SharedFile], Error>] = [:]

    var pendingBrowseStates: [UInt32: PendingBrowseState] = [:]

    /// Coalesce concurrent `establishPeerConnection` calls for the same peer.
    /// Without this, N parallel downloads to one peer each kick off their own
    /// ConnectToPeer + race, opening N independent TCP connections — wasteful
    /// and historically the source of the localPort=2235 4-tuple collision.
    var pendingEstablishments: [String: Task<PeerConnection, Error>] = [:]

    /// Last privileged flag the server actually reported per user. WatchUser
    /// replies don't carry privileged, so they pass nil and fall back to
    /// this instead of fabricating `false` (which could clobber a concurrent
    /// GetUserStatus waiter with wrong data).
    var lastKnownPrivileged: [String: Bool] = [:]

    /// Session-long cache of parsed UserInfoReply data, keyed by username.
    /// Populated whenever a reply arrives (either solicited via fetchUserInfo
    /// or unsolicited from any peer connection).
    var userInfoReplyCache: [String: MessageParser.UserInfoReplyInfo] = [:]

    /// In-flight fetch Tasks keyed by username, so concurrent callers for the
    /// same user share one network round-trip.
    var userInfoInFlight: [String: Task<MessageParser.UserInfoReplyInfo, Error>] = [:]

    /// Continuations awaiting a UserInfoReply from a specific peer. Resumed
    /// when the pool event arrives or when the timeout task fires.
    var userInfoReplyContinuations: [String: CheckedContinuation<MessageParser.UserInfoReplyInfo, Error>] = [:]

    /// Entries can carry multi-MB profile pictures and survive disconnect,
    /// so the cache needs a hard cap — without one, any peer that connects
    /// can park megabytes here forever by pushing an unsolicited reply.
    let maxUserInfoCacheEntries = 100

    /// Pending artwork request callbacks keyed by token.
    var artworkCallbacks: [UInt32: (Data?) -> Void] = [:]

    /// Coalesce concurrent `requestArtwork` calls for the same (peer, file).
    /// UI scenarios trigger multiple loaders for the same image (list cell +
    /// detail view + hover preview) at the same moment; without this, each
    /// loader opens its own token-based roundtrip and the peer is asked N
    /// times for the same artwork.
    var pendingArtworkRequests: [String: PendingArtworkRequest] = [:]

    // MARK: - Internal State Updates

    public func setLoggedIn(_ success: Bool, message: String?) {
        loggedIn = success
        if success {
            if let continuation = loginContinuation {
                loginContinuation = nil
                continuation.resume(returning: ())
            }
        } else {
            connectionError = message
            if let continuation = loginContinuation {
                loginContinuation = nil
                continuation.resume(throwing: ServerConnection.ConnectionError.loginFailed(message ?? "Unknown error"))
            }
            emit(.statusChanged(.disconnected))
        }
    }
}

// MARK: - Errors

enum NetworkError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case timeout
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout:
            return "Connection timed out"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}
