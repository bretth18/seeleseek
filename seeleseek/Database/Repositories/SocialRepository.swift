import Foundation
import GRDB

/// Repository for Social feature database operations
struct SocialRepository {
    // MARK: - Buddies

    /// Fetch all buddies from database
    static func fetchBuddies() async throws -> [Buddy] {
        try await DatabaseManager.shared.read { db in
            let records = try BuddyRecord
                .order(Column("username").asc)
                .fetchAll(db)
            return records.map { $0.toBuddy() }
        }
    }

    /// Save or update a buddy
    static func saveBuddy(_ buddy: Buddy) async throws {
        try await DatabaseManager.shared.write { db in
            var record = BuddyRecord.from(buddy)
            try record.save(db)
        }
    }

    /// Delete a buddy by username
    static func deleteBuddy(_ username: String) async throws {
        try await DatabaseManager.shared.write { db in
            try BuddyRecord
                .filter(Column("username") == username)
                .deleteAll(db)
        }
    }

    // MARK: - Interests

    /// Fetch all interests (likes and hates)
    static func fetchInterests() async throws -> (likes: [String], hates: [String]) {
        try await DatabaseManager.shared.read { db in
            let records = try InterestRecord
                .order(Column("addedAt").asc)
                .fetchAll(db)

            var likes: [String] = []
            var hates: [String] = []

            for record in records {
                if record.interestType == .like {
                    likes.append(record.item)
                } else {
                    hates.append(record.item)
                }
            }

            return (likes, hates)
        }
    }

    /// Save an interest
    static func saveInterest(_ item: String, type: InterestType) async throws {
        try await DatabaseManager.shared.write { db in
            var record = InterestRecord.from(item: item, type: type)
            try record.save(db)
        }
    }

    /// Delete an interest by item name
    static func deleteInterest(_ item: String) async throws {
        try await DatabaseManager.shared.write { db in
            try InterestRecord
                .filter(Column("item") == item)
                .deleteAll(db)
        }
    }

    /// Delete all interests of a specific type
    static func deleteAllInterests(type: InterestType) async throws {
        try await DatabaseManager.shared.write { db in
            try InterestRecord
                .filter(Column("type") == type.rawValue)
                .deleteAll(db)
        }
    }

    // MARK: - Profile Settings

    /// Get a profile setting value
    static func getProfileSetting(_ key: String) async throws -> String? {
        try await DatabaseManager.shared.read { db in
            let record = try ProfileSettingRecord
                .filter(Column("key") == key)
                .fetchOne(db)
            return record?.value
        }
    }

    /// Set a profile setting value
    static func setProfileSetting(_ key: String, value: String) async throws {
        try await DatabaseManager.shared.write { db in
            var record = ProfileSettingRecord.from(key: key, value: value)
            try record.save(db)
        }
    }

    /// Delete a profile setting
    static func deleteProfileSetting(_ key: String) async throws {
        try await DatabaseManager.shared.write { db in
            try ProfileSettingRecord
                .filter(Column("key") == key)
                .deleteAll(db)
        }
    }

    // MARK: - Blocked Users

    /// Fetch all blocked users
    static func fetchBlockedUsers() async throws -> [BlockedUser] {
        try await DatabaseManager.shared.read { db in
            let records = try BlockedUserRecord
                .order(Column("dateBlocked").desc)
                .fetchAll(db)
            return records.map { $0.toBlockedUser() }
        }
    }

    /// Save a blocked user
    static func saveBlockedUser(_ blockedUser: BlockedUser) async throws {
        try await DatabaseManager.shared.write { db in
            var record = BlockedUserRecord.from(blockedUser)
            try record.save(db)
        }
    }

    /// Delete a blocked user by username
    static func deleteBlockedUser(_ username: String) async throws {
        try await DatabaseManager.shared.write { db in
            try BlockedUserRecord
                .filter(Column("username") == username)
                .deleteAll(db)
        }
    }

    /// Check if a user is blocked
    static func isUserBlocked(_ username: String) async throws -> Bool {
        try await DatabaseManager.shared.read { db in
            try BlockedUserRecord
                .filter(Column("username").lowercased == username.lowercased())
                .fetchCount(db) > 0
        }
    }
}
