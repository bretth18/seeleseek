import Foundation
import GRDB

/// Database record for SearchQuery persistence
struct SearchQueryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "search_queries"

    var id: String
    var query: String
    var token: Int64
    var timestamp: Double
    var createdAt: Double

    /// Convert database record to domain model (without results - loaded separately)
    func toSearchQuery(results: [SearchResult] = []) -> SearchQuery {
        SearchQuery(
            id: UUID(uuidString: id) ?? UUID(),
            query: query,
            token: UInt32(token),
            timestamp: Date(timeIntervalSince1970: timestamp),
            results: results,
            isSearching: false // Persisted queries are never actively searching
        )
    }

    /// Create database record from domain model
    static func from(_ searchQuery: SearchQuery) -> SearchQueryRecord {
        SearchQueryRecord(
            id: searchQuery.id.uuidString,
            query: searchQuery.query,
            token: Int64(searchQuery.token),
            timestamp: searchQuery.timestamp.timeIntervalSince1970,
            createdAt: Date().timeIntervalSince1970
        )
    }
}
