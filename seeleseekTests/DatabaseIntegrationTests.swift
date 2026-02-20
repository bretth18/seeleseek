import Testing
import Foundation
import GRDB
@testable import seeleseek

/// Test database CRUD operations with an in-memory GRDB database using the same migrations
/// as the production DatabaseManager. Tests record types and migration schema directly.
@Suite("Database Integration Tests", .serialized)
struct DatabaseIntegrationTests {

    // MARK: - Test Database Helper

    /// Create an in-memory database with all production migrations applied
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            // v1: Initial schema
            try db.create(table: "transfers") { t in
                t.column("id", .text).primaryKey()
                t.column("username", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("direction", .text).notNull()
                t.column("status", .text).notNull()
                t.column("bytesTransferred", .integer).defaults(to: 0)
                t.column("startTime", .double)
                t.column("speed", .integer).defaults(to: 0)
                t.column("queuePosition", .integer)
                t.column("error", .text)
                t.column("localPath", .text)
                t.column("retryCount", .integer).defaults(to: 0)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(index: "idx_transfers_status", on: "transfers", columns: ["status"])

            try db.create(table: "search_queries") { t in
                t.column("id", .text).primaryKey()
                t.column("query", .text).notNull()
                t.column("token", .integer).notNull()
                t.column("timestamp", .double).notNull()
                t.column("createdAt", .double).notNull()
            }

            try db.create(table: "search_results") { t in
                t.column("id", .text).primaryKey()
                t.column("queryId", .text).notNull().references("search_queries", onDelete: .cascade)
                t.column("username", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("bitrate", .integer)
                t.column("duration", .integer)
                t.column("isVBR", .integer).defaults(to: 0)
                t.column("freeSlots", .integer).defaults(to: 1)
                t.column("uploadSpeed", .integer).defaults(to: 0)
                t.column("queueLength", .integer).defaults(to: 0)
            }
            try db.create(index: "idx_search_results_query", on: "search_results", columns: ["queryId"])

            try db.create(table: "user_shares") { t in
                t.column("id", .text).primaryKey()
                t.column("username", .text).notNull().unique()
                t.column("cachedAt", .double).notNull()
                t.column("totalFiles", .integer).defaults(to: 0)
                t.column("totalSize", .integer).defaults(to: 0)
            }

            try db.create(table: "shared_files") { t in
                t.column("id", .text).primaryKey()
                t.column("userSharesId", .text).notNull().references("user_shares", onDelete: .cascade)
                t.column("parentId", .text).references("shared_files", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("size", .integer).defaults(to: 0)
                t.column("bitrate", .integer)
                t.column("duration", .integer)
                t.column("isDirectory", .integer).defaults(to: 0)
                t.column("sortOrder", .integer).defaults(to: 0)
            }
            try db.create(index: "idx_shared_files_user", on: "shared_files", columns: ["userSharesId"])
            try db.create(index: "idx_shared_files_parent", on: "shared_files", columns: ["parentId"])

            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updatedAt", .double).notNull()
            }

            try db.create(table: "transfer_history") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .double).notNull()
                t.column("filename", .text).notNull()
                t.column("username", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("duration", .double).notNull()
                t.column("averageSpeed", .double).notNull()
                t.column("isDownload", .integer).notNull()
            }
            try db.create(index: "idx_transfer_history_timestamp", on: "transfer_history", columns: ["timestamp"])

            // v2: Social features
            try db.create(table: "buddies") { t in
                t.column("username", .text).primaryKey()
                t.column("notes", .text)
                t.column("dateAdded", .double).notNull()
                t.column("lastSeen", .double)
            }

            try db.create(table: "my_interests") { t in
                t.column("item", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("addedAt", .double).notNull()
            }

            try db.create(table: "my_profile") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            // v3: Blocklist
            try db.create(table: "blocked_users") { t in
                t.column("username", .text).primaryKey()
                t.column("reason", .text)
                t.column("dateBlocked", .double).notNull()
            }

            // v4: Private messages
            try db.create(table: "private_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("peerUsername", .text).notNull().indexed()
                t.column("senderUsername", .text).notNull()
                t.column("content", .text).notNull()
                t.column("isOwn", .integer).notNull()
                t.column("isSystem", .integer).notNull().defaults(to: 0)
                t.column("messageId", .integer)
                t.column("timestamp", .double).notNull()
            }
            try db.create(index: "idx_private_messages_peer_time", on: "private_messages", columns: ["peerUsername", "timestamp"])

            // v5: Wishlists
            try db.create(table: "wishlists") { t in
                t.column("id", .text).primaryKey()
                t.column("query", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("enabled", .integer).notNull().defaults(to: 1)
                t.column("lastSearchedAt", .double)
                t.column("resultCount", .integer).notNull().defaults(to: 0)
            }

            // v6: Extra columns
            try db.execute(sql: "ALTER TABLE search_results ADD COLUMN sampleRate INTEGER")
            try db.execute(sql: "ALTER TABLE search_results ADD COLUMN bitDepth INTEGER")
            try db.execute(sql: "ALTER TABLE transfer_history ADD COLUMN localPath TEXT")
        }
        return db
    }

    // MARK: - Migrations

    @Test("all tables exist after migration")
    func testAllTablesExist() throws {
        let db = try makeTestDatabase()
        let tables: [String] = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        let expected = ["blocked_users", "buddies", "my_interests", "my_profile",
                        "private_messages", "search_queries", "search_results",
                        "settings", "shared_files", "transfer_history", "transfers",
                        "user_shares", "wishlists"]
        for table in expected {
            #expect(tables.contains(table), "Missing table: \(table)")
        }
    }

    // MARK: - Search

    @Test("search: insert and fetch query")
    func testSearchInsertFetch() throws {
        let db = try makeTestDatabase()
        let queryId = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            let record = SearchQueryRecord(id: queryId, query: "pink floyd", token: 12345, timestamp: now, createdAt: now)
            try record.insert(db)
        }

        let fetched: SearchQueryRecord? = try db.read { db in
            try SearchQueryRecord.filter(Column("id") == queryId).fetchOne(db)
        }
        #expect(fetched?.query == "pink floyd")
        #expect(fetched?.token == 12345)
    }

    @Test("search: insert and fetch results by queryId")
    func testSearchResults() throws {
        let db = try makeTestDatabase()
        let queryId = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try SearchQueryRecord(id: queryId, query: "test", token: 1, timestamp: now, createdAt: now).insert(db)
            try SearchResultRecord(id: UUID().uuidString, queryId: queryId, username: "alice", filename: "song.mp3", size: 5_000_000, bitrate: 320, duration: 240, isVBR: false, freeSlots: true, uploadSpeed: 50000, queueLength: 3).insert(db)
            try SearchResultRecord(id: UUID().uuidString, queryId: queryId, username: "bob", filename: "track.flac", size: 30_000_000, bitrate: 1411, duration: 300, isVBR: false, freeSlots: false, uploadSpeed: 10000, queueLength: 10).insert(db)
        }

        let results: [SearchResultRecord] = try db.read { db in
            try SearchResultRecord.filter(Column("queryId") == queryId).fetchAll(db)
        }
        #expect(results.count == 2)
    }

