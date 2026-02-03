import SwiftUI

@Observable
@MainActor
final class ChatState {
    // MARK: - Rooms
    var availableRooms: [ChatRoom] = []
    var joinedRooms: [ChatRoom] = []
    var selectedRoom: String?

    // MARK: - Private Chats
    var privateChats: [PrivateChat] = []
    var selectedPrivateChat: String?

    // MARK: - Input
    var messageInput: String = ""
    var roomSearchQuery: String = ""

    // MARK: - Loading State
    var isLoadingRooms: Bool = false

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Setup
    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        client.onRoomList = { [weak self] rooms in
            self?.setAvailableRooms(rooms)
        }

        client.onRoomJoined = { [weak self] roomName, users in
            self?.handleRoomJoined(roomName, users: users)
        }

        client.onRoomLeft = { [weak self] roomName in
            self?.handleRoomLeft(roomName)
        }

        client.onRoomMessage = { [weak self] roomName, message in
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
    }

    private func handleRoomJoined(_ roomName: String, users: [String]) {
        if !joinedRooms.contains(where: { $0.name == roomName }) {
            let room = ChatRoom(name: roomName, users: users, isJoined: true)
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
            // Add system message
            let message = ChatMessage(username: "", content: "\(username) joined the room", isSystem: true)
            joinedRooms[index].messages.append(message)
        }
    }

    private func handleUserLeftRoom(_ roomName: String, username: String) {
        if let index = joinedRooms.firstIndex(where: { $0.name == roomName }) {
            joinedRooms[index].users.removeAll { $0 == username }
            // Add system message
            let message = ChatMessage(username: "", content: "\(username) left the room", isSystem: true)
            joinedRooms[index].messages.append(message)
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
        if roomSearchQuery.isEmpty {
            return availableRooms.sorted { $0.userCount > $1.userCount }
        }
        return availableRooms.filter {
            $0.name.localizedCaseInsensitiveContains(roomSearchQuery)
        }.sorted { $0.userCount > $1.userCount }
    }

    var totalUnreadCount: Int {
        joinedRooms.reduce(0) { $0 + $1.unreadCount } +
        privateChats.reduce(0) { $0 + $1.unreadCount }
    }

    var canSendMessage: Bool {
        !messageInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Room Actions
    func joinRoom(_ name: String) {
        Task {
            try? await networkClient?.joinRoom(name)
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

    // MARK: - Private Chat Actions
    func selectPrivateChat(_ username: String) {
        selectedPrivateChat = username
        selectedRoom = nil

        // Create chat if doesn't exist
        if !privateChats.contains(where: { $0.username == username }) {
            privateChats.append(PrivateChat(username: username))
        }

        // Clear unread
        if let index = privateChats.firstIndex(where: { $0.username == username }) {
            privateChats[index].unreadCount = 0
        }
    }

    func addPrivateMessage(_ username: String, message: ChatMessage) {
        if let index = privateChats.firstIndex(where: { $0.username == username }) {
            privateChats[index].messages.append(message)
            if selectedPrivateChat != username {
                privateChats[index].unreadCount += 1
            }
        } else {
            // Create new chat
            var chat = PrivateChat(username: username)
            chat.messages.append(message)
            chat.unreadCount = 1
            privateChats.append(chat)
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

        let content = messageInput.trimmingCharacters(in: .whitespaces)
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
}
