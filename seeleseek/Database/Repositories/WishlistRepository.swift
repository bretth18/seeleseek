import Foundation
import GRDB

/// Repository for Wishlist database operations
struct WishlistRepository {
    /// Fetch all wishlists ordered by creation date
    static func fetchAll() async throws -> [WishlistItem] {
        try await DatabaseManager.shared.read { db in
            let records = try WishlistRecord
                .order(Column("createdAt").asc)
                .fetchAll(db)
            return records.map { $0.toWishlistItem() }
        }
    }

    /// Save or update a wishlist item
    static func save(_ item: WishlistItem) async throws {
        try await DatabaseManager.shared.write { db in
            var record = WishlistRecord.from(item)
            try record.save(db)
        }
    }

    /// Delete a wishlist item by ID
    static func delete(id: UUID) async throws {
        _ = try await DatabaseManager.shared.write { db in
            try WishlistRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Update last searched time and result count
    static func updateLastSearched(id: UUID, resultCount: Int) async throws {
        try await DatabaseManager.shared.write { db in
            try db.execute(
                sql: "UPDATE wishlists SET lastSearchedAt = ?, resultCount = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, resultCount, id.uuidString]
            )
        }
    }
}
