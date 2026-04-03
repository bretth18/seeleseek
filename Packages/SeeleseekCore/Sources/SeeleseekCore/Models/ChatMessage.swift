import Foundation

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let messageId: UInt32?
    public let timestamp: Date
    public let username: String
    public let content: String
    public let isSystem: Bool
    public let isOwn: Bool
    public let isNewMessage: Bool  // true = real-time, false = offline/buffered

    public init(
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

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
