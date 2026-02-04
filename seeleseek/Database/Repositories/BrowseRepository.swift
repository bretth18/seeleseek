import Foundation
import GRDB

/// Repository for Browse cache database operations
struct BrowseRepository {
    /// Fetch cached user shares by username
    static func fetch(username: String) async throws -> UserShares? {
        try await DatabaseManager.shared.read { db in
            guard let userSharesRecord = try UserSharesRecord
                .filter(Column("username").collating(.nocase) == username)
                .fetchOne(db) else {
                return nil
            }

            // Fetch all files for this user
            let fileRecords = try SharedFileRecord
                .filter(Column("userSharesId") == userSharesRecord.id)
                .fetchAll(db)

            // Build hierarchical structure
            let folders = SharedFileRecord.toSharedFiles(from: fileRecords)

            return userSharesRecord.toUserShares(folders: folders)
        }
    }

    /// Check if cache is valid for a username
    static func isCacheValid(username: String, ttl: TimeInterval) async throws -> Bool {
        let minCacheTime = Date().timeIntervalSince1970 - ttl

        return try await DatabaseManager.shared.read { db in
            let count = try UserSharesRecord
                .filter(Column("username").collating(.nocase) == username && Column("cachedAt") >= minCacheTime)
                .fetchCount(db)
            return count > 0
        }
    }

    /// Save user shares to cache
    static func save(_ userShares: UserShares) async throws {
        try await DatabaseManager.shared.write { db in
            // Delete existing cache for this user
            try UserSharesRecord
                .filter(Column("username").collating(.nocase) == userShares.username)
                .deleteAll(db)

            // Insert new user shares record
            var userSharesRecord = UserSharesRecord.from(userShares)
            try userSharesRecord.insert(db)

            // Insert all files
            let fileRecords = SharedFileRecord.from(userShares.folders, userSharesId: userShares.id)
            for var record in fileRecords {
                try record.insert(db)
            }
        }
    }

    /// Delete cache for a specific user
    static func delete(username: String) async throws {
        try await DatabaseManager.shared.write { db in
            try UserSharesRecord
                .filter(Column("username").collating(.nocase) == username)
                .deleteAll(db)
        }
    }

    /// Delete expired cache entries
    static func deleteExpired(olderThan age: TimeInterval) async throws {
        let cutoff = Date().timeIntervalSince1970 - age

        try await DatabaseManager.shared.write { db in
            try UserSharesRecord.filter(Column("cachedAt") < cutoff).deleteAll(db)
        }
    }

    /// Get list of cached usernames (for browse history)
    static func fetchCachedUsernames() async throws -> [String] {
        try await DatabaseManager.shared.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT username FROM user_shares
                ORDER BY cachedAt DESC
                """)
            return rows.map { $0["username"] as String }
        }
    }

    /// Get cache statistics
    static func getCacheStats() async throws -> (userCount: Int, totalFiles: Int, totalSize: Int64) {
        try await DatabaseManager.shared.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as userCount,
                       COALESCE(SUM(totalFiles), 0) as totalFiles,
                       COALESCE(SUM(totalSize), 0) as totalSize
                FROM user_shares
                """)
            return (
                userCount: row?["userCount"] ?? 0,
                totalFiles: row?["totalFiles"] ?? 0,
                totalSize: row?["totalSize"] ?? 0
            )
        }
    }
}
