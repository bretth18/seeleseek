import Foundation
import Network
import os
import Synchronization

/// Main network interface that coordinates server and peer connections
@Observable
@MainActor
public final class NetworkClient {
    private nonisolated let logger = Logger(subsystem: "com.seeleseek", category: "NetworkClient")

    // MARK: - Connection State
    public private(set) var isConnecting = false
    public private(set) var isConnected = false
    public private(set) var connectionError: String?

    // MARK: - User Info
    public private(set) var username: String = ""
    public private(set) var loggedIn = false

    // MARK: - Network Info
    public private(set) var listenPort: UInt16 = 0
    public private(set) var obfuscatedPort: UInt16 = 0
    public private(set) var externalIP: String?

    /// Local interface IP (en0/en1). Set once at startup.
    public private(set) var localIP: String?
    /// Router gateway discovered by UPnP or inferred from the local subnet.
    /// Nil until NAT setup runs.
    public private(set) var natGateway: String?
    /// Port mappings we successfully registered via UPnP or NAT-PMP. Empty
    /// when mapping is disabled or all attempts failed.
    public private(set) var natMappings: [NATService.PortMapping] = []

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

    /// Current reachability classification. Recomputed on read from existing
    /// observable counters; no cache, no poll.
    public var reachability: Reachability {
        let pool = peerConnectionPool
        let directInbound = pool.peerInitCount
        let indirectWanted = pool.connectToPeerCount

        if directInbound > 0 {
            // At least one peer reached our port directly — definitively reachable.
            if !natMappings.isEmpty { return .upnpMapped }
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
    public var acceptDistributedChildren = true  // Participate in distributed search network
    public private(set) var distributedBranchLevel: UInt32 = 0
    public private(set) var distributedBranchRoot: String = ""
    public private(set) var distributedChildren: [PeerConnection] = []

    // MARK: - Internal
    private var serverConnection: ServerConnection?
    private var messageHandler: ServerMessageHandler?
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
    private var lastServer: String?
    private var lastPort: UInt16?
    private var lastPassword: String?
    private var lastPreferredListenPort: UInt16?
    /// Base delays for exponential backoff: 5s, 10s, 30s, 60s, then cap at 60s
    private static let reconnectDelays: [TimeInterval] = [5, 10, 30, 60]

    /// Host used for the current/last connect attempt. Exposed so the
    /// server-message handler can log the ACTUAL server instead of a
    /// hardcoded hostname.
    internal var serverHost: String? { lastServer }

    // MARK: - Keepalive Configuration
    /// Interval between ping messages (5 minutes)
    private static let pingInterval: TimeInterval = 300

    // Services
    private let listenerService = ListenerService()
    private let natService = NATService()

    // Peer connections - public for UI access
    public let peerConnectionPool = PeerConnectionPool()

    // Share manager
    public let shareManager = ShareManager()

    // Metadata reader for SeeleSeek artwork extension
    public var metadataReader: (any MetadataReading)?

    // User info cache (country codes, etc.)
    public let userInfoCache = UserInfoCache()

    // Stream consumer tasks (cancelled on disconnect for clean reconnect)
    private var listenerConsumerTask: Task<Void, Never>?
    private var poolEventConsumerTask: Task<Void, Never>?
    /// Session-independent — share rescans happen while disconnected too.
    private var shareCountsConsumerTask: Task<Void, Never>?

    // MARK: - Pending Peer Address Requests (for concurrent browse/folder requests)
    // Uses (continuation, requestID) to prevent double-resume when same user is requested multiple times
    private var pendingPeerAddressRequests: [String: [(continuation: CheckedContinuation<(ip: String, port: Int, obfuscatedPort: Int), Error>, requestID: UUID)]] = [:]

    /// Test-only: register a waiter without kicking off a server round-trip.
    /// Used to exercise the multi-waiter / timeout path independently of a
    /// live connection.
    internal func _awaitPeerAddressWaiter(
        for username: String,
        timeout: Duration
    ) async throws -> (ip: String, port: Int, obfuscatedPort: Int) {
        let requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pendingPeerAddressRequests[username, default: []].append(
                (continuation: continuation, requestID: requestID)
            )
            Task {
                try? await Task.sleep(for: timeout)
                guard var waiters = self.pendingPeerAddressRequests[username] else { return }
                guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
                let waiter = waiters.remove(at: idx)
                if waiters.isEmpty {
                    self.pendingPeerAddressRequests.removeValue(forKey: username)
                } else {
                    self.pendingPeerAddressRequests[username] = waiters
                }
                waiter.continuation.resume(throwing: NetworkError.timeout)
            }
        }
    }

    // MARK: - Pending Status Requests (for checking if user is online before browse/download)
    // Multi-waiter: concurrent callers for the same username all attach to
    // one server round-trip and get the same reply. Single-continuation
    // storage would silently orphan the earlier caller when a second call
    // overwrote the dict slot. Matches the shape of
    // `pendingPeerAddressRequests` — waiter identified by UUID so per-call
    // timeouts remove exactly one slot.
    private typealias PendingStatusWaiter = (
        continuation: CheckedContinuation<(status: UserStatus, privileged: Bool), Never>,
        requestID: UUID
    )
    private var pendingStatusRequests: [String: [PendingStatusWaiter]] = [:]

    /// Test-only: attach a waiter to `pendingStatusRequests` without
    /// sending a server round-trip. Used to exercise the multi-waiter
    /// coalescing and teardown paths independently of a live connection.
    internal func _awaitStatusWaiter(
        for username: String,
        timeout: Duration
    ) async -> (status: UserStatus, privileged: Bool) {
        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            pendingStatusRequests[username, default: []]
                .append((continuation: continuation, requestID: requestID))
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                guard var waiters = self.pendingStatusRequests[username] else { return }
                guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
                let waiter = waiters.remove(at: idx)
                if waiters.isEmpty {
                    self.pendingStatusRequests.removeValue(forKey: username)
                } else {
                    self.pendingStatusRequests[username] = waiters
                }
                waiter.continuation.resume(returning: (status: .offline, privileged: false))
            }
        }
    }

    /// Test-only: run the full disconnect peer-operation teardown without
    /// needing a live server connection. Returns when every pending waiter
    /// has been resolved (either thrown or resumed with `.offline`).
    internal func _failAllPendingPeerOperationsForTest(reason: String = "test") {
        failAllPendingPeerOperations(reason: reason)
    }

    /// Test-only: register a sentinel establishment task and return its
    /// handle. The task is a never-returning `await` — the test can
    /// confirm that disconnect-driven cancellation propagates into a
    /// real in-flight handshake by checking that the handle throws
    /// CancellationError afterwards.
    internal func _seedSentinelEstablishmentForTest(username: String) -> Task<PeerConnection, Error> {
        let task = Task<PeerConnection, Error> {
            // Sleep essentially forever until cancelled.
            try await Task.sleep(for: .seconds(3600))
            throw NetworkError.timeout
        }
        pendingEstablishments[username] = task
        return task
    }

    /// Test-only: attach a distributed child socket placeholder so tests
    /// can confirm `clearDistributedState` wipes it on teardown. We store
    /// a real idle PeerConnection so the disconnect call is exercised.
    internal func _seedDistributedChildForTest() -> PeerConnection {
        let info = PeerConnection.PeerInfo(username: "child", ip: "127.0.0.1", port: 1)
        let child = PeerConnection(peerInfo: info, type: .distributed, token: 0)
        distributedChildren.append(child)
        distributedBranchLevel = 5
        distributedBranchRoot = "root"
        return child
    }

    internal func _distributedChildCountForTest() -> Int {
        distributedChildren.count
    }

    internal func _distributedBranchLevelForTest() -> UInt32 {
        distributedBranchLevel
    }

    /// Test-only: run the peer-teardown half of `performDisconnect`
    /// (disconnectAll + distributed clear) without touching the server
    /// connection or listener. Matches what the real teardown Task does.
    internal func _runDisconnectTeardownForTest() async {
        await peerConnectionPool.disconnectAll()
        await clearDistributedState()
    }

    // MARK: - Initialization

    public init() {
        logger.info("NetworkClient initializing...")

        // Consume pool events via AsyncStream (replaces callback wiring).
        // Stream captured synchronously and Task body uses weak self per
        // iteration to avoid retaining self across the loop — `guard let
        // self` would strong-hold for the full loop lifetime, and the
        // loop only ends when the stream tears down (which only happens
        // when self deinits), creating a cycle.
        // Serialized: this single long-lived task awaits each handler in
        // turn, so cross-event ordering per peer is preserved — a
        // transferResponse can't leapfrog the queueUpload that preceded
        // it, and handlers don't interleave at suspension points.
        let poolEvents = peerConnectionPool.events
        poolEventConsumerTask = Task { [weak self] in
            for await event in poolEvents {
                await self?.handlePoolEvent(event)
            }
        }

        // Re-broadcast `SharedFoldersFiles` whenever the local share
        // index changes. Without this the login broadcast (which races
        // the disk rescan and usually loses) leaves the server reporting
        // "0 shared files" until the user reconnects with the scan
        // already cached. `updateShareCounts` is a no-op while
        // disconnected, so pre-login events are harmless.
        //
        // The continuation is registered SYNCHRONOUSLY here (not inside
        // the Task body) so it exists before any other Task can run on
        // MainActor — `countsChangesStream()`'s init closure fires
        // immediately and stamps `continuations[id] = continuation`. If
        // we instead called it inside the Task body, a `Task { await
        // rescanAll() }` queued on the same MainActor could run first,
        // fire `notifyCountsChanged()` against an empty `continuations`
        // dict, and the yield would be lost. AsyncStream's buffer covers
        // post-registration delivery, NOT pre-registration yields.
        //
        // Closure captures only the stream value; no `[weak self]`
        // strong-ification inside a `for await` (which would retain
        // self for the loop's lifetime — i.e. forever, since the loop
        // only exits when the continuation tears down, which only
        // happens when self deinits).
        let countsStream = shareManager.countsChangesStream()
        shareCountsConsumerTask = Task { [weak self] in
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
            onSearchResults?(token, results)

        case .fileTransferConnection(let username, let token, let connection):
            await onFileTransferConnection?(username, token, connection)

        case .pierceFirewall(let token, let connection):
            if await handlePierceFirewallForBrowse(token: token, connection: connection) { return }
            await onPierceFirewall?(token, connection)

        case .uploadDenied(let username, let filename, let reason):
            onUploadDenied?(username, filename, reason)

        case .uploadFailed(let username, let filename):
            onUploadFailed?(username, filename)

        case .queueUpload(let username, let filename, let connection):
            await onQueueUpload?(username, filename, connection)

        case .transferResponse(let token, let allowed, let filesize, let reason, let connection):
            await onTransferResponse?(token, allowed, filesize, reason, connection)

        case .folderContentsRequest(let username, let token, let folder, let connection):
            await handleFolderContentsRequest(username: username, token: token, folder: folder, connection: connection)

        case .folderContentsResponse(let token, let folder, let files):
            onFolderContentsResponse?(token, folder, files)

        case .transferRequest(let request, let connection):
            onTransferRequest?(request, connection)

        case .placeInQueueRequest(let username, let filename, let connection):
            await onPlaceInQueueRequest?(username, filename, connection)

        case .placeInQueueReply(let username, let filename, let position):
            await onPlaceInQueueReply?(username, filename, position)

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
            userInfoCache.registerIP(ip, for: username)

        case .artworkReply(let token, let imageData):
            if let callback = artworkCallbacks.removeValue(forKey: token) {
                callback(imageData.isEmpty ? nil : imageData)
            }
        }
    }

    // MARK: - Callbacks
    public var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    public var onSearchResults: ((UInt32, [SearchResult]) -> Void)?  // (token, results)
    public var onRoomList: (([ChatRoom]) -> Void)?
    public var onRoomListFull: ((_ publicRooms: [ChatRoom], _ ownedPrivate: [ChatRoom], _ memberPrivate: [ChatRoom], _ operated: [String]) -> Void)?
    public var onRoomMessage: ((String, ChatMessage) -> Void)?
    public var onPrivateMessage: ((String, ChatMessage) -> Void)?
    public var onRoomJoined: ((String, [String], String?, [String]) -> Void)?  // (room, users, owner?, operators)
    public var onRoomLeft: ((String) -> Void)?
    public var onUserJoinedRoom: ((String, String) -> Void)?
    public var onUserLeftRoom: ((String, String) -> Void)?

    // Multi-listener support for peer address responses
    // This fixes the issue where DownloadManager and UploadManager callbacks could overwrite each other
    private var peerAddressHandlers: [(String, String, Int) -> Void] = []

    /// Add a handler for peer address responses (supports multiple listeners)
    public func addPeerAddressHandler(_ handler: @escaping (String, String, Int) -> Void) {
        peerAddressHandlers.append(handler)
        logger.debug("NetworkClient: Added peer address handler (total: \(self.peerAddressHandlers.count))")
    }
    public var onFileTransferConnection: ((String, UInt32, PeerConnection) async -> Void)?  // (username, token, connection)
    public var onPierceFirewall: ((UInt32, PeerConnection) async -> Void)?  // (token, connection)
    public var onUploadDenied: ((String, String, String) -> Void)?  // (username, filename, reason)
    public var onUploadFailed: ((String, String) -> Void)?  // (username, filename)
    public var onQueueUpload: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection) - peer wants to download from us
    public var onTransferResponse: ((UInt32, Bool, UInt64?, String?, PeerConnection) async -> Void)?  // (token, allowed, filesize?, reason?, connection)
    public var onFolderContentsResponse: ((UInt32, String, [SharedFile]) -> Void)?  // (token, folder, files)
    public var onTransferRequest: ((TransferRequest, PeerConnection) -> Void)?  // (request, connection that delivered it). The connection is critical: peers can deliver TransferRequests on a different connection than the one we cached when queueing the download.
    public var onPlaceInQueueRequest: ((String, String, PeerConnection) async -> Void)?  // (username, filename, connection)
    public var onPlaceInQueueReply: ((String, String, UInt32) async -> Void)?  // (username, filename, position)

    // User interests & recommendations callbacks
    public var onRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    public var onGlobalRecommendations: (([(item: String, score: Int32)], [(item: String, score: Int32)]) -> Void)?  // (recommendations, unrecommendations)
    public var onUserInterests: ((String, [String], [String]) -> Void)?  // (username, likes, hates)
    public var onSimilarUsers: (([(username: String, rating: UInt32)]) -> Void)?
    public var onItemRecommendations: ((String, [(item: String, score: Int32)]) -> Void)?  // (item, recommendations)
    public var onItemSimilarUsers: ((String, [String]) -> Void)?  // (item, users)

    // Profile data provider - returns (description, picture) for UserInfoResponse
    public var profileDataProvider: ( () -> (description: String, picture: Data?))?

    // Search response filter - returns (respondToSearches, minQueryLength, maxResults)
    public var searchResponseFilter: ( () -> (enabled: Bool, minQueryLength: Int, maxResults: Int))?

    /// Set by the app layer (AppState) to answer "is this username on
    /// our buddy list?" without the core package needing to know about
    /// SocialState. Used by the shares-reply and distributed-search
    /// handlers to decide whether to expose folders marked `.buddies`.
    /// Returns false when nil so shares default to public-only if the
    /// app forgot to wire this up.
    public var isBuddyChecker: ((String) -> Bool)?

    // User stats & privileges callbacks
    private var userStatusHandlers: [(String, UserStatus, Bool) -> Void] = []
    /// Register a handler for user status updates. Multiple handlers supported.
    public func addUserStatusHandler(_ handler: @escaping (String, UserStatus, Bool) -> Void) {
        userStatusHandlers.append(handler)
    }
    private var userStatsHandlers: [(String, UInt32, UInt64, UInt32, UInt32) -> Void] = []
    /// Register a handler for user stats updates. Multiple handlers supported.
    public func addUserStatsHandler(_ handler: @escaping (String, UInt32, UInt64, UInt32, UInt32) -> Void) {
        userStatsHandlers.append(handler)
    }
    /// Dispatch user stats to all registered handlers
    public func dispatchUserStats(username: String, avgSpeed: UInt32, uploadNum: UInt64, files: UInt32, dirs: UInt32) {
        for handler in userStatsHandlers {
            handler(username, avgSpeed, uploadNum, files, dirs)
        }
    }
    public var onPrivilegesChecked: ((UInt32) -> Void)?  // timeLeft in seconds
    public var onUserPrivileges: ((String, Bool) -> Void)?  // (username, privileged)
    public var onPrivilegedUsers: (([String]) -> Void)?  // list of privileged usernames

    // Room ticker callbacks
    public var onRoomTickerState: ((String, [(username: String, ticker: String)]) -> Void)?  // (room, tickers)
    public var onRoomTickerAdd: ((String, String, String) -> Void)?  // (room, username, ticker)
    public var onRoomTickerRemove: ((String, String) -> Void)?  // (room, username)

    // Wishlist callback
    public var onWishlistInterval: ((UInt32) -> Void)?  // interval in seconds

    // Private room callbacks
    public var onPrivateRoomMembers: ((String, [String]) -> Void)?  // (room, members)
    public var onPrivateRoomMemberAdded: ((String, String) -> Void)?  // (room, username)
    public var onPrivateRoomMemberRemoved: ((String, String) -> Void)?  // (room, username)
    public var onPrivateRoomOperatorGranted: ((String) -> Void)?  // room
    public var onPrivateRoomOperatorRevoked: ((String) -> Void)?  // room
    public var onPrivateRoomOperators: ((String, [String]) -> Void)?  // (room, operators)

    // Admin/system message callback
    public var onAdminMessage: ((String) -> Void)?  // Server-wide admin message

    // Excluded search phrases callback
    public var onExcludedSearchPhrases: (([String]) -> Void)?  // Phrases excluded from search by server

    // Room membership callbacks
    public var onRoomMembershipGranted: ((String) -> Void)?  // room name
    public var onRoomMembershipRevoked: ((String) -> Void)?  // room name
    public var onRoomInvitationsEnabled: ((Bool) -> Void)?  // enabled
    public var onPasswordChanged: ((String) -> Void)?  // confirmed password
    public var onRoomAdded: ((String) -> Void)?  // room name
    public var onRoomRemoved: ((String) -> Void)?  // room name

    // Can't create room callback
    public var onCantCreateRoom: ((String) -> Void)?  // room name

    // Can't connect to peer callback (server tells us indirect connection failed)
    public var onCantConnectToPeer: ((UInt32) -> Void)?  // token

    // Global room callback
    public var onGlobalRoomMessage: ((String, String, String) -> Void)?  // (room, username, message)
    public var onProtocolNotice: ((UInt32, Data) -> Void)?  // (server code, raw payload)

    // MARK: - Connection

    public func connect(server: String, port: UInt16, username: String, password: String, preferredListenPort: UInt16? = nil) async {
        guard !isConnecting && !isConnected else { return }

        // Store for auto-reconnect
        lastServer = server
        lastPort = port
        lastPassword = password
        lastPreferredListenPort = preferredListenPort
        shouldAutoReconnect = true
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil

        isConnecting = true
        connectionError = nil
        self.username = username
        peerConnectionPool.ourUsername = username  // Set for PeerInit messages
        onConnectionStatusChanged?(.connecting)

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
            // Weak self per iteration — see `poolEventConsumerTask` for the
            // retain-cycle rationale.
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
            messageHandler = ServerMessageHandler(client: self)

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
                // Route through the full teardown so the listener, NAT, peer
                // pool, pending waiters, distributed state, and server socket
                // all get cleaned up — previously this path only stopped the
                // listener, leaving stale state for the next connect().
                isConnecting = false
                connectionError = error.localizedDescription
                // Only a credential rejection should disable auto-reconnect;
                // a timeout or socket error during the handshake is transient
                // and the user asked for a persistent connection.
                let wasEligibleForReconnect: Bool
                if case ServerConnection.ConnectionError.loginFailed = error {
                    shouldAutoReconnect = false
                    wasEligibleForReconnect = false
                } else {
                    wasEligibleForReconnect = shouldAutoReconnect
                }
                performDisconnect()
                await teardownTask?.value
                if wasEligibleForReconnect {
                    scheduleReconnect(reason: error.localizedDescription)
                }
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
            let folders = UInt32(shareManager.totalFolders)
            let files = UInt32(shareManager.totalFiles)
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
            onConnectionStatusChanged?(.connected)
            logger.info("Login successful!")

            // Start keepalive ping timer
            startPingTimer()

            // Run NAT mapping in background (don't block connection)
            Task {
                await self.setupNATInBackground()
            }

        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            isConnecting = false
            connectionError = error.localizedDescription

            // Route through the full teardown (listener + NAT + peer pool +
            // pending waiters + distributed state + server socket) instead
            // of only stopping the listener. Partially-established sessions
            // can otherwise leak server connections, distributed sockets,
            // or peer-pool entries into the next connect().
            let wasEligibleForReconnect = shouldAutoReconnect
            performDisconnect()
            await teardownTask?.value

            // performDisconnect fires onConnectionStatusChanged(.disconnected)
            // itself; the scheduleReconnect path takes over status updates
            // from here (.connecting, etc.).
            if wasEligibleForReconnect {
                scheduleReconnect(reason: error.localizedDescription)
            }
        }
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
    private func performDisconnect() {
        logger.info("Disconnecting...")
        ActivityLogger.shared?.logDisconnected()

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
        let handler = messageHandler
        messageHandler = nil
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
            await handler?.tearDownDistributedParent()
            await self?.clearDistributedState()
        }

        isConnected = false
        loggedIn = false
        listenPort = 0
        obfuscatedPort = 0
        externalIP = nil
        onConnectionStatusChanged?(.disconnected)

        logger.info("Disconnected")
    }

    /// Resume every peer-operation continuation with an error so no caller
    /// stays blocked across a disconnect. Covers every pending-dict used in
    /// `establishPeerConnection` / browse / status / artwork paths.
    private func failAllPendingPeerOperations(reason: String) {
        let error = NetworkError.connectionFailed(reason)

        for (_, waiters) in pendingPeerAddressRequests {
            for waiter in waiters {
                waiter.continuation.resume(throwing: error)
            }
        }
        pendingPeerAddressRequests.removeAll()

        for (_, waiters) in pendingStatusRequests {
            for waiter in waiters {
                waiter.continuation.resume(returning: (status: .offline, privileged: false))
            }
        }
        pendingStatusRequests.removeAll()

        for (_, continuation) in pendingBrowseSharesContinuations {
            continuation.resume(throwing: error)
        }
        pendingBrowseSharesContinuations.removeAll()

        for (token, state) in pendingBrowseStates {
            state.timeoutTask?.cancel()
            state.continuation?.resume(throwing: error)
            // The cancelled timeout task was the one path that would have
            // cleared the pool's expected-username entry — clear it here or
            // it leaks one entry per in-flight establishment per disconnect
            // (and risks stamping a stale username on a token collision in
            // a later session).
            peerConnectionPool.clearExpectedPierceFirewallUsername(token: token)
        }
        pendingBrowseStates.removeAll()

        // Cancel each in-flight establishment task. `removeAll()` alone
        // just drops our handle to the task — it keeps running, can
        // complete after disconnect, and hands a live PeerConnection
        // back to a caller whose session is already dead. Cancelling
        // propagates cooperative cancellation into the direct-dial /
        // PierceFirewall race so the awaiter sees CancellationError
        // instead of a zombie connection.
        for (_, task) in pendingEstablishments {
            task.cancel()
        }
        pendingEstablishments.removeAll()

        for (_, continuation) in userInfoReplyContinuations {
            continuation.resume(throwing: error)
        }
        userInfoReplyContinuations.removeAll()
        // Same story as pendingEstablishments: the inner task could be
        // mid-handshake with a peer. Cancel before dropping so the
        // `try await task.value` caller unwinds.
        for (_, task) in userInfoInFlight {
            task.cancel()
        }
        userInfoInFlight.removeAll()
        // Leave `userInfoReplyCache` intact — cached peer metadata isn't
        // invalidated by a server reconnect; users can still be looked up
        // by the next session without a fresh round-trip.

        for (_, pending) in pendingArtworkRequests {
            artworkCallbacks.removeValue(forKey: pending.token)
            for waiter in pending.waiters {
                waiter(nil)
            }
        }
        pendingArtworkRequests.removeAll()
        // Any dangling artwork callbacks whose pending entry was already
        // torn down earlier — drop them too so the next session starts clean.
        artworkCallbacks.removeAll()
    }

    /// Called when connection drops unexpectedly — triggers auto-reconnect if eligible
    public func handleUnexpectedDisconnect(reason: String? = nil) {
        guard shouldAutoReconnect else { return }
        guard !isConnecting else { return }
        // A stale wake (late keepalive failure, an old receive loop ending
        // after teardown) must not tear down a session that's already gone —
        // or a healthy new one established since.
        guard isConnected else { return }

        performDisconnect()
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

        let delayIndex = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[delayIndex]
        reconnectAttempt += 1

        let attempt = reconnectAttempt
        connectionError = reason ?? "Connection lost"
        onConnectionStatusChanged?(.reconnecting)
        logger.info("Auto-reconnect attempt \(attempt) in \(delay)s")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return  // Cancelled
            }

            guard let self, self.shouldAutoReconnect else { return }
            self.logger.info("Auto-reconnect attempt \(attempt) starting...")
            await self.connect(
                server: server,
                port: port,
                username: self.username,
                password: password,
                preferredListenPort: self.lastPreferredListenPort
            )
        }
    }

    // MARK: - Keepalive

    /// Start periodic ping timer to keep connection alive
    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.pingInterval))
                    guard let self = self, self.isConnected, let connection = self.serverConnection else {
                        return
                    }
                    let pingMessage = MessageBuilder.pingMessage()
                    try await connection.send(pingMessage)
                    self.logger.debug("Sent keepalive ping")
                } catch is CancellationError {
                    return
                } catch {
                    self?.logger.error("Keepalive ping failed, connection is dead: \(error.localizedDescription)")
                    self?.handleUnexpectedDisconnect(reason: "Keepalive failed")
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                if internalPort == self.listenPort {
                    self.externalListenPort = newExternalPort
                } else if internalPort == self.obfuscatedPort {
                    self.externalObfuscatedPort = newExternalPort
                } else {
                    return
                }
                await self.readvertiseListenPortsIfNeeded()
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
                await MainActor.run {
                    self.externalIP = extIP
                }
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
            await MainActor.run {
                self.externalIP = extIP
            }
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
        await MainActor.run {
            self.natGateway = gateway
            self.natMappings = mappings
            self.localIP = local
        }
    }

    // MARK: - Message Receiving

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self = self, let connection = self.serverConnection else { return }

            for await message in connection.messages {
                await self.handleMessage(message)
            }

            // Stream ended. Only treat this as an unexpected disconnect when
            // the CONNECTION died — if `performDisconnect` cancelled this
            // task, teardown already ran and a second pass here would burn
            // an extra reconnect-backoff step (or, after a fast reconnect,
            // tear down the healthy new session).
            guard !Task.isCancelled else { return }
            self.handleUnexpectedDisconnect(reason: "Connection closed")
        }
    }

    private func handleMessage(_ data: Data) async {
        await messageHandler?.handle(data)
    }

    // MARK: - Server Commands

    // SECURITY: Maximum search query length
    private static let maxSearchQueryLength = 500

    private func requireConnectedServerConnection() throws -> ServerConnection {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }
        return connection
    }

    public func search(query: String, token: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // Sanitize: truncate, normalize Unicode, and clean for SoulSeek compatibility
        let sanitizedQuery = Self.sanitizeSearchQuery(query)

        guard !sanitizedQuery.isEmpty else {
            throw NetworkError.invalidResponse
        }

        let message = MessageBuilder.fileSearchMessage(token: token, query: sanitizedQuery)
        try await connection.send(message)
        logger.info("Sent search request: query='\(sanitizedQuery)' token=\(token)")
    }

    /// Sanitize a search query for SoulSeek protocol compatibility
    private static func sanitizeSearchQuery(_ query: String) -> String {
        var q = String(query.prefix(maxSearchQueryLength))

        // Normalize Unicode: smart/curly quotes → ASCII, em-dash → hyphen, etc.
        // NFKD decomposes compatibility characters, then we replace known offenders
        q = q.precomposedStringWithCompatibilityMapping
        q = q.replacingOccurrences(of: "\u{2018}", with: "'")  // left single quote
            .replacingOccurrences(of: "\u{2019}", with: "'")    // right single quote
            .replacingOccurrences(of: "\u{201C}", with: "\"")   // left double quote
            .replacingOccurrences(of: "\u{201D}", with: "\"")   // right double quote
            .replacingOccurrences(of: "\u{2013}", with: "-")    // en-dash
            .replacingOccurrences(of: "\u{2014}", with: "-")    // em-dash

        // Collapse multiple spaces
        while q.contains("  ") {
            q = q.replacingOccurrences(of: "  ", with: " ")
        }

        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getRoomList() async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.getRoomListMessage()
        try await connection.send(message)
    }

    public func joinRoom(_ name: String, isPrivate: Bool = false) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.joinRoomMessage(roomName: name, isPrivate: isPrivate)
        try await connection.send(message)
    }

    public func leaveRoom(_ name: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.leaveRoomMessage(roomName: name)
        try await connection.send(message)
    }

    // SECURITY: Maximum chat message length
    private static let maxMessageLength = 2000
    // SECURITY: Maximum username/room name length
    private static let maxNameLength = 100

    public func sendRoomMessage(_ room: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // SECURITY: Validate and sanitize input
        let sanitizedRoom = String(room.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedRoom.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.sayInChatRoomMessage(roomName: sanitizedRoom, message: sanitizedMessage)
        try await connection.send(data)
    }

    public func sendPrivateMessage(to username: String, message: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        // SECURITY: Validate and sanitize input
        let sanitizedUsername = String(username.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedUsername.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.privateMessageMessage(username: sanitizedUsername, message: sanitizedMessage)
        try await connection.send(data)
    }

    public func getUserAddress(_ username: String) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.getUserAddress(username)
        try await connection.send(message)
    }

    public func setStatus(_ status: UserStatus) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.setOnlineStatusMessage(status: status)
        try await connection.send(message)
    }

    public func setSharedFilesCount(_ files: UInt32, directories: UInt32) async throws {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }

        let message = MessageBuilder.sharedFoldersFilesMessage(folders: directories, files: files)
        try await connection.send(message)
    }

    /// Tell server we couldn't connect to a peer (used by peer responding to us)
    public func sendCantConnectToPeer(token: UInt32, username: String) async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.cantConnectToPeer(token: token, username: username)
        do {
            try await connection.send(message)
            logger.info("Sent CantConnectToPeer for \(username) token=\(token)")
        } catch {
            logger.error("Failed to send CantConnectToPeer: \(error.localizedDescription)")
        }
    }

    /// Acknowledge a private message to the server (code 23)
    public func acknowledgePrivateMessage(messageId: UInt32) async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.acknowledgePrivateMessageMessage(messageId: messageId)
        do {
            try await connection.send(message)
            logger.info("Acknowledged private message \(messageId)")
        } catch {
            logger.error("Failed to acknowledge private message: \(error.localizedDescription)")
        }
    }

    /// Request server to tell peer to connect to us (indirect connection request)
    /// Server will forward this to the peer, who will then send PierceFirewall to us
    public func sendConnectToPeer(token: UInt32, username: String, connectionType: String = "P") async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.connectToPeerMessage(token: token, username: username, connectionType: connectionType)
        do {
            try await connection.send(message)
            logger.info("Sent ConnectToPeer for \(username) token=\(token) type=\(connectionType)")
        } catch {
            logger.error("Failed to send ConnectToPeer: \(error.localizedDescription)")
        }
    }

    // MARK: - Peer Address Response Handling

    /// Internal handler for peer address responses - dispatches to pending requests AND all registered handlers
    public func handlePeerAddressResponse(username: String, ip: String, port: Int, obfuscatedPort: Int = 0) {
        logger.debug("handlePeerAddressResponse: \(username) @ \(ip):\(port) obfuscatedPort=\(obfuscatedPort)")

        if let waiters = pendingPeerAddressRequests.removeValue(forKey: username) {
            logger.debug("Resuming \(waiters.count) pending getPeerAddress continuation(s) for \(username)")
            for waiter in waiters {
                waiter.continuation.resume(returning: (ip, port, obfuscatedPort))
            }
        }

        // Call all registered handlers (multi-listener pattern). Note: an
        // empty handler list is normal — the internal continuation path
        // above already consumes responses for coalesced requests.
        if !peerAddressHandlers.isEmpty {
            logger.debug("Calling \(self.peerAddressHandlers.count) registered peer address handlers")
            for handler in peerAddressHandlers {
                handler(username, ip, port)
            }
        }
    }

    /// Request peer address and wait for response (concurrent-safe)
    /// Can be called from multiple places concurrently - each request gets its own continuation
    public func getPeerAddress(for username: String, timeout: Duration = .seconds(10)) async throws -> (ip: String, port: Int, obfuscatedPort: Int) {
        let requestID = UUID()
        let alreadyInFlight = (pendingPeerAddressRequests[username]?.isEmpty == false)

        return try await withCheckedThrowingContinuation { continuation in
            pendingPeerAddressRequests[username, default: []].append(
                (continuation: continuation, requestID: requestID)
            )

            if !alreadyInFlight {
                Task {
                    do {
                        try await self.getUserAddress(username)
                    } catch {
                        if let waiters = self.pendingPeerAddressRequests.removeValue(forKey: username) {
                            for waiter in waiters {
                                waiter.continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }

            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                guard var waiters = self.pendingPeerAddressRequests[username] else { return }
                guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
                let waiter = waiters.remove(at: idx)
                if waiters.isEmpty {
                    self.pendingPeerAddressRequests.removeValue(forKey: username)
                } else {
                    self.pendingPeerAddressRequests[username] = waiters
                }
                waiter.continuation.resume(throwing: NetworkError.timeout)
            }
        }
    }

    // MARK: - Peer Connections

    // Pending browse requests waiting for indirect connections (keyed by TOKEN)
    // When peer connects via PierceFirewall, they send the same token we used in ConnectToPeer
    // (pendingBrowseStates is defined below in the browse section)

    /// Browse a user's shared files. Concurrent callers for the same `username`
    /// are coalesced into a single establishment + a single `requestShares`
    /// roundtrip, and all receive the same `[SharedFile]` result.
    ///
    /// Two layers of coalescing happen here:
    ///   1. `pendingBrowseUserCalls` dedups the *whole operation* (connection
    ///      + request + reply wait) so we don't issue N requestShares to
    ///      the same peer on N concurrent browses.
    ///   2. `establishPeerConnection` (called inside) dedups just the
    ///      connection establishment, which also benefits non-browse
    ///      consumers like fetchUserInfo running in parallel.
    public func browseUser(_ username: String) async throws -> [SharedFile] {
        if let inFlight = pendingBrowseUserCalls[username] {
            return try await inFlight.value
        }

        let task = Task<[SharedFile], Error> { [weak self] in
            // Task {} inherits MainActor isolation here, so the coalescing
            // map can be cleaned synchronously in the defer (same shape as
            // fetchUserInfo) — no re-hop Task needed.
            defer { self?.pendingBrowseUserCalls.removeValue(forKey: username) }
            guard let self else { throw NetworkError.notConnected }
            return try await self._performBrowseUser(username)
        }
        pendingBrowseUserCalls[username] = task
        return try await task.value
    }

    /// Coalesced concurrent `browseUser(_:)` calls.
    private var pendingBrowseUserCalls: [String: Task<[SharedFile], Error>] = [:]

    private func _performBrowseUser(_ username: String) async throws -> [SharedFile] {
        logger.debug("Browse: START browseUser(\(username))")
        // Earlier code passed `forceFresh: true` here. Tracing the history
        // (c950b1f → b80a28e → 4b73571 → ...) the original commit added
        // the behavior with the inline comment "Always create a fresh
        // connection for browse" — no justification given. The later
        // refactor that introduced `forceFresh` admitted as much
        // ("preserved until we have evidence reuse is safe"). With no
        // documented concrete failure mode, removed. Watch for browse-
        // returning-stale-data or browse-blocking-other-messages
        // regressions; if they appear, restore `forceFresh` and document
        // the actual reason this time.
        let connection = try await establishPeerConnection(for: username)

        logger.debug("Browse: Requesting shares from \(username)...")
        try await connection.requestShares()

        // Wait for sharesReceived event via pool stream (arrives in handlePoolEvent)
        let files = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SharedFile], Error>) in
            // The connection dance above can outlive the session: if a
            // disconnect ran `failAllPendingPeerOperations` in the interim,
            // registering a fresh continuation now would orphan it until
            // the 30s timeout. Fail fast instead.
            guard isConnected else {
                continuation.resume(throwing: NetworkError.notConnected)
                return
            }
            pendingBrowseSharesContinuations[username] = continuation

            // Timeout after 30 seconds. Fire-and-forget: idempotent via
            // `removeValue` — if the reply arrives first the continuation
            // is already gone, so this wakes to a no-op. Not worth tracking
            // per-call; outer `browseUser` is coalesced and itself owned.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if let cont = self?.pendingBrowseSharesContinuations.removeValue(forKey: username) {
                    cont.resume(throwing: NetworkError.timeout)
                }
            }
        }

        logger.debug("Browse: Got \(files.count) files from \(username)")
        return files
    }

    /// Pending continuations for browse shares responses, keyed by username.
    /// At most one continuation per user at a time — guaranteed by the
    /// `pendingBrowseUserCalls` coalescing in `browseUser(_:)`.
    private var pendingBrowseSharesContinuations: [String: CheckedContinuation<[SharedFile], Error>] = [:]

    // Pending browse state - tracks both waiting and received connections
    private struct PendingBrowseState {
        let username: String
        var continuation: CheckedContinuation<PeerConnection, Error>?
        var receivedConnection: PeerConnection?  // Set if PierceFirewall arrives before we start waiting
        var timeoutTask: Task<Void, Never>?
        var timedOut = false
        var failureReason: String?  // Set by CantConnectToPeer to fail the wait fast
    }
    private var pendingBrowseStates: [UInt32: PendingBrowseState] = [:]

    /// Coalesce concurrent `establishPeerConnection` calls for the same peer.
    /// Without this, N parallel downloads to one peer each kick off their own
    /// ConnectToPeer + race, opening N independent TCP connections — wasteful
    /// and historically the source of the localPort=2235 4-tuple collision.
    private var pendingEstablishments: [String: Task<PeerConnection, Error>] = [:]

    /// Register a pending browse BEFORE sending ConnectToPeer (to avoid race condition)
    public func registerPendingBrowse(token: UInt32, username: String, timeout: TimeInterval) {
        var state = PendingBrowseState(username: username)

        // Set up timeout
        state.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self else { return }

            // If still pending without a connection, fail the waiter and
            // drop the entry — nothing consumes it after this point, and
            // leaving it in the dict leaked one entry per failed browse
            // (and let a late PierceFirewall park an orphaned socket in it).
            if var pending = self.pendingBrowseStates[token] {
                if pending.receivedConnection == nil {
                    logger.warning("Browse: Timeout waiting for PierceFirewall from \(pending.username) (token=\(token))")
                    if let continuation = pending.continuation {
                        pending.continuation = nil
                        continuation.resume(throwing: NetworkError.timeout)
                    }
                    self.pendingBrowseStates.removeValue(forKey: token)
                }
            }
            // Clear any leftover username pre-registration.
            self.peerConnectionPool.clearExpectedPierceFirewallUsername(token: token)
        }

        pendingBrowseStates[token] = state
        // Pre-register the username the pool should stamp on whatever indirect
        // connection arrives bearing this token. Done here so it's set BEFORE
        // we send ConnectToPeer (next call from the caller). See
        // `pierceFirewallExpectedUsernames` for the rationale.
        peerConnectionPool.registerExpectedPierceFirewallUsername(token: token, username: username)
    }

    /// Wait for a previously registered pending browse to receive PierceFirewall
    public func waitForPendingBrowse(token: UInt32) async throws -> PeerConnection {
        // Check if connection already arrived (or failed)
        if let state = pendingBrowseStates[token] {
            if let connection = state.receivedConnection {
                logger.debug("Browse: PierceFirewall already received for token=\(token)")
                pendingBrowseStates.removeValue(forKey: token)
                return connection
            }
            if state.timedOut {
                pendingBrowseStates.removeValue(forKey: token)
                throw NetworkError.timeout
            }
            if let reason = state.failureReason {
                pendingBrowseStates.removeValue(forKey: token)
                throw NetworkError.connectionFailed(reason)
            }
        }

        // Wait for connection. Cancellation-aware: callers race this waiter
        // against a direct connect inside task groups — without the handler,
        // group.cancelAll() can't unwind the waiter and the group blocks at
        // scope exit until the registration timeout fires.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if var state = pendingBrowseStates[token] {
                    // Check again if connection arrived while we were setting up
                    if let connection = state.receivedConnection {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(returning: connection)
                        return
                    }
                    if state.timedOut {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(throwing: NetworkError.timeout)
                        return
                    }
                    if let reason = state.failureReason {
                        pendingBrowseStates.removeValue(forKey: token)
                        continuation.resume(throwing: NetworkError.connectionFailed(reason))
                        return
                    }
                    state.continuation = continuation
                    pendingBrowseStates[token] = state
                } else {
                    // Token was already removed (cancelled or error)
                    continuation.resume(throwing: NetworkError.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaitForPendingBrowse(token: token)
            }
        }
    }

    /// Unblock a cancelled `waitForPendingBrowse` waiter. The entry itself
    /// stays registered (minus the waiter) so a late PierceFirewall is still
    /// matched and cleaned up rather than falling through unhandled.
    private func cancelWaitForPendingBrowse(token: UInt32) {
        guard var state = pendingBrowseStates[token],
              let continuation = state.continuation else { return }
        state.continuation = nil
        pendingBrowseStates[token] = state
        continuation.resume(throwing: CancellationError())
    }

    /// Mark a pending browse as failed (e.g. server sent CantConnectToPeer).
    /// The waiter, if any, fails fast instead of sitting on the 30s timeout.
    public func failPendingBrowse(token: UInt32, reason: String) {
        guard var state = pendingBrowseStates[token] else { return }
        state.timeoutTask?.cancel()
        state.failureReason = reason
        peerConnectionPool.clearExpectedPierceFirewallUsername(token: token)
        if let continuation = state.continuation {
            state.continuation = nil
            pendingBrowseStates.removeValue(forKey: token)
            continuation.resume(throwing: NetworkError.connectionFailed(reason))
            return
        }
        pendingBrowseStates[token] = state
    }

    /// Cancel a pending browse (used when direct connection succeeds or search delivery completes)
    public func cancelPendingBrowse(token: UInt32) {
        if let state = pendingBrowseStates.removeValue(forKey: token) {
            state.timeoutTask?.cancel()
            // Don't resume continuation - caller will handle the success case
            // A PierceFirewall that arrived but was never consumed (direct
            // path won the race) is an orphaned live socket — close it.
            if let connection = state.receivedConnection {
                Task { await connection.disconnect() }
            }
        }
        peerConnectionPool.clearExpectedPierceFirewallUsername(token: token)
    }

    /// Called when PierceFirewall is received - check if it matches a pending browse request
    /// Returns true if it was handled as a browse request.
    ///
    /// Async because we await `setPeerUsername` before resuming the browse
    /// waiter — by the time the waiter gets the connection back, the
    /// username is already stamped (the pool also stamps it pre-yield, so
    /// in practice this is defense in depth: the local stamp guarantees
    /// it even if the pool's pre-registration map was cleared).
    public func handlePierceFirewallForBrowse(token: UInt32, connection: PeerConnection) async -> Bool {
        guard let initial = pendingBrowseStates[token] else { return false }

        // A browse that already failed (CantConnectToPeer) has no waiter
        // left; storing the connection would orphan a live socket.
        if initial.timedOut || initial.failureReason != nil {
            logger.debug("Browse: late PierceFirewall token=\(token) for dead browse; closing")
            pendingBrowseStates.removeValue(forKey: token)
            await connection.disconnect()
            return true
        }
        logger.debug("Browse: PierceFirewall token=\(token) matched pending browse for \(initial.username)")

        // Stamp username — must complete BEFORE we resume any waiter so
        // callers always see a connection whose `peerInfo.username` matches
        // the user they asked for.
        await connection.setPeerUsername(initial.username)

        // RE-FETCH after the await: that suspension lets the 30s timeout,
        // CantConnectToPeer, or a cancelled waiter run on the main actor and
        // consume the entry — resuming a stale copy's continuation here was
        // a CheckedContinuation double-resume (fatal trap; field crash on
        // build 15 whenever a PierceFirewall raced the timeout).
        guard var state = pendingBrowseStates[token] else {
            logger.debug("Browse: token=\(token) consumed while stamping username; closing connection")
            await connection.disconnect()
            return true
        }
        if state.timedOut || state.failureReason != nil {
            pendingBrowseStates.removeValue(forKey: token)
            await connection.disconnect()
            return true
        }

        // Store the connection
        state.receivedConnection = connection
        state.timeoutTask?.cancel()

        // If there's a continuation waiting, claim it and resume exactly once
        if let continuation = state.continuation {
            state.continuation = nil
            pendingBrowseStates.removeValue(forKey: token)
            continuation.resume(returning: connection)
        } else {
            // No one waiting yet - store for later
            pendingBrowseStates[token] = state
        }
        return true
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like
    public func addThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I like: \(item)")
    }

    /// Remove something I like
    public func removeThingILike(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I like: \(item)")
    }

    /// Add something I hate
    public func addThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.addThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I hate: \(item)")
    }

    /// Remove something I hate
    public func removeThingIHate(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.removeThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I hate: \(item)")
    }

    /// Get my recommendations
    public func getRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations")
    }

    /// Get global (network-wide) recommendations - popular interests across all users
    public func getGlobalRecommendations() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getGlobalRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested global recommendations")
    }

    /// Get a user's interests
    public func getUserInterests(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserInterests(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested interests for: \(username)")
    }

    /// Get similar users
    public func getSimilarUsers() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getSimilarUsers()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users")
    }

    /// Get recommendations for an item
    public func getItemRecommendations(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemRecommendations(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations for item: \(item)")
    }

    /// Get similar users for an item
    public func getItemSimilarUsers(_ item: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getItemSimilarUsers(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users for item: \(item)")
    }

    // MARK: - User Watching (Buddy List)

    /// Watch a user (receive status updates)
    public func watchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.watchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Watching user: \(username)")
    }

    /// Stop watching a user
    public func unwatchUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.unwatchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unwatched user: \(username)")
    }

    /// Ignore user (server code 11)
    public func ignoreUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.ignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Ignored user: \(username)")
    }

    /// Unignore user (server code 12)
    public func unignoreUser(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.unignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unignored user: \(username)")
    }

    /// Get a user's current status
    public func getUserStatus(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStatusMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested status for: \(username)")
    }

    /// Check if a user is online before attempting to connect
    /// Returns the user's status (offline, away, online) with a timeout.
    ///
    /// Concurrent callers for the same username are coalesced onto one
    /// server round-trip: the second/third caller attaches its continuation
    /// to the same pending entry and all receive the same reply. Previously
    /// a second caller overwrote the first caller's continuation, orphaning
    /// them until the 5s timeout (or forever on a `disconnect` without the
    /// teardown hook that now exists in `failAllPendingPeerOperations`).
    public func checkUserOnlineStatus(_ username: String, timeout: TimeInterval = 5.0) async throws -> (status: UserStatus, privileged: Bool) {
        guard isConnected else { throw NetworkError.notConnected }
        let connection = try requireConnectedServerConnection()

        let requestID = UUID()
        return await withCheckedContinuation { continuation in
            // Check-and-register in one synchronous block (no await in
            // between): computing the in-flight flag before an await let a
            // concurrent caller slip in and trigger a duplicate
            // GetUserStatus send.
            let alreadyInFlight = (pendingStatusRequests[username]?.isEmpty == false)
            pendingStatusRequests[username, default: []]
                .append((continuation: continuation, requestID: requestID))

            if alreadyInFlight {
                logger.debug("Coalescing status check for \(username) onto in-flight request")
            } else {
                logger.info("Checking online status for: \(username)")
                Task {
                    do {
                        let message = MessageBuilder.getUserStatusMessage(username: username)
                        try await connection.send(message)
                    } catch {
                        // The continuation is non-throwing; a failed send
                        // degrades to the per-caller timeout below, which
                        // resolves as .offline.
                        self.logger.warning("GetUserStatus send failed for \(username): \(error.localizedDescription)")
                    }
                }
            }

            // Per-caller timeout — removes exactly this waiter by requestID.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self else { return }
                guard var waiters = self.pendingStatusRequests[username] else { return }
                guard let idx = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
                let waiter = waiters.remove(at: idx)
                if waiters.isEmpty {
                    self.pendingStatusRequests.removeValue(forKey: username)
                } else {
                    self.pendingStatusRequests[username] = waiters
                }
                self.logger.warning("Status check timeout for \(username), assuming offline")
                waiter.continuation.resume(returning: (status: .offline, privileged: false))
            }
        }
    }

    /// Handle status response - resumes every pending status check for this user
    /// Last privileged flag the server actually reported per user. WatchUser
    /// replies don't carry privileged, so they pass nil and fall back to
    /// this instead of fabricating `false` (which could clobber a concurrent
    /// GetUserStatus waiter with wrong data).
    private var lastKnownPrivileged: [String: Bool] = [:]

    public func handleUserStatusResponse(username: String, status: UserStatus, privileged: Bool?) {
        let resolvedPrivileged: Bool
        if let privileged {
            lastKnownPrivileged[username] = privileged
            resolvedPrivileged = privileged
        } else {
            resolvedPrivileged = lastKnownPrivileged[username] ?? false
        }

        if let waiters = pendingStatusRequests.removeValue(forKey: username) {
            for waiter in waiters {
                waiter.continuation.resume(returning: (status: status, privileged: resolvedPrivileged))
            }
        }

        // Notify all registered status handlers
        for handler in userStatusHandlers {
            handler(username, status, resolvedPrivileged)
        }
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (speed, files, dirs)
    public func getUserStats(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserStats(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested stats for: \(username)")
    }

    /// Check our privilege time remaining
    public func checkPrivileges() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.checkPrivileges()
        try await requireConnectedServerConnection().send(message)
        logger.info("Checking privileges")
    }

    /// Get a user's privilege status
    public func getUserPrivileges(_ username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.getUserPrivileges(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested privileges for: \(username)")
    }

    // MARK: - Room Tickers

    /// Set a ticker message for a room
    public func setRoomTicker(room: String, ticker: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.setRoomTicker(room: room, ticker: ticker)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ticker in \(room): \(ticker)")
    }

    // MARK: - Room Search & Wishlist

    /// Search within a specific room
    public func searchRoom(_ room: String, query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.roomSearch(room: room, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Room search in \(room): \(query)")
    }

    /// Add a wishlist search (runs periodically)
    public func addWishlistSearch(query: String, token: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.wishlistSearch(token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added wishlist search: \(query)")
    }

    // MARK: - Private Rooms

    /// Add a member to a private room
    public func addPrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) to private room \(room)")
    }

    /// Remove a member from a private room
    public func removePrivateRoomMember(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) from private room \(room)")
    }

    /// Leave a private room
    public func leavePrivateRoom(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelMembership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Leaving private room \(room)")
    }

    /// Give up ownership of a private room
    public func giveUpPrivateRoomOwnership(_ room: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomCancelOwnership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Giving up ownership of \(room)")
    }

    /// Add an operator to a private room
    public func addPrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomAddOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) as operator in \(room)")
    }

    /// Remove an operator from a private room
    public func removePrivateRoomOperator(room: String, username: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.privateRoomRemoveOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) as operator from \(room)")
    }

    // MARK: - User Search

    /// Search a specific user's files
    public func userSearch(username: String, token: UInt32, query: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.userSearchMessage(username: username, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Upload Speed & Privileges

    /// Report upload speed to server
    public func reportUploadSpeed(_ speed: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.sendUploadSpeedMessage(speed: speed)
        try await requireConnectedServerConnection().send(message)
    }

    /// Give privileges to another user
    public func givePrivileges(to username: String, days: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.givePrivilegesMessage(username: username, days: days)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Room Invitations

    /// Enable or disable room invitations
    public func enableRoomInvitations(_ enable: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.enableRoomInvitationsMessage(enable: enable)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Bulk Messaging

    /// Send a message to multiple users at once
    public func messageUsers(_ usernames: [String], message: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let msg = MessageBuilder.messageUsersMessage(usernames: usernames, message: message)
        try await requireConnectedServerConnection().send(msg)
    }

    // MARK: - Global Room

    /// Join the global room
    public func joinGlobalRoom() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.joinGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    /// Leave the global room
    public func leaveGlobalRoom() async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.leaveGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Distributed Network

    /// Update whether we accept distributed children
    public func setAcceptDistributedChildren(_ accept: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        acceptDistributedChildren = accept
        let message = MessageBuilder.acceptChildren(accept)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set AcceptChildren(\(accept))")
    }

    /// Update our branch level
    /// Tell server whether we have a distributed parent
    public func sendHaveNoParent(_ haveNoParent: Bool) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.haveNoParent(haveNoParent)
        try await requireConnectedServerConnection().send(message)
        logger.info("Sent HaveNoParent(\(haveNoParent))")
    }

    public func setDistributedBranchLevel(_ level: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchLevel = level
        let message = MessageBuilder.branchLevel(level)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchLevel(\(level))")
    }

    /// Update our branch root
    public func setDistributedBranchRoot(_ root: String) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        distributedBranchRoot = root
        let message = MessageBuilder.branchRoot(root)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set BranchRoot(\(root))")
    }

    /// Update our child depth
    public func setDistributedChildDepth(_ depth: UInt32) async throws {
        guard isConnected else { throw NetworkError.notConnected }
        let message = MessageBuilder.childDepth(depth)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ChildDepth(\(depth))")
    }

    /// Reset distributed network state (called when server sends code 130)
    public func resetDistributedNetwork() async {
        guard isConnected else { return }

        logger.info("Resetting distributed network state")

        await clearDistributedState()

        // Tell server we have no parent and need one
        do {
            let haveNoParentMessage = MessageBuilder.haveNoParent(true)
            try await requireConnectedServerConnection().send(haveNoParentMessage)

            let branchLevelMessage = MessageBuilder.branchLevel(0)
            try await requireConnectedServerConnection().send(branchLevelMessage)

            // See the login sequence: child support is unimplemented, so
            // always advertise honestly regardless of the (kept-for-future)
            // `acceptDistributedChildren` flag.
            let acceptChildrenMessage = MessageBuilder.acceptChildren(false)
            try await requireConnectedServerConnection().send(acceptChildrenMessage)

            logger.info("Distributed network reset complete, awaiting new parent assignment")
        } catch {
            logger.error("Failed to send distributed reset messages: \(error.localizedDescription)")
        }
    }

    /// Drop every distributed child socket and reset branch state. Shared
    /// between `resetDistributedNetwork` (server code 130) and
    /// `performDisconnect` — a reconnect must not inherit live child
    /// sockets from the previous session. Does not touch the server
    /// connection, so it's safe to call during teardown.
    private func clearDistributedState() async {
        for child in distributedChildren {
            await child.disconnect()
        }
        distributedChildren.removeAll()
        distributedBranchLevel = 0
        distributedBranchRoot = ""
    }

    /// Add a distributed child connection
    public func addDistributedChild(_ connection: PeerConnection) {
        self.distributedChildren.append(connection)
        let count = self.distributedChildren.count
        self.logger.info("Added distributed child, total: \(count)")
    }

    /// Remove a distributed child connection
    public func removeDistributedChild(_ connection: PeerConnection) async {
        self.distributedChildren.removeAll { $0 === connection }
        let count = self.distributedChildren.count
        self.logger.info("Removed distributed child, total: \(count)")
    }

    /// Forward a distributed search to all children
    public func forwardDistributedSearch(unknown: UInt32, username: String, token: UInt32, query: String) async {
        guard !self.distributedChildren.isEmpty else { return }

        self.logger.info("Forwarding distributed search to \(self.distributedChildren.count) children")

        // Build the distributed search message once — identical for every child.
        var searchPayload = Data()
        searchPayload.appendUInt8(DistributedMessageCode.searchRequest.rawValue)
        searchPayload.appendUInt32(unknown)
        searchPayload.appendString(username)
        searchPayload.appendUInt32(token)
        searchPayload.appendString(query)

        var message = Data()
        message.appendUInt32(UInt32(searchPayload.count))
        message.append(searchPayload)

        for child in self.distributedChildren {
            do {
                try await child.send(message)
            } catch {
                logger.error("Failed to forward search to child: \(error.localizedDescription)")
            }
        }
    }

    /// Get number of distributed children
    public var distributedChildCount: Int { distributedChildren.count }

    // MARK: - Folder Browsing

    /// Handle incoming folder contents request - respond with our files in that folder
    private func handleFolderContentsRequest(username: String, token: UInt32, folder: String, connection: PeerConnection) async {
        let isBuddy = isBuddyChecker?(username) ?? false
        logger.info("Folder contents request from \(username) (buddy=\(isBuddy)) for: \(folder)")

        // Snapshot the index on the main actor, then run the O(N) filter +
        // mapping off-main — with large shares this walk hitched the UI on
        // every incoming peer request.
        let fileIndex = shareManager.fileIndex
        let files = await Task.detached(priority: .utility) {
            Self.buildFolderContents(fileIndex: fileIndex, folder: folder, isBuddy: isBuddy)
        }.value

        if files.isEmpty {
            logger.info("No files found in folder: \(folder)")
            // Still send empty response
        }

        do {
            try await connection.sendFolderContents(token: token, folder: folder, files: files)
            logger.info("Sent folder contents: \(folder) (\(files.count) files)")
        } catch {
            logger.error("Failed to send folder contents: \(error.localizedDescription)")
        }
    }

    /// Off-main-actor helper for `handleFolderContentsRequest`. Finds files
    /// in the requested folder, respecting per-folder visibility. Buddy-only
    /// files are dropped for non-buddies so they can't be enumerated via a
    /// folder-contents query that bypasses the shares-reply gate.
    private nonisolated static func buildFolderContents(
        fileIndex: [ShareManager.IndexedFile],
        folder: String,
        isBuddy: Bool
    ) -> [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] {
        fileIndex.compactMap { file -> (filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])? in
            guard file.sharedPath.hasPrefix(folder + "\\") || file.sharedPath == folder else { return nil }
            if file.visibility == .buddies && !isBuddy { return nil }
            var attributes: [(UInt32, UInt32)] = []
            if let bitrate = file.bitrate {
                attributes.append((0, bitrate))
            }
            if let duration = file.duration {
                attributes.append((1, duration))
            }
            return (
                filename: file.filename,
                size: file.size,
                extension_: file.fileExtension,
                attributes: attributes
            )
        }
    }

    // MARK: - Shares Request Handling

    /// Handle incoming shares request - respond with our shared file list.
    ///
    /// Folders marked `.buddies` are sent in the protocol's private
    /// directories section only when the requester is on our buddy
    /// list. Non-buddies get public folders only.
    private func handleSharesRequest(username: String, connection: PeerConnection) async {
        let isBuddy = isBuddyChecker?(username) ?? false
        logger.info("Shares request from \(username) (buddy=\(isBuddy))")

        // Snapshot the index on the main actor, then run the full-index
        // walk + per-file split + sorts off-main — with large shares this
        // hitched the UI on every incoming shares request.
        let fileIndex = shareManager.fileIndex
        let (publicDirs, privateDirs) = await Task.detached(priority: .utility) {
            Self.buildSharesDirectories(fileIndex: fileIndex, isBuddy: isBuddy)
        }.value

        logger.info("Sending \(publicDirs.count) public + \(privateDirs.count) private directories to \(username)")

        do {
            try await connection.sendShares(files: publicDirs, privateFiles: privateDirs)
            logger.info("Sent shares to \(username)")
        } catch {
            logger.error("Failed to send shares to \(username): \(error.localizedDescription)")
        }
    }

    private typealias DirBucket = (directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])

    /// Off-main-actor helper for `handleSharesRequest`: groups the index by
    /// directory and splits by visibility.
    private nonisolated static func buildSharesDirectories(
        fileIndex: [ShareManager.IndexedFile],
        isBuddy: Bool
    ) -> (publicDirs: [DirBucket], privateDirs: [DirBucket]) {
        var publicMap: [String: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)]] = [:]
        var privateMap: [String: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)]] = [:]

        for file in fileIndex {
            let components = file.sharedPath.split(separator: "\\")
            guard components.count > 1 else { continue }

            let directory = components.dropLast().joined(separator: "\\")
            let filename = String(components.last!)
            let entry = (filename: filename, size: file.size, bitrate: file.bitrate, duration: file.duration)

            switch file.visibility {
            case .public:
                publicMap[directory, default: []].append(entry)
            case .buddies:
                // Drop buddy-only files entirely for non-buddies; put
                // them in the private section for buddies so they show
                // up separately on the receiver.
                if isBuddy {
                    privateMap[directory, default: []].append(entry)
                }
            }
        }

        let publicDirs: [DirBucket] = publicMap.map { ($0.key, $0.value) }.sorted { $0.directory < $1.directory }
        let privateDirs: [DirBucket] = privateMap.map { ($0.key, $0.value) }.sorted { $0.directory < $1.directory }
        return (publicDirs, privateDirs)
    }

    // MARK: - User Info Request Handling

    /// Handle incoming user info request - respond with our profile info
    private func handleUserInfoRequest(username: String, connection: PeerConnection) async {
        logger.info("UserInfoRequest from \(username)")

        let totalUploads = UInt32(shareManager.totalFiles)
        let queueSize = UInt32(0)
        let hasFreeSlots = true

        // Get profile data from SocialState (or fall back to default)
        let profileData = profileDataProvider?() ?? (description: "SeeleSeek - Soulseek client for macOS", picture: nil)

        do {
            try await connection.sendUserInfo(
                description: profileData.description,
                picture: profileData.picture,
                totalUploads: totalUploads,
                queueSize: queueSize,
                hasFreeSlots: hasFreeSlots
            )
            logger.info("Sent user info to \(username)")
        } catch {
            logger.error("Failed to send user info to \(username): \(error.localizedDescription)")
        }
    }

    // MARK: - User Info Fetching (outbound)

    /// Session-long cache of parsed UserInfoReply data, keyed by username.
    /// Populated whenever a reply arrives (either solicited via fetchUserInfo
    /// or unsolicited from any peer connection).
    private var userInfoReplyCache: [String: MessageParser.UserInfoReplyInfo] = [:]

    /// In-flight fetch Tasks keyed by username, so concurrent callers for the
    /// same user share one network round-trip.
    private var userInfoInFlight: [String: Task<MessageParser.UserInfoReplyInfo, Error>] = [:]

    /// Continuations awaiting a UserInfoReply from a specific peer. Resumed
    /// when the pool event arrives or when the timeout task fires.
    private var userInfoReplyContinuations: [String: CheckedContinuation<MessageParser.UserInfoReplyInfo, Error>] = [:]

    /// Multi-listener handlers invoked for every incoming UserInfoReply
    /// (solicited or unsolicited). App code should subscribe once per state.
    private var userInfoReplyHandlers: [(String, MessageParser.UserInfoReplyInfo) -> Void] = []

    /// Register a handler for incoming UserInfoReply events. Multiple handlers supported.
    public func addUserInfoHandler(_ handler: @escaping (String, MessageParser.UserInfoReplyInfo) -> Void) {
        userInfoReplyHandlers.append(handler)
        logger.debug("NetworkClient: Added user info handler (total: \(self.userInfoReplyHandlers.count))")
    }

    /// Fetch user info (description, picture, upload stats) from a peer.
    /// Establishes a P connection if one isn't already open, sends UserInfoRequest,
    /// and awaits the reply. Results are cached for the session and concurrent
    /// callers for the same user are coalesced into one round-trip.
    @discardableResult
    public func fetchUserInfo(from username: String) async throws -> MessageParser.UserInfoReplyInfo {
        if let cached = userInfoReplyCache[username] {
            return cached
        }
        if let inFlight = userInfoInFlight[username] {
            return try await inFlight.value
        }
        let task = Task<MessageParser.UserInfoReplyInfo, Error> { [weak self] in
            guard let self else { throw NetworkError.notConnected }
            defer { self.userInfoInFlight[username] = nil }

            let connection = try await self.establishPeerConnection(for: username)
            try await connection.requestUserInfo()

            // Wait for the reply via a per-user continuation, with a hard timeout.
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MessageParser.UserInfoReplyInfo, Error>) in
                self.userInfoReplyContinuations[username] = cont
                // Fire-and-forget 15s timeout. Idempotent via `removeValue`:
                // if the reply arrives first the continuation is already
                // resumed and removed, so this wake is a no-op. Outer task
                // is owned by `userInfoInFlight`.
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    if let waiter = self?.userInfoReplyContinuations.removeValue(forKey: username) {
                        waiter.resume(throwing: NetworkError.timeout)
                    }
                }
            }
        }
        userInfoInFlight[username] = task
        let info = try await task.value
        cacheUserInfoReply(username: username, info)
        return info
    }

    /// Invalidate the cached user info for a user (next fetch will re-request).
    public func invalidateUserInfoCache(for username: String) {
        userInfoReplyCache.removeValue(forKey: username)
    }

    /// Entries can carry multi-MB profile pictures and survive disconnect,
    /// so the cache needs a hard cap — without one, any peer that connects
    /// can park megabytes here forever by pushing an unsolicited reply.
    private let maxUserInfoCacheEntries = 100

    private func cacheUserInfoReply(username: String, _ info: MessageParser.UserInfoReplyInfo) {
        if userInfoReplyCache.count >= maxUserInfoCacheEntries,
           userInfoReplyCache[username] == nil {
            // Simple pressure valve: drop half. LRU bookkeeping isn't worth
            // it for a cache whose hits are user-driven profile views.
            for key in userInfoReplyCache.keys.prefix(maxUserInfoCacheEntries / 2) {
                userInfoReplyCache.removeValue(forKey: key)
            }
        }
        userInfoReplyCache[username] = info
    }

    private func handleUserInfoReplyEvent(username: String, info: MessageParser.UserInfoReplyInfo) {
        // Unsolicited replies (no waiter) get cached without the picture —
        // hostile or chatty peers shouldn't be able to park image bytes.
        if userInfoReplyContinuations[username] == nil {
            var stripped = info
            stripped.pictureData = nil
            cacheUserInfoReply(username: username, stripped)
        } else {
            cacheUserInfoReply(username: username, info)
        }
        if let cont = userInfoReplyContinuations.removeValue(forKey: username) {
            cont.resume(returning: info)
        }
        for handler in userInfoReplyHandlers {
            handler(username, info)
        }
    }

    // MARK: - Peer Connection Establishment

    /// Opens (or reuses) a P-type peer connection, completing the handshake.
    /// The single home of the ConnectToPeer + direct/indirect-race dance —
    /// used by browse, folder-contents, user-info, and downloads. Anyone
    /// reaching out to a peer for the first time should go through here so
    /// the firewall-traversal logic isn't reinvented per consumer.
    ///
    /// Concurrent calls for the same `username` are coalesced via
    /// `pendingEstablishments`, so N parallel downloads to one peer share
    /// one connection establishment instead of racing each other.
    public func establishPeerConnection(for username: String) async throws -> PeerConnection {
        guard isConnected else {
            throw NetworkError.notConnected
        }

        if let existing = await peerConnectionPool.getConnectionForUser(username) {
            return existing
        }

        if let inFlight = pendingEstablishments[username] {
            return try await inFlight.value
        }

        let task = Task { [weak self] in
            // Task {} inherits MainActor isolation here, so the coalescing
            // map can be cleaned synchronously in the defer (same shape as
            // fetchUserInfo) — no re-hop Task needed.
            defer { self?.pendingEstablishments.removeValue(forKey: username) }
            guard let self else { throw NetworkError.notConnected }
            return try await self.performEstablishPeerConnection(for: username)
        }
        pendingEstablishments[username] = task
        return try await task.value
    }

    private func performEstablishPeerConnection(for username: String) async throws -> PeerConnection {
        // Resolve the address BEFORE registering the browse and sending
        // ConnectToPeer: the server answers GetPeerAddress for an offline/
        // unknown user with 0.0.0.0:0, and bailing here saves a wasted
        // ConnectToPeer + 30s browse window per attempt — at retry-storm
        // rates that was hundreds of pointless server messages per minute.
        // A PierceFirewall can't arrive before ConnectToPeer is sent, so
        // registering after the lookup loses nothing.
        let (ip, port, obfuscatedPort) = try await getPeerAddress(for: username)

        guard ip != "0.0.0.0", port > 0 || obfuscatedPort > 0 else {
            throw NetworkError.connectionFailed("\(username) is offline (no address)")
        }

        let token = UInt32.random(in: 0...UInt32.max)
        registerPendingBrowse(token: token, username: username, timeout: 30)
        await sendConnectToPeer(token: token, username: username, connectionType: "P")

        // Prefer the peer's obfuscated port whenever they advertise one.
        // Peers always advertise the plain port too, so falling back to plain
        // is safe when a peer doesn't advertise obfuscation.
        let useObfuscated = obfuscatedPort > 0
        let dialPort = useObfuscated ? obfuscatedPort : port

        var connection: PeerConnection
        var isIndirect = false
        do {
            connection = try await withThrowingTaskGroup(of: PeerConnection.self) { group in
                group.addTask {
                    let conn = try await self.peerConnectionPool.connect(
                        to: username, ip: ip, port: dialPort, token: token, obfuscated: useObfuscated
                    )
                    do {
                        // Handshake must also complete — the peer may not respond
                        // via PeerInit on the direct connection if they already
                        // connected back to us via PierceFirewall.
                        try await conn.waitForPeerHandshake(timeout: .seconds(8))
                    } catch {
                        // Tear down exactly the connection THIS dial created
                        // (covers handshake failure AND the 10s-timeout
                        // cancellation). Disconnecting whatever
                        // `getConnectionForUser` returned from the outer
                        // catch could kill an unrelated healthy inbound
                        // connection established during the race window.
                        await conn.disconnect()
                        throw error
                    }
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
            cancelPendingBrowse(token: token)
        } catch {
            // Direct timed out or handshake failed — the direct-dial child
            // already tore down its own connection; wait for the peer's
            // indirect PierceFirewall connection instead.
            connection = try await waitForPendingBrowse(token: token)
            isIndirect = true
        }

        if isIndirect {
            // PierceFirewall stops the receive loop assuming file-transfer
            // mode. P connections need it resumed for peer messages.
            await connection.resumeReceivingForPeerConnection()
        }

        // For indirect, PierceFirewall sets peerHandshakeReceived=true so
        // this returns immediately. For direct, the handshake was already
        // awaited inside the race.
        try await connection.waitForPeerHandshake(timeout: .seconds(5))
        return connection
    }

    // MARK: - SeeleSeek Artwork Request Handling

    /// Handle artwork request from a SeeleSeek peer — look up the file and send back embedded artwork.
    private func handleArtworkRequest(username: String, token: UInt32, filePath: String, connection: PeerConnection) async {
        // Find the file in our share index by SoulSeek path. Snapshot on
        // the main actor, scan off-main — O(N) over a large index per
        // incoming request otherwise hitches the UI.
        let fileIndex = shareManager.fileIndex
        let match = await Task.detached(priority: .utility) {
            fileIndex.first(where: { $0.sharedPath == filePath })
        }.value
        guard let indexedFile = match else {
            logger.warning("ArtworkRequest: file not found in shares: \(filePath)")
            // Send empty reply
            let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: Data())
            try? await connection.send(reply)
            return
        }

        // Deny artwork for buddy-only files when the requester is not a
        // buddy. Album art is embedded inside the file bytes, so leaking
        // it is a data leak even if we stop short of serving the full
        // upload. Matches the gate in handleSharesRequest / search.
        if indexedFile.visibility == .buddies {
            let isBuddy = isBuddyChecker?(username) ?? false
            if !isBuddy {
                logger.info("ArtworkRequest denied (buddy-only file, non-buddy requester): \(filePath)")
                let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: Data())
                try? await connection.send(reply)
                return
            }
        }

        let localURL = URL(fileURLWithPath: indexedFile.localPath)

        // Extract artwork off-main-thread via MetadataReader actor
        let imageData = await metadataReader?.extractArtwork(from: localURL) ?? Data()

        logger.info("ArtworkRequest: sending \(imageData.count) bytes for \(filePath)")
        let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: imageData)
        try? await connection.send(reply)
    }

    /// Pending artwork request callbacks keyed by token.
    private var artworkCallbacks: [UInt32: (Data?) -> Void] = [:]

    /// Coalesce concurrent `requestArtwork` calls for the same (peer, file).
    /// UI scenarios trigger multiple loaders for the same image (list cell +
    /// detail view + hover preview) at the same moment; without this, each
    /// loader opens its own token-based roundtrip and the peer is asked N
    /// times for the same artwork.
    private struct PendingArtworkRequest {
        var token: UInt32
        var waiters: [(Data?) -> Void]
    }
    private var pendingArtworkRequests: [String: PendingArtworkRequest] = [:]

    private static func artworkKey(username: String, filePath: String) -> String {
        "\(username)|\(filePath)"
    }

    /// Request artwork from a SeeleSeek peer.
    /// The completion handler is called with image data, or nil if the peer doesn't respond / isn't SeeleSeek.
    /// Only works if we already have a connection to the peer (e.g., from search results).
    public func requestArtwork(from username: String, filePath: String, completion: @escaping (Data?) -> Void) {
        guard isConnected else {
            completion(nil)
            return
        }

        let key = Self.artworkKey(username: username, filePath: filePath)

        // Coalesce: if a request for the same (peer, file) is in flight,
        // attach as an additional waiter and return — peer is asked once.
        if pendingArtworkRequests[key] != nil {
            pendingArtworkRequests[key]?.waiters.append(completion)
            return
        }

        let token = UInt32.random(in: 1..<0x8000_0000)
        pendingArtworkRequests[key] = PendingArtworkRequest(token: token, waiters: [completion])
        // Bridge token → key for the artworkReply event handler.
        artworkCallbacks[token] = { [weak self] data in
            self?.deliverArtwork(key: key, data: data)
        }

        Task {
            guard let connection = await peerConnectionPool.getConnectionForUser(username) else {
                logger.debug("No existing connection to \(username) for artwork request")
                deliverArtwork(key: key, data: nil)
                return
            }

            let request = MessageBuilder.artworkRequestMessage(token: token, filePath: filePath)
            do {
                try await connection.send(request)
            } catch {
                deliverArtwork(key: key, data: nil)
                return
            }

            // Fire-and-forget 10s timeout. `deliverArtwork` is idempotent —
            // if the real reply arrived first the entry is already gone, so
            // the nil-delivery no-ops. Not worth tracking per-call.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.deliverArtwork(key: key, data: nil)
            }
        }
    }

    /// Deliver an artwork result to every waiter for `(peer, file)` and
    /// clean up the coalesced entry. Idempotent — late timeout firing after
    /// the real reply already delivered finds no entry and no-ops.
    private func deliverArtwork(key: String, data: Data?) {
        guard let pending = pendingArtworkRequests.removeValue(forKey: key) else { return }
        artworkCallbacks.removeValue(forKey: pending.token)
        for waiter in pending.waiters {
            waiter(data)
        }
    }

    /// Test-only: register an artwork waiter directly without a peer
    /// connection. Returns the key used internally so tests can drive
    /// `_deliverArtworkForTest`.
    internal func _registerArtworkWaiterForTest(
        username: String,
        filePath: String,
        completion: @escaping (Data?) -> Void
    ) -> String {
        let key = Self.artworkKey(username: username, filePath: filePath)
        if pendingArtworkRequests[key] != nil {
            pendingArtworkRequests[key]?.waiters.append(completion)
        } else {
            pendingArtworkRequests[key] = PendingArtworkRequest(
                token: UInt32.random(in: 1..<0x8000_0000),
                waiters: [completion]
            )
        }
        return key
    }

    internal func _deliverArtworkForTest(key: String, data: Data?) {
        deliverArtwork(key: key, data: data)
    }

    internal func _pendingArtworkWaiterCount(key: String) -> Int {
        pendingArtworkRequests[key]?.waiters.count ?? 0
    }

    /// Request folder contents from a peer. Returns the token used so the
    /// caller can correlate the eventual `onFolderContentsResponse` event
    /// back to the originating request (multiple concurrent folder requests
    /// otherwise race on `(folder, peer)` alone).
    ///
    /// Routes through `establishPeerConnection`, which races a direct TCP
    /// connect against a server-mediated PierceFirewall indirect connection
    /// (10 s budget) — essential for firewalled peers whose listen port is
    /// unreachable. A bare `peerConnectionPool.connect(...)` here would hang
    /// on TCP SYN for ~75 s with no fallback, which is the entire failure
    /// mode this helper exists to solve. Do not bypass it.
    @discardableResult
    public func requestFolderContents(from username: String, folder: String) async throws -> UInt32 {
        guard isConnected else { throw NetworkError.notConnected }

        let token = UInt32.random(in: 0...UInt32.max)
        let connection = try await establishPeerConnection(for: username)
        try await connection.requestFolderContents(token: token, folder: folder)
        return token
    }

    // MARK: - Share Updates

    /// Re-broadcast `SharedFoldersFiles` using `ShareManager`'s current
    /// totals. Wired automatically via the `countsChangesStream`
    /// consumer in `init`. No-op while disconnected.
    public func updateShareCounts() async {
        guard isConnected, let connection = serverConnection else { return }

        let folders = UInt32(shareManager.totalFolders)
        let files = UInt32(shareManager.totalFiles)

        do {
            let message = MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files)
            try await connection.send(message)
            logger.info("Updated share counts: \(folders) folders, \(files) files")
        } catch {
            logger.error("Failed to update share counts: \(error.localizedDescription)")
        }
    }

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
            onConnectionStatusChanged?(.disconnected)
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
