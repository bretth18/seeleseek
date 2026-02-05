import Foundation
import GRDB
import os

/// Actor-based database coordinator for SQLite persistence via GRDB
actor DatabaseManager {
    static let shared = DatabaseManager()

    private let logger = Logger(subsystem: "com.seeleseek", category: "Database")
    private var dbPool: DatabasePool?

    // Cache TTLs
    let searchCacheTTL: TimeInterval = 3600      // 1 hour
    let browseCacheTTL: TimeInterval = 86400     // 24 hours

    enum DatabaseError: Error, LocalizedError {
        case notInitialized
        case migrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "Database not initialized"
            case .migrationFailed(let reason):
                return "Migration failed: \(reason)"
            }
        }
    }

    /// Initialize the database and run migrations
    func initialize() async throws {
        // Guard against multiple initializations
        guard dbPool == nil else {
            logger.debug("Database already initialized, skipping")
            return
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("SeeleSeek")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("seeleseek.sqlite")
        logger.info("Database path: \(dbPath.path)")

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Enable WAL mode for better concurrent access
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbPool = try DatabasePool(path: dbPath.path, configuration: config)
        try await migrate()

        logger.info("Database initialized successfully")
    }

    /// Run database migrations
    private func migrate() async throws {
        guard let dbPool else { throw DatabaseError.notInitialized }

        var migrator = DatabaseMigrator()

        // v1: Initial schema
        migrator.registerMigration("v1") { db in
            // transfers: Download/upload queue with resume support
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

            // search_queries: Search history with TTL
            try db.create(table: "search_queries") { t in
                t.column("id", .text).primaryKey()
                t.column("query", .text).notNull()
                t.column("token", .integer).notNull()
                t.column("timestamp", .double).notNull()
                t.column("createdAt", .double).notNull()
            }

            // search_results: Results linked to queries
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

            // user_shares: Browse cache
            try db.create(table: "user_shares") { t in
                t.column("id", .text).primaryKey()
                t.column("username", .text).notNull().unique()
                t.column("cachedAt", .double).notNull()
                t.column("totalFiles", .integer).defaults(to: 0)
                t.column("totalSize", .integer).defaults(to: 0)
            }

            // shared_files: Hierarchical file tree
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

            // settings: Key-value store
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // transfer_history: Statistics
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
        }

        // v2: Social features (buddies, interests, profile)
        migrator.registerMigration("v2") { db in
            // buddies: Persistent buddy list
            try db.create(table: "buddies") { t in
                t.column("username", .text).primaryKey()
                t.column("notes", .text)
                t.column("dateAdded", .double).notNull()
                t.column("lastSeen", .double)
            }

            // my_interests: User's likes and hates
            try db.create(table: "my_interests") { t in
                t.column("item", .text).primaryKey()
                t.column("type", .text).notNull()  // "like" or "hate"
                t.column("addedAt", .double).notNull()
            }

            // my_profile: User profile settings
            try db.create(table: "my_profile") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        try migrator.migrate(dbPool)

        logger.info("Database migrations completed")
    }

    /// Execute a read operation on the database
    func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        guard let dbPool else { throw DatabaseError.notInitialized }
        return try await dbPool.read(block)
    }

    /// Execute a write operation on the database
    func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        guard let dbPool else { throw DatabaseError.notInitialized }
        return try await dbPool.write(block)
    }

    /// Check if database is initialized
    var isInitialized: Bool {
        dbPool != nil
    }

    /// Clean up expired cache entries
    func cleanupExpiredCache() async throws {
        let now = Date().timeIntervalSince1970

        try await write { db in
            // Clean expired search queries
            let searchExpiry = now - 3600 // 1 hour
            try db.execute(
                sql: "DELETE FROM search_queries WHERE createdAt < ?",
                arguments: [searchExpiry]
            )

            // Clean expired browse cache
            let browseExpiry = now - 86400 // 24 hours
            try db.execute(
                sql: "DELETE FROM user_shares WHERE cachedAt < ?",
                arguments: [browseExpiry]
            )
        }

        logger.info("Expired cache cleaned up")
    }
}
