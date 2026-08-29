import SwiftUI
import os
import SeeleseekCore

enum RoomListTab: String, CaseIterable {
    case all = "All"
    case `private` = "Private"
    case owned = "Owned"
}

@Observable
@MainActor
final class ChatState {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ChatState")
    // MARK: - Rooms
    var availableRooms: [ChatRoom] = []
    var joinedRooms: [ChatRoom] = []
    var selectedRoom: String?

    // MARK: - Private Room Categories
    var ownedPrivateRooms: [ChatRoom] = []
    var memberPrivateRooms: [ChatRoom] = []
    var operatedRoomNames: Set<String> = []

    // MARK: - Private Chats
    var privateChats: [PrivateChat] = []
    var selectedPrivateChat: String?

    // MARK: - Input
    /// Per-conversation drafts keyed by conversation (room name or DM
    /// username, prefixed to avoid collisions). A single shared draft
    /// meant typing in room A then pressing Return in a DM sent the
    /// draft there, and switching conversations lost the text.
    private var drafts: [String: String] = [:]

    /// Draft for the currently-selected conversation. Computed so the
    /// existing `$chatState.messageInput` bindings keep working while
    /// the storage is per-conversation.
    var messageInput: String {
        get { currentDraftKey.map { drafts[$0] ?? "" } ?? "" }
        set {
            guard let key = currentDraftKey else { return }
            if newValue.isEmpty {
                drafts.removeValue(forKey: key)
            } else {
                drafts[key] = newValue
            }
        }
    }

    private var currentDraftKey: String? {
        if let room = selectedRoom { return "room:\(room)" }
        if let user = selectedPrivateChat { return "dm:\(user)" }
        return nil
    }

    var roomSearchQuery: String = ""

    // MARK: - Room Browser State
    var roomListTab: RoomListTab = .all {
        didSet { if roomListTab != oldValue { recomputeSortedRooms() } }
    }
    var showCreateRoom: Bool = false
    var createRoomName: String = ""
    var createRoomIsPrivate: Bool = false
    var createRoomError: String? = nil

    // MARK: - Room User List Panel
    var showUserListPanel: Bool = false
    var userListSearchQuery: String = ""

    // MARK: - User Stats Cache
    var userStatsCache: [String: (speed: UInt32, files: UInt32)] = [:]
    private var pendingStatsRequests: Set<String> = []

    // MARK: - Room Management
    var showRoomManagement: Bool = false
    var tickersCollapsed: Bool = false

    // MARK: - Loading State
    var isLoadingRooms: Bool = false
    /// Set when the room-list request fails or times out; surfaced in
    /// `RoomBrowserSheet` with a Retry button.
    var roomListError: String? = nil
    @ObservationIgnored private var roomListTimeoutTask: Task<Void, Never>?

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Setup

    @ObservationIgnored private var chatEventsTask: Task<Void, Never>?
    @ObservationIgnored private var socialEventsTask: Task<Void, Never>?

