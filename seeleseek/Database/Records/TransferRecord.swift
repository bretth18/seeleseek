import Foundation
import GRDB

/// Database record for Transfer persistence
struct TransferRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transfers"

    var id: String
    var username: String
    var filename: String
    var size: Int64
    var direction: String
    var status: String
    var bytesTransferred: Int64
    var startTime: Double?
    var speed: Int64
    var queuePosition: Int?
    var error: String?
    var localPath: String?
    var retryCount: Int
    var createdAt: Double
    var updatedAt: Double

    /// Convert database record to domain model
    func toTransfer() -> Transfer {
        Transfer(
            id: UUID(uuidString: id) ?? UUID(),
            username: username,
            filename: filename,
            size: UInt64(size),
            direction: Transfer.TransferDirection(rawValue: direction) ?? .download,
            status: Transfer.TransferStatus(rawValue: status) ?? .queued,
            bytesTransferred: UInt64(bytesTransferred),
            startTime: startTime.map { Date(timeIntervalSince1970: $0) },
            speed: speed,
            queuePosition: queuePosition,
            error: error,
            localPath: localPath.map { URL(fileURLWithPath: $0) },
            retryCount: retryCount
        )
    }

    /// Create database record from domain model
    static func from(_ transfer: Transfer) -> TransferRecord {
        let now = Date().timeIntervalSince1970
        return TransferRecord(
            id: transfer.id.uuidString,
            username: transfer.username,
            filename: transfer.filename,
            size: Int64(transfer.size),
            direction: transfer.direction.rawValue,
            status: transfer.status.rawValue,
            bytesTransferred: Int64(transfer.bytesTransferred),
            startTime: transfer.startTime?.timeIntervalSince1970,
            speed: transfer.speed,
            queuePosition: transfer.queuePosition,
            error: transfer.error,
            localPath: transfer.localPath?.path,
            retryCount: transfer.retryCount,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Create updated record preserving creation time
    static func from(_ transfer: Transfer, createdAt: Double) -> TransferRecord {
        var record = from(transfer)
        record.createdAt = createdAt
        return record
    }
}
