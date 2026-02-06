import Foundation
import GRDB

/// Repository for chat message persistence
struct ChatRepository {
    /// Fetch all private message conversations (distinct peer usernames)
    static func fetchConversations() async throws -> [String] {
        try await DatabaseManager.shared.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT peerUsername FROM private_messages
                ORDER BY (SELECT MAX(timestamp) FROM private_messages pm2 WHERE pm2.peerUsername = private_messages.peerUsername) DESC
            """)
        }
    }

    /// Fetch messages for a specific conversation, most recent N messages
    static func fetchMessages(for peerUsername: String, limit: Int = 200) async throws -> [ChatMessage] {
        try await DatabaseManager.shared.read { db in
            let records = try PrivateMessageRecord
                .filter(Column("peerUsername") == peerUsername)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
            return records.reversed().map { $0.toChatMessage() }
        }
    }

    /// Save a single message
    static func saveMessage(_ message: ChatMessage, peerUsername: String) async throws {
        try await DatabaseManager.shared.write { db in
            var record = PrivateMessageRecord.from(message, peerUsername: peerUsername)
            try record.save(db)
        }
    }

    /// Delete all messages for a conversation
    static func deleteConversation(_ peerUsername: String) async throws {
        try await DatabaseManager.shared.write { db in
            try PrivateMessageRecord
                .filter(Column("peerUsername") == peerUsername)
                .deleteAll(db)
        }
    }

    /// Delete old messages (keep last N per conversation)
    static func pruneOldMessages(keepPerConversation: Int = 500) async throws {
        try await DatabaseManager.shared.write { db in
            // Get all conversations
            let peers = try String.fetchAll(db, sql: "SELECT DISTINCT peerUsername FROM private_messages")

            for peer in peers {
                let count = try PrivateMessageRecord
                    .filter(Column("peerUsername") == peer)
                    .fetchCount(db)

                if count > keepPerConversation {
                    // Delete oldest messages beyond the limit
                    try db.execute(sql: """
                        DELETE FROM private_messages WHERE id IN (
                            SELECT id FROM private_messages
                            WHERE peerUsername = ?
                            ORDER BY timestamp ASC
                            LIMIT ?
                        )
                    """, arguments: [peer, count - keepPerConversation])
                }
            }
        }
    }
}
