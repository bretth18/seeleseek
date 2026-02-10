import Foundation
import GRDB

/// Database record for wishlist entries
struct WishlistRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wishlists"

    var id: String
    var query: String
    var createdAt: Double
    var enabled: Int  // 0 = disabled, 1 = enabled
    var lastSearchedAt: Double?
    var resultCount: Int

    // MARK: - Conversion

    func toWishlistItem() -> WishlistItem {
        WishlistItem(
            id: UUID(uuidString: id) ?? UUID(),
            query: query,
            createdAt: Date(timeIntervalSince1970: createdAt),
            enabled: enabled != 0,
            lastSearchedAt: lastSearchedAt.map { Date(timeIntervalSince1970: $0) },
            resultCount: resultCount
        )
    }

    static func from(_ item: WishlistItem) -> WishlistRecord {
        WishlistRecord(
            id: item.id.uuidString,
            query: item.query,
            createdAt: item.createdAt.timeIntervalSince1970,
            enabled: item.enabled ? 1 : 0,
            lastSearchedAt: item.lastSearchedAt?.timeIntervalSince1970,
            resultCount: item.resultCount
        )
    }
}
