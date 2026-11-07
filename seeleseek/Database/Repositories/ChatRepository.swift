import Foundation
import GRDB
import SeeleseekCore

/// Repository for chat message persistence
struct ChatRepository {
    /// Every conversation (most recent first) with its last N messages, in one read.
    static func fetchAllConversations(limit: Int = 200) async throws -> [(peer: String, messages: [ChatMessage])] {
        try await DatabaseManager.shared.read { db in try allConversations(limit: limit, in: db) }
    }

    nonisolated static func allConversations(limit: Int, in db: Database) throws -> [(peer: String, messages: [ChatMessage])] {
        let peers = try String.fetchAll(db, sql: """
            SELECT DISTINCT peerUsername FROM private_messages
            ORDER BY (SELECT MAX(timestamp) FROM private_messages pm2 WHERE pm2.peerUsername = private_messages.peerUsername) DESC
        """)
        return try peers.map { ($0, try recentMessages(for: $0, limit: limit, in: db)) }
    }

    nonisolated private static func recentMessages(for peerUsername: String, limit: Int, in db: Database) throws -> [ChatMessage] {
        let records = try PrivateMessageRecord
            .filter(Column("peerUsername") == peerUsername)
            .order(Column("timestamp").desc)
            .limit(limit)
            .fetchAll(db)
        return records.reversed().map { $0.toChatMessage() }
    }

    /// Save a single message
    static func saveMessage(_ message: ChatMessage, peerUsername: String) async throws {
        _ = try await DatabaseManager.shared.write { db in
            let record = PrivateMessageRecord.from(message, peerUsername: peerUsername)
            try record.save(db)
        }
    }

    /// Delete all messages for a conversation
    static func deleteConversation(_ peerUsername: String) async throws {
        _ = try await DatabaseManager.shared.write { db in
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
