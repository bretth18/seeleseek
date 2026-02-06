import Foundation
import GRDB

/// Database record for persisted private messages
struct PrivateMessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "private_messages"

    var id: String
    var peerUsername: String      // The other user in the conversation
    var senderUsername: String    // Who sent this message
    var content: String
    var isOwn: Bool
    var isSystem: Bool
    var messageId: UInt32?       // Server message ID (for dedup)
    var timestamp: Double

    static func from(_ message: ChatMessage, peerUsername: String) -> PrivateMessageRecord {
        PrivateMessageRecord(
            id: message.id.uuidString,
            peerUsername: peerUsername,
            senderUsername: message.username,
            content: message.content,
            isOwn: message.isOwn,
            isSystem: message.isSystem,
            messageId: message.messageId,
            timestamp: message.timestamp.timeIntervalSince1970
        )
    }

    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: id) ?? UUID(),
            messageId: messageId,
            timestamp: Date(timeIntervalSince1970: timestamp),
            username: senderUsername,
            content: content,
            isSystem: isSystem,
            isOwn: isOwn
        )
    }
}