    @Test("search: cascade delete removes results")
    func testSearchCascadeDelete() throws {
        let db = try makeTestDatabase()
        let queryId = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try SearchQueryRecord(id: queryId, query: "test", token: 1, timestamp: now, createdAt: now).insert(db)
            try SearchResultRecord(id: UUID().uuidString, queryId: queryId, username: "u", filename: "f", size: 1, bitrate: nil, duration: nil, isVBR: false, freeSlots: true, uploadSpeed: 0, queueLength: 0).insert(db)
        }

        try db.write { db in
            try SearchQueryRecord.filter(Column("id") == queryId).deleteAll(db)
        }

        let count: Int = try db.read { db in
            try SearchResultRecord.filter(Column("queryId") == queryId).fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test("search: expired cleanup")
    func testSearchExpiredCleanup() throws {
        let db = try makeTestDatabase()
        let oldTime = Date().timeIntervalSince1970 - 7200 // 2 hours ago
        let newTime = Date().timeIntervalSince1970

        try db.write { db in
            try SearchQueryRecord(id: UUID().uuidString, query: "old", token: 1, timestamp: oldTime, createdAt: oldTime).insert(db)
            try SearchQueryRecord(id: UUID().uuidString, query: "new", token: 2, timestamp: newTime, createdAt: newTime).insert(db)
        }

        // Delete queries older than 1 hour
        let cutoff = Date().timeIntervalSince1970 - 3600
        try db.write { db in
            try db.execute(sql: "DELETE FROM search_queries WHERE createdAt < ?", arguments: [cutoff])
        }

        let remaining: [SearchQueryRecord] = try db.read { db in
            try SearchQueryRecord.fetchAll(db)
        }
        #expect(remaining.count == 1)
        #expect(remaining[0].query == "new")
    }

    @Test("search: distinct history")
    func testSearchDistinctHistory() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try SearchQueryRecord(id: UUID().uuidString, query: "pink floyd", token: 1, timestamp: now, createdAt: now).insert(db)
            try SearchQueryRecord(id: UUID().uuidString, query: "pink floyd", token: 2, timestamp: now + 1, createdAt: now + 1).insert(db)
            try SearchQueryRecord(id: UUID().uuidString, query: "led zeppelin", token: 3, timestamp: now + 2, createdAt: now + 2).insert(db)
        }

