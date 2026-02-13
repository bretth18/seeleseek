import Foundation
import GRDB

/// Repository for Settings database operations
struct SettingsRepository {
    /// Get a setting value with a default fallback
    static func get<T: Decodable & Sendable>(_ key: String, default defaultValue: T) async throws -> T {
        try await DatabaseManager.shared.read { db in
            guard let record = try SettingRecord
                .filter(Column("key") == key)
                .fetchOne(db),
                  let value: T = record.decode(T.self) else {
                return defaultValue
            }
            return value
        }
    }

    /// Get a setting value (returns nil if not found)
    static func get<T: Decodable & Sendable>(_ key: String) async throws -> T? {
        try await DatabaseManager.shared.read { db in
            guard let record = try SettingRecord
                .filter(Column("key") == key)
                .fetchOne(db) else {
                return nil
            }
            return record.decode(T.self)
        }
    }

    /// Set a setting value
    static func set<T: Encodable & Sendable>(_ key: String, value: T) async throws {
        let record = try SettingRecord.create(key: key, value: value)

        try await DatabaseManager.shared.write { db in
            // Use upsert (insert or replace)
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO settings (key, value, updatedAt)
                    VALUES (?, ?, ?)
                    """,
                arguments: [record.key, record.value, record.updatedAt]
            )
        }
    }

    /// Delete a setting
    static func delete(_ key: String) async throws {
        _ = try await DatabaseManager.shared.write { db in
            try SettingRecord.filter(Column("key") == key).deleteAll(db)
        }
    }

    /// Get all settings (for debugging/export)
    static func getAll() async throws -> [String: String] {
        try await DatabaseManager.shared.read { db in
            let records = try SettingRecord.fetchAll(db)
            var result: [String: String] = [:]
            for record in records {
                result[record.key] = record.value
            }
            return result
        }
    }

    /// Check if database has been migrated from UserDefaults
    static func isMigrated() async throws -> Bool {
        try await get("db_migrated_v1", default: false)
    }

    /// Mark migration as complete
    static func markMigrated() async throws {
        try await set("db_migrated_v1", value: true)
    }
}

// MARK: - Transfer History Repository

/// Repository for Transfer History (statistics) operations
struct TransferHistoryRepository {
    /// Record a completed transfer
    static func record(_ history: TransferHistoryRecord) async throws {
        _ = try await DatabaseManager.shared.write { db in
            let record = history
            try record.insert(db)
        }
    }

    /// Fetch recent transfer history
    static func fetchRecent(limit: Int = 100) async throws -> [TransferHistoryRecord] {
        try await DatabaseManager.shared.read { db in
            try TransferHistoryRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch transfer history for a date range
    static func fetch(from startDate: Date, to endDate: Date) async throws -> [TransferHistoryRecord] {
        try await DatabaseManager.shared.read { db in
            try TransferHistoryRecord
                .filter(Column("timestamp") >= startDate.timeIntervalSince1970 &&
                        Column("timestamp") <= endDate.timeIntervalSince1970)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Get aggregate statistics
    static func getStats() async throws -> TransferStats {
        try await DatabaseManager.shared.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) as totalTransfers,
                    SUM(CASE WHEN isDownload = 1 THEN 1 ELSE 0 END) as totalDownloads,
                    SUM(CASE WHEN isDownload = 0 THEN 1 ELSE 0 END) as totalUploads,
                    SUM(CASE WHEN isDownload = 1 THEN size ELSE 0 END) as totalDownloadedBytes,
                    SUM(CASE WHEN isDownload = 0 THEN size ELSE 0 END) as totalUploadedBytes,
                    AVG(averageSpeed) as avgSpeed
                FROM transfer_history
                """)

            return TransferStats(
                totalTransfers: row?["totalTransfers"] ?? 0,
                totalDownloads: row?["totalDownloads"] ?? 0,
                totalUploads: row?["totalUploads"] ?? 0,
                totalDownloadedBytes: row?["totalDownloadedBytes"] ?? 0,
                totalUploadedBytes: row?["totalUploadedBytes"] ?? 0,
                averageSpeed: row?["avgSpeed"] ?? 0
            )
        }
    }

    /// Delete history older than a certain date
    static func deleteOlderThan(_ date: Date) async throws {
        _ = try await DatabaseManager.shared.write { db in
            try TransferHistoryRecord
                .filter(Column("timestamp") < date.timeIntervalSince1970)
                .deleteAll(db)
        }
    }
}

/// Aggregate transfer statistics
struct TransferStats: Sendable {
    let totalTransfers: Int
    let totalDownloads: Int
    let totalUploads: Int
    let totalDownloadedBytes: Int64
    let totalUploadedBytes: Int64
    let averageSpeed: Double
}
