import Foundation
import GRDB

/// Repository for Transfer database operations
struct TransferRepository {
    /// Fetch all persisted transfers (everything except completed)
    static func fetchPersisted() async throws -> [Transfer] {
        try await DatabaseManager.shared.read { db in
            let records = try TransferRecord
                .filter(Column("status") != "completed")
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.map { $0.toTransfer() }
        }
    }

    /// Fetch all transfers
    static func fetchAll() async throws -> [Transfer] {
        try await DatabaseManager.shared.read { db in
            let records = try TransferRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.map { $0.toTransfer() }
        }
    }

    /// Fetch transfers by direction
    static func fetch(direction: Transfer.TransferDirection) async throws -> [Transfer] {
        try await DatabaseManager.shared.read { db in
            let records = try TransferRecord
                .filter(Column("direction") == direction.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
            return records.map { $0.toTransfer() }
        }
    }

    /// Fetch a single transfer by ID
    static func fetch(id: UUID) async throws -> Transfer? {
        try await DatabaseManager.shared.read { db in
            let record = try TransferRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
            return record?.toTransfer()
        }
    }

    /// Save a transfer (insert or update)
    static func save(_ transfer: Transfer) async throws {
        _ = try await DatabaseManager.shared.write { db in
            // Check if exists to preserve createdAt
            if let existing = try TransferRecord.filter(Column("id") == transfer.id.uuidString).fetchOne(db) {
                let record = TransferRecord.from(transfer, createdAt: existing.createdAt)
                try record.update(db)
            } else {
                let record = TransferRecord.from(transfer)
                try record.insert(db)
            }
        }
    }

    /// Update transfer status
    static func updateStatus(id: UUID, status: Transfer.TransferStatus, error: String? = nil) async throws {
        try await DatabaseManager.shared.write { db in
            try db.execute(
                sql: """
                    UPDATE transfers
                    SET status = ?, error = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, error, Date().timeIntervalSince1970, id.uuidString]
            )
        }
    }

    /// Update transfer progress
    static func updateProgress(id: UUID, bytesTransferred: UInt64, speed: Int64) async throws {
        try await DatabaseManager.shared.write { db in
            try db.execute(
                sql: """
                    UPDATE transfers
                    SET bytesTransferred = ?, speed = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Int64(bytesTransferred), speed, Date().timeIntervalSince1970, id.uuidString]
            )
        }
    }

    /// Delete a transfer
    static func delete(id: UUID) async throws {
        _ = try await DatabaseManager.shared.write { db in
            try TransferRecord.filter(Column("id") == id.uuidString).deleteAll(db)
        }
    }

    /// Delete completed transfers
    static func deleteCompleted() async throws {
        _ = try await DatabaseManager.shared.write { db in
            try TransferRecord.filter(Column("status") == "completed").deleteAll(db)
        }
    }

    /// Delete failed/cancelled transfers
    static func deleteFailed() async throws {
        _ = try await DatabaseManager.shared.write { db in
            try TransferRecord
                .filter(["failed", "cancelled"].contains(Column("status")))
                .deleteAll(db)
        }
    }

    /// Record completed transfer to history
    static func recordCompletion(_ transfer: Transfer) async throws {
        guard let startTime = transfer.startTime else { return }
        let duration = Date().timeIntervalSince(startTime)

        _ = try await DatabaseManager.shared.write { db in
            let record = TransferHistoryRecord.from(transfer, duration: duration)
            try record.insert(db)
        }
    }
}