    func wireNetworkEvents(client: NetworkClient) {
        self.networkClient = client

        // Load persisted DMs
        Task {
            await loadPersistedDMs()
        }

        // One serial consumer per domain — in-domain delivery order is
        // emission order, which chat depends on (roomJoined must land
        // before that room's messages). Never spawn per-event Tasks here.
        chatEventsTask?.cancel()
        let chatEvents = client.events.chat.subscribe()
        chatEventsTask = Task { [weak self] in
            for await event in chatEvents {
                guard let self else { return }
                self.handle(event)
            }
        }

        // Bounded: only status colors ride this; tail-drop under a storm.
        socialEventsTask?.cancel()
        let socialEvents = client.events.social.subscribe(bufferingPolicy: .bufferingOldest(1024))
        socialEventsTask = Task { [weak self] in
            for await event in socialEvents {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: ChatEvent) {
        switch event {
        case .roomList(let publicRooms, let ownedPrivate, let memberPrivate, let operated):
            handleRoomListFull(
                publicRooms: publicRooms,
                ownedPrivate: ownedPrivate,
                memberPrivate: memberPrivate,
                operated: operated
            )
        case .roomJoined(let room, let users, let owner, let operators):
            handleRoomJoined(room, users: users, owner: owner, operators: operators)
        case .roomLeft(let room):
            handleRoomLeft(room)
        case .roomMessage(let room, let message):
            // Skip server echo of our own messages (already added optimistically in sendMessage)
            guard !message.isOwn else { return }
            addRoomMessage(room, message: message)
        case .privateMessage(let username, let message):
            addPrivateMessage(username, message: message)
        case .userJoinedRoom(let room, let username):
            handleUserJoinedRoom(room, username: username)
        case .userLeftRoom(let room, let username):
            handleUserLeftRoom(room, username: username)
        case .cantCreateRoom(let room):
            setCreateRoomError("Cannot create room '\(room)'")
        case .privateRoomMembers(let room, let members):
            updateRoomMembers(room, members: members)
        case .privateRoomMemberAdded(let room, let username):
            addRoomMember(room, username: username)
        case .privateRoomMemberRemoved(let room, let username):
            removeRoomMember(room, username: username)
        case .privateRoomOperators(let room, let operators):
            updateRoomOperators(room, operators: operators)
        case .privateRoomOperatorGranted(let room):
            operatedRoomNames.insert(room)
        case .privateRoomOperatorRevoked(let room):
            operatedRoomNames.remove(room)
        case .roomMembershipGranted(let room):
            let msg = ChatMessage(username: "", content: "You were invited to private room '\(room)'", isSystem: true)
            // Add as a system notification to current room if any
            if let current = selectedRoom, let idx = joinedRooms.firstIndex(where: { $0.name == current }) {
                Self.appendCapped(msg, to: &joinedRooms[idx].messages)
            }
        case .roomMembershipRevoked(let room):
            // Remove from joined if present
            joinedRooms.removeAll { $0.name == room }
            memberPrivateRooms.removeAll { $0.name == room }
            if selectedRoom == room {
                selectedRoom = joinedRooms.first?.name
            }
        case .roomTickerState(let room, let tickers):
            if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
                var dict: [String: String] = [:]
                for t in tickers { dict[t.username] = t.ticker }
                joinedRooms[idx].tickers = dict
            }
        case .roomTickerAdd(let room, let username, let ticker):
            if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
                joinedRooms[idx].tickers[username] = ticker
            }
        case .roomTickerRemove(let room, let username):
            if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
                joinedRooms[idx].tickers.removeValue(forKey: username)
            }
        case .roomInvitationsEnabled, .passwordChanged, .roomAdded, .roomRemoved,
             .globalRoomMessage:
            break
        }
    }

    private func handle(_ event: SocialEvent) {
        switch event {
        case .userStatus(let username, let status, _):
            // Update private chat online status
            updateUserOnlineStatus(username: username, status: status)
        case .userStats(let username, let avgSpeed, _, let files, _):
            // Room user list display
            userStatsCache[username] = (speed: avgSpeed, files: files)
            pendingStatsRequests.remove(username)
        default:
            break
        }
    }

    // MARK: - User Stats Requests

    /// Request user stats for a list of usernames (throttled, skips cached)
    func requestUserStats(for usernames: [String]) {
        let uncached = usernames.filter { userStatsCache[$0] == nil && !pendingStatsRequests.contains($0) }
        guard !uncached.isEmpty else { return }

        // Batch in groups of 5 to avoid flooding the server
        let batches = stride(from: 0, to: uncached.count, by: 5).map {
            Array(uncached[$0..<min($0 + 5, uncached.count)])
        }

        Task {
            for batch in batches {
                for username in batch {
                    pendingStatsRequests.insert(username)
                    try? await networkClient?.getUserStats(username)
                }
                // Small delay between batches
                if batches.count > 1 {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    // MARK: - Room List Handling

    private func handleRoomListFull(
        publicRooms: [ChatRoom],
        ownedPrivate: [ChatRoom],
        memberPrivate: [ChatRoom],
        operated: [String]
    ) {
        availableRooms = publicRooms
        ownedPrivateRooms = ownedPrivate
        memberPrivateRooms = memberPrivate
        operatedRoomNames = Set(operated)
        recomputeSortedRooms()
        roomListResponseArrived()
    }

    // MARK: - User Status Updates

    func updateUserOnlineStatus(username: String, status: UserStatus) {
        if let index = privateChats.firstIndex(where: { $0.username == username }) {
            privateChats[index].isOnline = status != .offline
        }
    }

    private func handleRoomJoined(_ roomName: String, users: [String], owner: String?, operators: [String]) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            // Update existing room
            joinedRooms[index].users = users
            if let owner { joinedRooms[index].owner = owner }
            if !operators.isEmpty { joinedRooms[index].operators = Set(operators) }
            if owner != nil { joinedRooms[index].isPrivate = true }
        } else {
            let isPrivate = owner != nil
            let room = ChatRoom(
                name: roomName,
                users: users,
                isJoined: true,
                isPrivate: isPrivate,
                owner: owner,
                operators: Set(operators)
            )
            joinedRooms.append(room)
        }
        selectedRoom = roomName
    }

    private func handleRoomLeft(_ roomName: String) {
        joinedRooms.removeAll { $0.name == roomName }
        drafts.removeValue(forKey: "room:\(roomName)")
        if selectedRoom == roomName {
            selectedRoom = joinedRooms.first?.name
        }
    }

    private func handleUserJoinedRoom(_ roomName: String, username: String) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            if !joinedRooms[index].users.contains(username) {
                joinedRooms[index].users.append(username)
            }
            appendEvent(RoomEvent(kind: .joined, username: username), toRoomAt: index)
        }
    }

    private func handleUserLeftRoom(_ roomName: String, username: String) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            joinedRooms[index].users.removeAll { $0 == username }
            appendEvent(RoomEvent(kind: .left, username: username), toRoomAt: index)
        }
    }

    /// Maximum events kept per room.
    private static let maxRoomEvents = 200

    private func appendEvent(_ event: RoomEvent, toRoomAt index: Int) {
        joinedRooms[index].events.append(event)
        let overflow = joinedRooms[index].events.count - Self.maxRoomEvents
        if overflow > 0 {
            joinedRooms[index].events.removeFirst(overflow)
        }
    }

    // MARK: - Private Room Member/Operator Updates

    private func updateRoomMembers(_ room: String, members: [String]) {
        if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            joinedRooms[idx].members = members
        }
    }

    private func addRoomMember(_ room: String, username: String) {
        if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            if !joinedRooms[idx].members.contains(username) {
                joinedRooms[idx].members.append(username)
            }
        }
    }

    private func removeRoomMember(_ room: String, username: String) {
        if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            joinedRooms[idx].members.removeAll { $0 == username }
        }
    }

    private func updateRoomOperators(_ room: String, operators: [String]) {
        if let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            joinedRooms[idx].operators = Set(operators)
        }
    }

    // MARK: - Computed Properties
    var currentRoom: ChatRoom? {
        guard let name = selectedRoom else { return nil }
        return joinedRooms.first { $0.name == name }
    }

    var currentPrivateChat: PrivateChat? {
        guard let username = selectedPrivateChat else { return nil }
        return privateChats.first { $0.username == username }
    }

    /// Sorted room list for the current tab. Cached — sorting thousands
    /// of rooms on every body eval (twice: isEmpty check + ForEach) made
    /// the browser sheet sluggish. Recomputed only when the source lists
    /// or the tab change.
    private(set) var sortedRooms: [ChatRoom] = []

    private func recomputeSortedRooms() {
        let source: [ChatRoom]
        switch roomListTab {
        case .all:
            source = availableRooms
        case .private:
            source = memberPrivateRooms
        case .owned:
            source = ownedPrivateRooms
        }
        sortedRooms = source.sorted { $0.userCount > $1.userCount }
    }

    var filteredRooms: [ChatRoom] {
        if roomSearchQuery.isEmpty {
            return sortedRooms
        }
        return sortedRooms.filter {
            $0.name.localizedCaseInsensitiveContains(roomSearchQuery)
        }
    }

    var totalUnreadCount: Int {
        joinedRooms.reduce(0) { $0 + $1.unreadCount } +
        privateChats.reduce(0) { $0 + $1.unreadCount }
    }

    // SECURITY: Maximum message length to prevent abuse
    private static let maxMessageLength = 2000

    /// Cap per room/chat so long-lived sessions don't grow unboundedly.
    private static let maxMessages = 1000

    /// Append with cap: keeps the most recent `maxMessages`, dropping
    /// from the head.
    private static func appendCapped(_ message: ChatMessage, to messages: inout [ChatMessage]) {
        messages.append(message)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    var canSendMessage: Bool {
        let trimmed = messageInput.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= Self.maxMessageLength
    }

    // MARK: - Room Role Queries

    func isOwner(of roomName: String) -> Bool {
        guard let room = joinedRooms.first(where: { $0.name == roomName }) else { return false }
        return room.owner == networkClient?.status.username
    }

    func isOperator(of roomName: String) -> Bool {
        guard let room = joinedRooms.first(where: { $0.name == roomName }) else { return false }
        return room.operators.contains(networkClient?.status.username ?? "")
    }

    // MARK: - Room Actions
    func joinRoom(_ name: String, isPrivate: Bool = false) {
        Task {
            try? await networkClient?.joinRoom(name, isPrivate: isPrivate)
        }
    }

    func leaveRoom(_ name: String) {
        Task {
            try? await networkClient?.leaveRoom(name)
        }
    }

    func requestRoomList() {
        isLoadingRooms = true
        roomListError = nil
        Task {
            do {
                try await networkClient?.getRoomList()
            } catch {
                roomListRequestFailed("Couldn't request room list: \(error.localizedDescription)")
            }
        }
        // The server can silently never reply — without a timeout the
        // spinner spins forever. Cleared by roomListResponseArrived().
        roomListTimeoutTask?.cancel()
        roomListTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.isLoadingRooms else { return }
            self.roomListRequestFailed("The server didn't respond.")
        }
    }

    private func roomListRequestFailed(_ message: String) {
        isLoadingRooms = false
        roomListError = message
        roomListTimeoutTask?.cancel()
        roomListTimeoutTask = nil
    }

    private func roomListResponseArrived() {
        isLoadingRooms = false
        roomListError = nil
        roomListTimeoutTask?.cancel()
        roomListTimeoutTask = nil
    }

    func selectRoom(_ name: String) {
        selectedRoom = name
        selectedPrivateChat = nil

        // Clear unread
        if let index = joinedRooms.firstIndex(where: { $0.name == name }) {
            joinedRooms[index].unreadCount = 0
        }
    }

    func addRoomMessage(_ roomName: String, message: ChatMessage) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            Self.appendCapped(message, to: &joinedRooms[index].messages)
            if selectedRoom != roomName {
                joinedRooms[index].unreadCount += 1
            }
            announceMentionIfNeeded(message, in: roomName)
        }
    }

    /// A VoiceOver user cannot scan the transcript for a highlight.
    /// Speak a short notice when another user writes the local
    /// username in a room message.
    private func announceMentionIfNeeded(_ message: ChatMessage, in roomName: String) {
        guard !message.isOwn, !message.isSystem else { return }
        guard let localUsername = networkClient?.status.username, !localUsername.isEmpty else { return }
        guard message.username.caseInsensitiveCompare(localUsername) != .orderedSame else { return }
        guard Self.containsWholeWord(localUsername, in: message.content) else { return }
        VoiceOverAnnouncer.shared.announce("Mentioned by \(message.username) in \(roomName)")
    }

    /// True when `word` occurs with non-alphanumeric characters on
    /// both sides.
    private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z0-9_])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func updateRoomUsers(_ roomName: String, users: [String]) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            joinedRooms[index].users = users
        }
    }

    // MARK: - Room Creation & Management

    func createRoom() {
        let name = createRoomName.trimmingCharacters(in: .whitespaces)
        createRoomError = nil

        guard !name.isEmpty else {
            setCreateRoomError("Room name cannot be empty")
            return
        }
        guard name.count <= 24 else {
            setCreateRoomError("Room name must be 24 characters or less")
            return
        }
        guard name.allSatisfy({ $0.isASCII && $0 != " " }) else {
            setCreateRoomError("Room name must be ASCII with no spaces")
            return
        }

        joinRoom(name, isPrivate: createRoomIsPrivate)
        createRoomName = ""
        createRoomIsPrivate = false
        showCreateRoom = false
    }

    /// Announce here, not in a view `onChange`. The sheet can close
    /// before the server error arrives.
    private func setCreateRoomError(_ message: String) {
        createRoomError = message
        VoiceOverAnnouncer.shared.announce(message)
    }

    func addMember(room: String, username: String) {
        Task { try? await networkClient?.addPrivateRoomMember(room: room, username: username) }
    }

    func removeMember(room: String, username: String) {
        Task { try? await networkClient?.removePrivateRoomMember(room: room, username: username) }
    }

    func addOperator(room: String, username: String) {
        Task { try? await networkClient?.addPrivateRoomOperator(room: room, username: username) }
    }

    func removeOperator(room: String, username: String) {
        Task { try? await networkClient?.removePrivateRoomOperator(room: room, username: username) }
    }

    func setTicker(room: String, text: String) {
        Task { try? await networkClient?.setRoomTicker(room: room, ticker: text) }
    }

    func clearTicker(room: String) {
        Task { try? await networkClient?.setRoomTicker(room: room, ticker: "") }
    }

    /// This user's Soulseek username, or "" when not connected. Views that
    /// already hold a `ChatRoom` use this to index into it rather than
    /// re-scanning `joinedRooms` for a room they were handed.
    var myUsername: String {
        networkClient?.status.username ?? ""
    }

    func giveUpOwnership(room: String) {
        Task { try? await networkClient?.giveUpPrivateRoomOwnership(room) }
    }

    // MARK: - Private Chat Actions
    func selectPrivateChat(_ username: String) {
        selectedPrivateChat = username
        selectedRoom = nil

        // Create chat if doesn't exist
        let isNew = !privateChats.contains(where: { $0.username == username })
        if isNew {
            privateChats.append(PrivateChat(username: username))

            // Request user status for new chat
            Task {
                try? await networkClient?.watchUser(username)
                try? await networkClient?.getUserStatus(username)
            }
        }

        // Clear unread
        if let index = privateChats.firstIndex(where: { $0.username == username }) {
            privateChats[index].unreadCount = 0
        }
    }

    func addPrivateMessage(_ username: String, message: ChatMessage) {
        if let index = privateChats.firstIndex(where: { $0.username == username }) {
            Self.appendCapped(message, to: &privateChats[index].messages)
            // If receiving a message from them, they're online
            if !message.isOwn {
                privateChats[index].isOnline = true
            }
            if selectedPrivateChat != username {
                privateChats[index].unreadCount += 1
            }
        } else {
            // Create new chat - user is online since they sent us a message
            var chat = PrivateChat(username: username, isOnline: !message.isOwn)
            Self.appendCapped(message, to: &chat.messages)
            chat.unreadCount = selectedPrivateChat != username ? 1 : 0
            privateChats.append(chat)

            // Request user status
            Task {
                try? await networkClient?.watchUser(username)
                try? await networkClient?.getUserStatus(username)
            }
        }

        // Log incoming private messages for notifications
        if !message.isOwn && !message.isSystem {
            ActivityLog.shared.logChatMessage(from: username, room: nil)
        }

        // Persist to database (skip system messages like join/leave)
        if !message.isSystem {
            Task {
                do {
                    try await ChatRepository.saveMessage(message, peerUsername: username)
                } catch {
                    logger.error("Failed to persist DM: \(error.localizedDescription)")
                }
            }
        }
    }

    func closePrivateChat(_ username: String) {
        privateChats.removeAll { $0.username == username }
        drafts.removeValue(forKey: "dm:\(username)")
        if selectedPrivateChat == username {
            selectedPrivateChat = nil
        }
    }

    // MARK: - Message Actions
    func sendMessage() {
        guard canSendMessage else { return }

        var content = messageInput.trimmingCharacters(in: .whitespaces)
        // SECURITY: Truncate message if it exceeds max length
        if content.count > Self.maxMessageLength {
            content = String(content.prefix(Self.maxMessageLength))
        }
        messageInput = ""

        if let command = SlashCommand.parse(content) {
            switch command {
            case .me:
                break  // Send unchanged. The UI shows it as an action line.
            case .join(let room):
                joinRoom(room)
                return
            case .leave:
                if let room = selectedRoom {
                    leaveRoom(room)
                } else {
                    appendLocalSystemMessage("Not in a room")
                }
                return
            case .clear:
                clearTranscript()
                return
            case .ticker(let text):
                // Tickers are per-room; there is nowhere to put one in a
                // private chat.
                guard let room = selectedRoom else {
                    appendLocalSystemMessage("Tickers only work in a room")
                    return
                }
                // Empty text is the protocol's removal signal, so one call
                // covers both set and clear.
                setTicker(room: room, text: text)
                appendLocalSystemMessage(text.isEmpty ? "Ticker cleared" : "Ticker set")
                return
            case .unknown(let name):
                appendLocalSystemMessage("Unknown command: \(name)")
                return
            }
        }

        if let roomName = selectedRoom {
            // Send to room via network
            let message = ChatMessage(
                username: networkClient?.status.username ?? "You",
                content: content,
                isOwn: true
            )
            addRoomMessage(roomName, message: message)

            Task {
                try? await networkClient?.sendRoomMessage(roomName, message: content)
            }
        } else if let username = selectedPrivateChat {
            // Send private message
            let message = ChatMessage(
                username: networkClient?.status.username ?? "You",
                content: content,
                isOwn: true
            )
            addPrivateMessage(username, message: message)

            Task {
                try? await networkClient?.sendPrivateMessage(to: username, message: content)
            }
        }
    }

    /// Empties the visible transcript of the current conversation.
    /// Does not change DM history in the database.
    func clearTranscript() {
        if let room = selectedRoom, let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            joinedRooms[idx].messages.removeAll()
        } else if let user = selectedPrivateChat, let idx = privateChats.firstIndex(where: { $0.username == user }) {
            privateChats[idx].messages.removeAll()
        }
    }

    /// Adds a local system line to the current conversation. The line is
    /// not sent and not persisted.
    private func appendLocalSystemMessage(_ text: String) {
        let message = ChatMessage(username: "", content: text, isSystem: true)
        if let room = selectedRoom, let idx = joinedRooms.firstIndex(where: { $0.name == room }) {
            Self.appendCapped(message, to: &joinedRooms[idx].messages)
        } else if let user = selectedPrivateChat, let idx = privateChats.firstIndex(where: { $0.username == user }) {
            Self.appendCapped(message, to: &privateChats[idx].messages)
        }
    }

    // MARK: - Room List
    func setAvailableRooms(_ rooms: [ChatRoom]) {
        availableRooms = rooms
        recomputeSortedRooms()
        roomListResponseArrived()
    }

    // MARK: - DM Persistence

    /// Load persisted DM conversations from database
    private func loadPersistedDMs() async {
        do {
            let peerUsernames = try await ChatRepository.fetchConversations()
            for peer in peerUsernames {
                let messages = try await ChatRepository.fetchMessages(for: peer)
                guard !messages.isEmpty else { continue }

                if let index = privateChats.firstIndex(where: { $0.username == peer }) {
                    // Merge: only add messages not already present
                    let existingIds = Set(privateChats[index].messages.map(\.id))
                    let newMessages = messages.filter { !existingIds.contains($0.id) }
                    privateChats[index].messages.insert(contentsOf: newMessages, at: 0)
                    let overflow = privateChats[index].messages.count - Self.maxMessages
                    if overflow > 0 {
                        privateChats[index].messages.removeFirst(overflow)
                    }
                } else {
                    let chat = PrivateChat(username: peer, messages: messages)
                    privateChats.append(chat)
                }
            }
            if !peerUsernames.isEmpty {
                logger.info("Loaded DM history for \(peerUsernames.count) conversations")
            }

            // Prune old messages
            try await ChatRepository.pruneOldMessages()
        } catch {
            logger.error("Failed to load DM history: \(error.localizedDescription)")
        }
    }

    /// Delete conversation history from database
    func deleteConversationHistory(_ username: String) {
        Task {
            do {
                try await ChatRepository.deleteConversation(username)
                logger.info("Deleted DM history for \(username)")
            } catch {
                logger.error("Failed to delete DM history: \(error.localizedDescription)")
            }
        }
    }
}
