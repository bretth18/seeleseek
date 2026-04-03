import Foundation

public struct PrivateChat: Identifiable, Hashable, Sendable {
    public let id: String
    public let username: String
    public var messages: [ChatMessage]
    public var unreadCount: Int
    public var isOnline: Bool

    public init(
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
