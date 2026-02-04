import Foundation
import GRDB

/// Repository for Search database operations
struct SearchRepository {
    /// Fetch recent search queries with their results
    static func fetchRecent(limit: Int = 10) async throws -> [(SearchQueryRecord, [SearchResultRecord])] {
        try await DatabaseManager.shared.read { db in
            let queries = try SearchQueryRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)

            var result: [(SearchQueryRecord, [SearchResultRecord])] = []
            for query in queries {
                let results = try SearchResultRecord
                    .filter(Column("queryId") == query.id)
                    .fetchAll(db)
                result.append((query, results))
            }
            return result
        }
    }

    /// Fetch a specific search query by ID
    static func fetch(id: UUID) async throws -> (SearchQueryRecord, [SearchResultRecord])? {
        try await DatabaseManager.shared.read { db in
            guard let query = try SearchQueryRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db) else {
                return nil
            }

            let results = try SearchResultRecord
                .filter(Column("queryId") == query.id)
                .fetchAll(db)

            return (query, results)
        }
    }

    /// Check if a cached search exists for a query string
    static func findCached(query: String, maxAge: TimeInterval) async throws -> (SearchQueryRecord, [SearchResultRecord])? {
        let minTimestamp = Date().timeIntervalSince1970 - maxAge

        return try await DatabaseManager.shared.read { db in
            guard let queryRecord = try SearchQueryRecord
                .filter(Column("query") == query && Column("createdAt") >= minTimestamp)
                .order(Column("createdAt").desc)
                .fetchOne(db) else {
                return nil
            }

            let results = try SearchResultRecord
                .filter(Column("queryId") == queryRecord.id)
                .fetchAll(db)

            return (queryRecord, results)
        }
    }

    /// Save a search query
    static func save(_ query: SearchQuery) async throws {
        try await DatabaseManager.shared.write { db in
            var record = SearchQueryRecord.from(query)
            try record.insert(db)
        }
    }

    /// Add results to an existing search query
    static func addResults(_ results: [SearchResult], toQueryId queryId: UUID) async throws {
        guard !results.isEmpty else { return }

        try await DatabaseManager.shared.write { db in
            for result in results {
                var record = SearchResultRecord.from(result, queryId: queryId)
                try record.insert(db)
            }
        }
    }

    /// Save a complete search (query + results)
    static func saveComplete(_ query: SearchQuery) async throws {
        try await DatabaseManager.shared.write { db in
            // Save query
            var queryRecord = SearchQueryRecord.from(query)
            try queryRecord.insert(db)

            // Save results
            for result in query.results {
                var resultRecord = SearchResultRecord.from(result, queryId: query.id)
                try resultRecord.insert(db)
            }
        }
    }

    /// Delete a search query (cascades to results)
    static func delete(id: UUID) async throws {
        try await DatabaseManager.shared.write { db in
            try SearchQueryRecord.filter(Column("id") == id.uuidString).deleteAll(db)
        }
    }

    /// Delete expired search queries
    static func deleteExpired(olderThan age: TimeInterval) async throws {
        let cutoff = Date().timeIntervalSince1970 - age

        try await DatabaseManager.shared.write { db in
            try SearchQueryRecord.filter(Column("createdAt") < cutoff).deleteAll(db)
        }
    }

    /// Get search history (query strings only, for autocomplete)
    static func fetchHistory(limit: Int = 20) async throws -> [String] {
        try await DatabaseManager.shared.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT query FROM search_queries
                ORDER BY timestamp DESC
                LIMIT ?
                """, arguments: [limit])
            return rows.map { $0["query"] as String }
        }
    }
}
