import Foundation

public struct SearchQuery: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let token: UInt32
    public let timestamp: Date
    public var results: [SearchResult]
    public var isSearching: Bool

    /// Convenience init for new searches
    public nonisolated init(query: String, token: UInt32) {
        self.id = UUID()
        self.query = query
        self.token = token
        self.timestamp = Date()
        self.results = []
        self.isSearching = true
    }

    /// Full memberwise init for database restoration
    public nonisolated init(
        id: UUID,
        query: String,
        token: UInt32,
        timestamp: Date,
        results: [SearchResult],
        isSearching: Bool
    ) {
        self.id = id
        self.query = query
        self.token = token
        self.timestamp = timestamp
        self.results = results
        self.isSearching = isSearching
    }

    public var resultCount: Int {
        results.count
    }

    public var uniqueUsers: Int {
        Set(results.map(\.username)).count
    }
}