        let distinct: [String] = try db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT query FROM search_queries ORDER BY createdAt DESC")
        }
        #expect(distinct.count == 2)
        #expect(distinct[0] == "led zeppelin")
        #expect(distinct[1] == "pink floyd")
    }

    // MARK: - Transfers

    @Test("transfers: insert and fetch")
    func testTransferInsertFetch() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            let record = TransferRecord(id: id, username: "alice", filename: "song.mp3", size: 5_000_000, direction: "download", status: "queued", bytesTransferred: 0, startTime: nil, speed: 0, queuePosition: 5, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now)
            try record.insert(db)
        }

        let fetched: TransferRecord? = try db.read { db in
            try TransferRecord.filter(Column("id") == id).fetchOne(db)
        }
        #expect(fetched?.username == "alice")
        #expect(fetched?.filename == "song.mp3")
        #expect(fetched?.direction == "download")
        #expect(fetched?.status == "queued")
    }

    @Test("transfers: update status")
    func testTransferUpdateStatus() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try TransferRecord(id: id, username: "u", filename: "f", size: 1, direction: "download", status: "queued", bytesTransferred: 0, startTime: nil, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
        }

        try db.write { db in
            try db.execute(sql: "UPDATE transfers SET status = ?, error = ?, updatedAt = ? WHERE id = ?",
                           arguments: ["failed", "Connection lost", now + 1, id])
        }

        let fetched: TransferRecord? = try db.read { db in
            try TransferRecord.filter(Column("id") == id).fetchOne(db)
        }
        #expect(fetched?.status == "failed")
        #expect(fetched?.error == "Connection lost")
    }

    @Test("transfers: update progress")
    func testTransferUpdateProgress() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try TransferRecord(id: id, username: "u", filename: "f", size: 10_000_000, direction: "download", status: "downloading", bytesTransferred: 0, startTime: now, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
        }

        try db.write { db in
            try db.execute(sql: "UPDATE transfers SET bytesTransferred = ?, speed = ? WHERE id = ?",
                           arguments: [Int64(5_000_000), Int64(100_000), id])
        }

        let fetched: TransferRecord? = try db.read { db in
            try TransferRecord.filter(Column("id") == id).fetchOne(db)
        }
        #expect(fetched?.bytesTransferred == 5_000_000)
        #expect(fetched?.speed == 100_000)
    }

    @Test("transfers: delete completed")
    func testTransferDeleteCompleted() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try TransferRecord(id: UUID().uuidString, username: "u", filename: "done.mp3", size: 1, direction: "download", status: "completed", bytesTransferred: 1, startTime: nil, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
            try TransferRecord(id: UUID().uuidString, username: "u", filename: "active.mp3", size: 1, direction: "download", status: "downloading", bytesTransferred: 0, startTime: nil, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
        }

        try db.write { db in
            try TransferRecord.filter(Column("status") == "completed").deleteAll(db)
        }

        let remaining: [TransferRecord] = try db.read { db in try TransferRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].status == "downloading")
    }

    @Test("transfers: filter by direction")
    func testTransferFilterDirection() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try TransferRecord(id: UUID().uuidString, username: "u", filename: "dl.mp3", size: 1, direction: "download", status: "queued", bytesTransferred: 0, startTime: nil, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
            try TransferRecord(id: UUID().uuidString, username: "u", filename: "ul.mp3", size: 1, direction: "upload", status: "queued", bytesTransferred: 0, startTime: nil, speed: 0, queuePosition: nil, error: nil, localPath: nil, retryCount: 0, createdAt: now, updatedAt: now).insert(db)
        }

        let downloads: [TransferRecord] = try db.read { db in
            try TransferRecord.filter(Column("direction") == "download").fetchAll(db)
        }
        #expect(downloads.count == 1)
        #expect(downloads[0].filename == "dl.mp3")

        let uploads: [TransferRecord] = try db.read { db in
            try TransferRecord.filter(Column("direction") == "upload").fetchAll(db)
        }
        #expect(uploads.count == 1)
        #expect(uploads[0].filename == "ul.mp3")
    }

    // MARK: - Wishlists

    @Test("wishlists: insert and fetchAll")
    func testWishlistInsertFetch() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try WishlistRecord(id: id, query: "rare vinyl", createdAt: now, enabled: 1, lastSearchedAt: nil, resultCount: 0).insert(db)
        }

        let all: [WishlistRecord] = try db.read { db in
            try WishlistRecord.order(Column("createdAt").asc).fetchAll(db)
        }
        #expect(all.count == 1)
        #expect(all[0].query == "rare vinyl")
        #expect(all[0].enabled == 1)
    }

    @Test("wishlists: update lastSearched")
    func testWishlistUpdateLastSearched() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try WishlistRecord(id: id, query: "test", createdAt: now, enabled: 1, lastSearchedAt: nil, resultCount: 0).insert(db)
        }

        try db.write { db in
            try db.execute(sql: "UPDATE wishlists SET lastSearchedAt = ?, resultCount = ? WHERE id = ?",
                           arguments: [now + 100, 42, id])
        }

        let fetched: WishlistRecord? = try db.read { db in
            try WishlistRecord.filter(Column("id") == id).fetchOne(db)
        }
        #expect(fetched?.resultCount == 42)
        #expect(fetched?.lastSearchedAt != nil)
    }

    @Test("wishlists: delete")
    func testWishlistDelete() throws {
        let db = try makeTestDatabase()
        let id = UUID().uuidString

        try db.write { db in
            try WishlistRecord(id: id, query: "delete me", createdAt: Date().timeIntervalSince1970, enabled: 1, lastSearchedAt: nil, resultCount: 0).insert(db)
        }

        try db.write { db in
            try WishlistRecord.filter(Column("id") == id).deleteAll(db)
        }

        let count: Int = try db.read { db in try WishlistRecord.fetchCount(db) }
        #expect(count == 0)
    }

    // MARK: - Buddies

    @Test("buddies: insert and fetch")
    func testBuddyInsertFetch() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try BuddyRecord(username: "alice", notes: "Best friend", dateAdded: Date().timeIntervalSince1970, lastSeen: nil).insert(db)
        }

        let all: [BuddyRecord] = try db.read { db in
            try BuddyRecord.order(Column("username").asc).fetchAll(db)
        }
        #expect(all.count == 1)
        #expect(all[0].username == "alice")
        #expect(all[0].notes == "Best friend")
    }

    @Test("buddies: upsert (same username updates notes)")
    func testBuddyUpsert() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try BuddyRecord(username: "bob", notes: "Old note", dateAdded: now, lastSeen: nil).save(db)
        }
        try db.write { db in
            try BuddyRecord(username: "bob", notes: "New note", dateAdded: now, lastSeen: now + 100).save(db)
        }

        let all: [BuddyRecord] = try db.read { db in try BuddyRecord.fetchAll(db) }
        #expect(all.count == 1)
        #expect(all[0].notes == "New note")
    }

    @Test("buddies: delete")
    func testBuddyDelete() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try BuddyRecord(username: "carol", notes: nil, dateAdded: Date().timeIntervalSince1970, lastSeen: nil).insert(db)
        }
        try db.write { db in
            try BuddyRecord.filter(Column("username") == "carol").deleteAll(db)
        }

        let count: Int = try db.read { db in try BuddyRecord.fetchCount(db) }
        #expect(count == 0)
    }

    // MARK: - Interests

    @Test("interests: insert and fetch (likes/hates)")
    func testInterestInsertFetch() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try InterestRecord(item: "jazz", type: "like", addedAt: now).insert(db)
            try InterestRecord(item: "blues", type: "like", addedAt: now + 1).insert(db)
            try InterestRecord(item: "noise", type: "hate", addedAt: now + 2).insert(db)
        }

        let all: [InterestRecord] = try db.read { db in
            try InterestRecord.order(Column("addedAt").asc).fetchAll(db)
        }
        let likes = all.filter { $0.type == "like" }
        let hates = all.filter { $0.type == "hate" }
        #expect(likes.count == 2)
        #expect(hates.count == 1)
        #expect(likes[0].item == "jazz")
        #expect(hates[0].item == "noise")
    }

    @Test("interests: delete by item")
    func testInterestDeleteByItem() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try InterestRecord(item: "jazz", type: "like", addedAt: Date().timeIntervalSince1970).insert(db)
        }
        try db.write { db in
            try InterestRecord.filter(Column("item") == "jazz").deleteAll(db)
        }

        let count: Int = try db.read { db in try InterestRecord.fetchCount(db) }
        #expect(count == 0)
    }

    @Test("interests: delete all by type")
    func testInterestDeleteAllByType() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try InterestRecord(item: "jazz", type: "like", addedAt: now).insert(db)
            try InterestRecord(item: "blues", type: "like", addedAt: now).insert(db)
            try InterestRecord(item: "noise", type: "hate", addedAt: now).insert(db)
        }

        try db.write { db in
            try InterestRecord.filter(Column("type") == "like").deleteAll(db)
        }

        let remaining: [InterestRecord] = try db.read { db in try InterestRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].type == "hate")
    }

    // MARK: - Blocked Users

    @Test("blocked users: insert and fetch")
    func testBlockedUserInsertFetch() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try BlockedUserRecord(username: "troll123", reason: "Spam", dateBlocked: Date()).insert(db)
        }

        let all: [BlockedUserRecord] = try db.read { db in try BlockedUserRecord.fetchAll(db) }
        #expect(all.count == 1)
        #expect(all[0].username == "troll123")
        #expect(all[0].reason == "Spam")
    }

    @Test("blocked users: isBlocked check")
    func testIsBlocked() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try BlockedUserRecord(username: "troll123", reason: nil, dateBlocked: Date()).insert(db)
        }

        let isBlocked: Bool = try db.read { db in
            try BlockedUserRecord.filter(Column("username") == "troll123").fetchCount(db) > 0
        }
        #expect(isBlocked == true)

        let isNotBlocked: Bool = try db.read { db in
            try BlockedUserRecord.filter(Column("username") == "friend").fetchCount(db) > 0
        }
        #expect(isNotBlocked == false)
    }

    @Test("blocked users: delete")
    func testBlockedUserDelete() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try BlockedUserRecord(username: "troll", reason: nil, dateBlocked: Date()).insert(db)
        }
        try db.write { db in
            try BlockedUserRecord.filter(Column("username") == "troll").deleteAll(db)
        }

        let count: Int = try db.read { db in try BlockedUserRecord.fetchCount(db) }
        #expect(count == 0)
    }

    // MARK: - Chat (Private Messages)

    @Test("chat: insert and fetch by peer")
    func testChatInsertFetch() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: "me", content: "Hello!", isOwn: true, isSystem: false, messageId: 1, timestamp: now).insert(db)
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: "alice", content: "Hi!", isOwn: false, isSystem: false, messageId: 2, timestamp: now + 1).insert(db)
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "bob", senderUsername: "bob", content: "Hey", isOwn: false, isSystem: false, messageId: 3, timestamp: now + 2).insert(db)
        }

        let aliceMessages: [PrivateMessageRecord] = try db.read { db in
            try PrivateMessageRecord.filter(Column("peerUsername") == "alice").order(Column("timestamp").asc).fetchAll(db)
        }
        #expect(aliceMessages.count == 2)
        #expect(aliceMessages[0].content == "Hello!")
        #expect(aliceMessages[1].content == "Hi!")
    }

    @Test("chat: list conversations")
    func testChatListConversations() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: "me", content: "msg1", isOwn: true, isSystem: false, messageId: nil, timestamp: now).insert(db)
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "bob", senderUsername: "bob", content: "msg2", isOwn: false, isSystem: false, messageId: nil, timestamp: now + 1).insert(db)
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: "alice", content: "msg3", isOwn: false, isSystem: false, messageId: nil, timestamp: now + 2).insert(db)
        }

        let conversations: [String] = try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT peerUsername FROM private_messages
                ORDER BY (SELECT MAX(timestamp) FROM private_messages pm2 WHERE pm2.peerUsername = private_messages.peerUsername) DESC
            """)
        }
        #expect(conversations.count == 2)
        #expect(conversations[0] == "alice") // most recent
        #expect(conversations[1] == "bob")
    }

    @Test("chat: delete conversation")
    func testChatDeleteConversation() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: "me", content: "x", isOwn: true, isSystem: false, messageId: nil, timestamp: now).insert(db)
            try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "bob", senderUsername: "bob", content: "y", isOwn: false, isSystem: false, messageId: nil, timestamp: now).insert(db)
        }

        try db.write { db in
            try PrivateMessageRecord.filter(Column("peerUsername") == "alice").deleteAll(db)
        }

        let remaining: [PrivateMessageRecord] = try db.read { db in try PrivateMessageRecord.fetchAll(db) }
        #expect(remaining.count == 1)
        #expect(remaining[0].peerUsername == "bob")
    }

    @Test("chat: prune old (keep 500)")
    func testChatPruneOld() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        // Insert 505 messages for one peer
        try db.write { db in
            for i in 0..<505 {
                try PrivateMessageRecord(id: UUID().uuidString, peerUsername: "alice", senderUsername: i % 2 == 0 ? "me" : "alice", content: "msg\(i)", isOwn: i % 2 == 0, isSystem: false, messageId: nil, timestamp: now + Double(i)).insert(db)
            }
        }

        // Prune keeping 500
        try db.write { db in
            let conversations = try String.fetchAll(db, sql: "SELECT DISTINCT peerUsername FROM private_messages")
            for peer in conversations {
                let ids = try String.fetchAll(db, sql: """
                    SELECT id FROM private_messages WHERE peerUsername = ?
                    ORDER BY timestamp DESC LIMIT -1 OFFSET 500
                """, arguments: [peer])
                if !ids.isEmpty {
                    try db.execute(sql: "DELETE FROM private_messages WHERE id IN (\(ids.map { "'\($0)'" }.joined(separator: ",")))")
                }
            }
        }

        let count: Int = try db.read { db in
            try PrivateMessageRecord.filter(Column("peerUsername") == "alice").fetchCount(db)
        }
        #expect(count == 500)
    }

    // MARK: - Browse Cache

    @Test("browse cache: insert shares and files")
    func testBrowseCacheInsert() throws {
        let db = try makeTestDatabase()
        let sharesId = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try UserSharesRecord(id: sharesId, username: "alice", cachedAt: now, totalFiles: 2, totalSize: 10_000_000).insert(db)
            try SharedFileRecord(id: UUID().uuidString, userSharesId: sharesId, parentId: nil, filename: "Music", size: 0, bitrate: nil, duration: nil, isDirectory: true, sortOrder: 0).insert(db)
            try SharedFileRecord(id: UUID().uuidString, userSharesId: sharesId, parentId: nil, filename: "song.mp3", size: 5_000_000, bitrate: 320, duration: 240, isDirectory: false, sortOrder: 1).insert(db)
        }

        let shares: UserSharesRecord? = try db.read { db in
            try UserSharesRecord.filter(Column("username") == "alice").fetchOne(db)
        }
        #expect(shares?.totalFiles == 2)

        let files: [SharedFileRecord] = try db.read { db in
            try SharedFileRecord.filter(Column("userSharesId") == sharesId).fetchAll(db)
        }
        #expect(files.count == 2)
    }

    @Test("browse cache: cache validity")
    func testBrowseCacheValidity() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try UserSharesRecord(id: UUID().uuidString, username: "recent", cachedAt: now, totalFiles: 0, totalSize: 0).insert(db)
            try UserSharesRecord(id: UUID().uuidString, username: "old", cachedAt: now - 100_000, totalFiles: 0, totalSize: 0).insert(db)
        }

        let ttl: TimeInterval = 86400
        let cutoff = now - ttl

        let recentValid: Bool = try db.read { db in
            try UserSharesRecord.filter(Column("username") == "recent" && Column("cachedAt") > cutoff).fetchCount(db) > 0
        }
        #expect(recentValid == true)

        let oldValid: Bool = try db.read { db in
            try UserSharesRecord.filter(Column("username") == "old" && Column("cachedAt") > cutoff).fetchCount(db) > 0
        }
        #expect(oldValid == false)
    }

    @Test("browse cache: delete expired cascades to files")
    func testBrowseCacheDeleteExpired() throws {
        let db = try makeTestDatabase()
        let oldSharesId = UUID().uuidString
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try UserSharesRecord(id: oldSharesId, username: "old", cachedAt: now - 200_000, totalFiles: 1, totalSize: 1000).insert(db)
            try SharedFileRecord(id: UUID().uuidString, userSharesId: oldSharesId, parentId: nil, filename: "f.mp3", size: 1000, bitrate: nil, duration: nil, isDirectory: false, sortOrder: 0).insert(db)
        }

        let cutoff = now - 86400
        try db.write { db in
            try db.execute(sql: "DELETE FROM user_shares WHERE cachedAt < ?", arguments: [cutoff])
        }

        let shareCount: Int = try db.read { db in try UserSharesRecord.fetchCount(db) }
        let fileCount: Int = try db.read { db in try SharedFileRecord.fetchCount(db) }
        #expect(shareCount == 0)
        #expect(fileCount == 0) // cascade
    }

    // MARK: - Settings

    @Test("settings: insert and fetch")
    func testSettingsInsertFetch() throws {
        let db = try makeTestDatabase()

        try db.write { db in
            try SettingRecord(key: "theme", value: "\"dark\"", updatedAt: Date().timeIntervalSince1970).insert(db)
        }

        let setting: SettingRecord? = try db.read { db in
            try SettingRecord.filter(Column("key") == "theme").fetchOne(db)
        }
        #expect(setting?.value == "\"dark\"")
    }

    @Test("settings: update existing")
    func testSettingsUpdate() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try SettingRecord(key: "volume", value: "80", updatedAt: now).save(db)
        }
        try db.write { db in
            try SettingRecord(key: "volume", value: "100", updatedAt: now + 1).save(db)
        }

        let setting: SettingRecord? = try db.read { db in
            try SettingRecord.filter(Column("key") == "volume").fetchOne(db)
        }
        #expect(setting?.value == "100")

        let count: Int = try db.read { db in try SettingRecord.fetchCount(db) }
        #expect(count == 1)
    }

    // MARK: - Transfer History

    @Test("transfer history: insert and fetch")
    func testTransferHistoryInsertFetch() throws {
        let db = try makeTestDatabase()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try TransferHistoryRecord(id: UUID().uuidString, timestamp: now, filename: "song.mp3", username: "alice", size: 5_000_000, duration: 10.5, averageSpeed: 476190.5, isDownload: true, localPath: "/tmp/song.mp3").insert(db)
        }

        let all: [TransferHistoryRecord] = try db.read { db in try TransferHistoryRecord.fetchAll(db) }
        #expect(all.count == 1)
        #expect(all[0].filename == "song.mp3")
        #expect(all[0].isDownload == true)
        #expect(all[0].localPath == "/tmp/song.mp3")
    }
}
