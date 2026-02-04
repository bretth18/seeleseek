import Foundation
import GRDB

/// Database record for UserShares (browse cache) persistence
struct UserSharesRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "user_shares"

    var id: String
    var username: String
    var cachedAt: Double
    var totalFiles: Int
    var totalSize: Int64

    /// Convert database record to domain model (folders loaded separately)
    func toUserShares(folders: [SharedFile] = []) -> UserShares {
        UserShares(
            id: UUID(uuidString: id) ?? UUID(),
            username: username,
            folders: folders,
            isLoading: false,
            error: nil
        )
    }

    /// Create database record from domain model
    static func from(_ userShares: UserShares) -> UserSharesRecord {
        UserSharesRecord(
            id: userShares.id.uuidString,
            username: userShares.username,
            cachedAt: Date().timeIntervalSince1970,
            totalFiles: userShares.totalFiles,
            totalSize: Int64(userShares.totalSize)
        )
    }
}
