import SwiftUI
import os

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
    var messageInput: String = ""
    var roomSearchQuery: String = ""

    // MARK: - Room Browser State
    var roomListTab: RoomListTab = .all
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

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Setup
    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        // Load persisted DMs
        Task {
            await loadPersistedDMs()
        }

        client.onRoomList = { [weak self] rooms in
            self?.setAvailableRooms(rooms)
        }

        client.onRoomListFull = { [weak self] publicRooms, ownedPrivate, memberPrivate, operated in
            self?.handleRoomListFull(
                publicRooms: publicRooms,
                ownedPrivate: ownedPrivate,
                memberPrivate: memberPrivate,
                operated: operated
            )
        }

        client.onRoomJoined = { [weak self] roomName, users, owner, operators in
            self?.handleRoomJoined(roomName, users: users, owner: owner, operators: operators)
        }

        client.onRoomLeft = { [weak self] roomName in
            self?.handleRoomLeft(roomName)
        }

        client.onRoomMessage = { [weak self] roomName, message in
            // Skip server echo of our own messages (already added optimistically in sendMessage)
            guard !message.isOwn else { return }
            self?.addRoomMessage(roomName, message: message)
        }

        client.onPrivateMessage = { [weak self] username, message in
            self?.addPrivateMessage(username, message: message)
        }

        client.onUserJoinedRoom = { [weak self] roomName, username in
            self?.handleUserJoinedRoom(roomName, username: username)
        }

        client.onUserLeftRoom = { [weak self] roomName, username in
            self?.handleUserLeftRoom(roomName, username: username)
        }

        client.onCantCreateRoom = { [weak self] roomName in
            self?.createRoomError = "Cannot create room '\(roomName)'"
        }

        // Private room callbacks
        client.onPrivateRoomMembers = { [weak self] room, members in
            self?.updateRoomMembers(room, members: members)
        }

        client.onPrivateRoomMemberAdded = { [weak self] room, username in
            self?.addRoomMember(room, username: username)
        }

        client.onPrivateRoomMemberRemoved = { [weak self] room, username in
            self?.removeRoomMember(room, username: username)
        }

        client.onPrivateRoomOperators = { [weak self] room, operators in
            self?.updateRoomOperators(room, operators: operators)
        }

        client.onPrivateRoomOperatorGranted = { [weak self] room in
            self?.operatedRoomNames.insert(room)
        }

        client.onPrivateRoomOperatorRevoked = { [weak self] room in
            self?.operatedRoomNames.remove(room)
        }

        client.onRoomMembershipGranted = { [weak self] room in
            guard let self else { return }
            let msg = ChatMessage(username: "", content: "You were invited to private room '\(room)'", isSystem: true)
            // Add as a system notification to current room if any
            if let current = self.selectedRoom, let idx = self.joinedRooms.firstIndex(where: { $0.name == current }) {
                self.joinedRooms[idx].messages.append(msg)
            }
        }

        client.onRoomMembershipRevoked = { [weak self] room in
            guard let self else { return }
            // Remove from joined if present
            self.joinedRooms.removeAll { $0.name == room }
            self.memberPrivateRooms.removeAll { $0.name == room }
            if self.selectedRoom == room {
                self.selectedRoom = self.joinedRooms.first?.name
            }
        }

        // Ticker callbacks
        client.onRoomTickerState = { [weak self] room, tickers in
            guard let self else { return }
            if let idx = self.joinedRooms.firstIndex(where: { $0.name == room }) {
                var dict: [String: String] = [:]
                for t in tickers { dict[t.username] = t.ticker }
                self.joinedRooms[idx].tickers = dict
            }
        }

        client.onRoomTickerAdd = { [weak self] room, username, ticker in
            guard let self else { return }
            if let idx = self.joinedRooms.firstIndex(where: { $0.name == room }) {
                self.joinedRooms[idx].tickers[username] = ticker
            }
        }

        client.onRoomTickerRemove = { [weak self] room, username in
            guard let self else { return }
            if let idx = self.joinedRooms.firstIndex(where: { $0.name == room }) {
                self.joinedRooms[idx].tickers.removeValue(forKey: username)
            }
        }

        // Listen for user status updates to update private chat online status
        client.addUserStatusHandler { [weak self] username, status, _ in
            self?.updateUserOnlineStatus(username: username, status: status)
        }

        // User stats updates (for room user list display)
        client.addUserStatsHandler { [weak self] username, avgSpeed, _, files, _ in
            guard let self else { return }
            self.userStatsCache[username] = (speed: avgSpeed, files: files)
            self.pendingStatsRequests.remove(username)
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
        isLoadingRooms = false
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
        if selectedRoom == roomName {
            selectedRoom = joinedRooms.first?.name
        }
    }

    private func handleUserJoinedRoom(_ roomName: String, username: String) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            if !joinedRooms[index].users.contains(username) {
                joinedRooms[index].users.append(username)
            }
            let message = ChatMessage(username: "", content: "\(username) joined the room", isSystem: true)
            joinedRooms[index].messages.append(message)
        }
    }

    private func handleUserLeftRoom(_ roomName: String, username: String) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            joinedRooms[index].users.removeAll { $0 == username }
            let message = ChatMessage(username: "", content: "\(username) left the room", isSystem: true)
            joinedRooms[index].messages.append(message)
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

    var filteredRooms: [ChatRoom] {
        let source: [ChatRoom]
        switch roomListTab {
        case .all:
            source = availableRooms
        case .private:
            source = memberPrivateRooms
        case .owned:
            source = ownedPrivateRooms
        }

        let sorted = source.sorted { $0.userCount > $1.userCount }
        if roomSearchQuery.isEmpty {
            return sorted
        }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(roomSearchQuery)
        }
    }

    var totalUnreadCount: Int {
        joinedRooms.reduce(0) { $0 + $1.unreadCount } +
        privateChats.reduce(0) { $0 + $1.unreadCount }
    }

    // SECURITY: Maximum message length to prevent abuse
    private static let maxMessageLength = 2000

    var canSendMessage: Bool {
        let trimmed = messageInput.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= Self.maxMessageLength
    }

    // MARK: - Room Role Queries

    func isOwner(of roomName: String) -> Bool {
        guard let room = joinedRooms.first(where: { $0.name == roomName }) else { return false }
        return room.owner == networkClient?.username
    }

    func isOperator(of roomName: String) -> Bool {
        guard let room = joinedRooms.first(where: { $0.name == roomName }) else { return false }
        return room.operators.contains(networkClient?.username ?? "")
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
        Task {
            try? await networkClient?.getRoomList()
        }
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
            joinedRooms[index].messages.append(message)
            if selectedRoom != roomName {
                joinedRooms[index].unreadCount += 1
            }
        }
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
            createRoomError = "Room name cannot be empty"
            return
        }
        guard name.count <= 24 else {
            createRoomError = "Room name must be 24 characters or less"
            return
        }
        guard name.allSatisfy({ $0.isASCII && $0 != " " }) else {
            createRoomError = "Room name must be ASCII with no spaces"
            return
        }

        joinRoom(name, isPrivate: createRoomIsPrivate)
        createRoomName = ""
        createRoomIsPrivate = false
        showCreateRoom = false
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
            privateChats[index].messages.append(message)
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
            chat.messages.append(message)
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

        if let roomName = selectedRoom {
            // Send to room via network
            let message = ChatMessage(
                username: networkClient?.username ?? "You",
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
                username: networkClient?.username ?? "You",
                content: content,
                isOwn: true
            )
            addPrivateMessage(username, message: message)

            Task {
                try? await networkClient?.sendPrivateMessage(to: username, message: content)
            }
        }
    }

    // MARK: - Room List
    func setAvailableRooms(_ rooms: [ChatRoom]) {
        availableRooms = rooms
        isLoadingRooms = false
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
