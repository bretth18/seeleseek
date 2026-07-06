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

    /// Cached formatters — building a fresh DateFormatter per call is
    /// expensive and these run 2-3× per message-bubble render.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }

    public var formattedDate: String {
        Self.dateFormatter.string(from: timestamp)
    }
}
