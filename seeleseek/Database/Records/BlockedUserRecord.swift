import Foundation
import GRDB

struct BlockedUserRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "blocked_users"

    var username: String
    var reason: String?
    var dateBlocked: Date

    // MARK: - Conversion

    static func from(_ blockedUser: BlockedUser) -> BlockedUserRecord {
        BlockedUserRecord(
            username: blockedUser.username,
            reason: blockedUser.reason,
            dateBlocked: blockedUser.dateBlocked
        )
    }

    func toBlockedUser() -> BlockedUser {
        BlockedUser(
            username: username,
            reason: reason,
            dateBlocked: dateBlocked
        )
    }
}
