import Foundation

public struct ChatRoom: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var users: [String]
    public var messages: [ChatMessage]
    public var unreadCount: Int
    public var isJoined: Bool
    public var isPrivate: Bool
    public var owner: String?
    public var operators: Set<String>
    public var members: [String]
    public var tickers: [String: String]

    public init(
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

    public var userCount: Int {
        users.count
    }
}
