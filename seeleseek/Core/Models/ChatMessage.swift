import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let messageId: UInt32?
    let timestamp: Date
    let username: String
    let content: String
    let isSystem: Bool
    let isOwn: Bool
    let isNewMessage: Bool  // true = real-time, false = offline/buffered

    init(
        id: UUID = UUID(),
        messageId: UInt32? = nil,
        timestamp: Date = Date(),
        username: String,
        content: String,
        isSystem: Bool = false,
        isOwn: Bool = false,
        isNewMessage: Bool = true
    ) {
        self.id = id
        self.messageId = messageId
        self.timestamp = timestamp
        self.username = username
        self.content = content
        self.isSystem = isSystem
        self.isOwn = isOwn
        self.isNewMessage = isNewMessage
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct ChatRoom: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var users: [String]
    var messages: [ChatMessage]
    var unreadCount: Int
    var isJoined: Bool
    var isPrivate: Bool
    var owner: String?
    var operators: Set<String>
    var members: [String]
    var tickers: [String: String]

    init(
        name: String,
        users: [String] = [],
        messages: [ChatMessage] = [],
        unreadCount: Int = 0,
        isJoined: Bool = false,
        isPrivate: Bool = false,
        owner: String? = nil,
        operators: Set<String> = [],
        members: [String] = [],
        tickers: [String: String] = [:]
    ) {
        self.id = name
        self.name = name
        self.users = users
        self.messages = messages
        self.unreadCount = unreadCount
        self.isJoined = isJoined
        self.isPrivate = isPrivate
        self.owner = owner
        self.operators = operators
        self.members = members
        self.tickers = tickers
    }

    var userCount: Int {
        users.count
    }
}

struct PrivateChat: Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    var messages: [ChatMessage]
    var unreadCount: Int
    var isOnline: Bool

    init(
        username: String,
        messages: [ChatMessage] = [],
        unreadCount: Int = 0,
        isOnline: Bool = false
    ) {
        self.id = username
        self.username = username
        self.messages = messages
        self.unreadCount = unreadCount
        self.isOnline = isOnline
    }
}
