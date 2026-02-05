import Foundation
import GRDB

/// Database record for buddy list entries
struct BuddyRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "buddies"

    var username: String
    var notes: String?
    var dateAdded: Double
    var lastSeen: Double?

    // MARK: - Conversion

    func toBuddy() -> Buddy {
        Buddy(
            username: username,
            status: .offline,  // Will be updated from network
            notes: notes,
            dateAdded: Date(timeIntervalSince1970: dateAdded),
            lastSeen: lastSeen.map { Date(timeIntervalSince1970: $0) }
        )
    }

    static func from(_ buddy: Buddy) -> BuddyRecord {
        BuddyRecord(
            username: buddy.username,
            notes: buddy.notes,
            dateAdded: buddy.dateAdded.timeIntervalSince1970,
            lastSeen: buddy.lastSeen?.timeIntervalSince1970
        )
    }
}
