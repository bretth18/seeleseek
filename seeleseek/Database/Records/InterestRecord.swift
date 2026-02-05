import Foundation
import GRDB

/// Type of interest (like or hate)
enum InterestType: String, Codable, Sendable {
    case like
    case hate
}

/// Database record for user interests
struct InterestRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "my_interests"

    var item: String
    var type: String  // "like" or "hate"
    var addedAt: Double

    // MARK: - Conversion

    var interestType: InterestType {
        InterestType(rawValue: type) ?? .like
    }

    static func from(item: String, type: InterestType) -> InterestRecord {
        InterestRecord(
            item: item,
            type: type.rawValue,
            addedAt: Date().timeIntervalSince1970
        )
    }
}

/// Database record for profile settings
struct ProfileSettingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "my_profile"

    var key: String
    var value: String

    static func from(key: String, value: String) -> ProfileSettingRecord {
        ProfileSettingRecord(key: key, value: value)
    }
}
