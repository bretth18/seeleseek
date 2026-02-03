import SwiftUI

@Observable
@MainActor
final class SearchState {
    // MARK: - Search Input
    var searchQuery: String = ""
    var isSearching: Bool = false

    // MARK: - Results
    var currentSearch: SearchQuery?
    var searchHistory: [SearchQuery] = []

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Setup
    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        client.onSearchResults = { [weak self] results in
            // Note: In SoulSeek, search results come from peers, not the server
            // This callback would be triggered when peer connections deliver results
            self?.addResults(results)
        }
    }

    // MARK: - Filters
    var filterMinBitrate: Int? = nil
    var filterMinSize: Int64? = nil
    var filterMaxSize: Int64? = nil
    var filterExtensions: Set<String> = []
    var filterFreeSlotOnly: Bool = false
    var sortOrder: SortOrder = .relevance

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case bitrate = "Bitrate"
        case size = "Size"
        case speed = "Speed"
        case queue = "Queue"
    }

    // MARK: - Computed Properties
    var filteredResults: [SearchResult] {
        guard let search = currentSearch else { return [] }

        var results = search.results

        // Apply filters
        if let minBitrate = filterMinBitrate {
            results = results.filter { ($0.bitrate ?? 0) >= UInt32(minBitrate) }
        }

        if let minSize = filterMinSize {
            results = results.filter { $0.size >= UInt64(minSize) }
        }

        if let maxSize = filterMaxSize {
            results = results.filter { $0.size <= UInt64(maxSize) }
        }

        if !filterExtensions.isEmpty {
            results = results.filter { filterExtensions.contains($0.fileExtension) }
        }

        if filterFreeSlotOnly {
            results = results.filter { $0.freeSlots }
        }

        // Apply sorting
        switch sortOrder {
        case .relevance:
            break // Keep original order
        case .bitrate:
            results.sort { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        case .size:
            results.sort { $0.size > $1.size }
        case .speed:
            results.sort { $0.uploadSpeed > $1.uploadSpeed }
        case .queue:
            results.sort { $0.queueLength < $1.queueLength }
        }

        return results
    }

    var canSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching
    }

    // MARK: - Actions
    func startSearch(token: UInt32) {
        let query = SearchQuery(query: searchQuery, token: token)
        currentSearch = query
        isSearching = true
    }

    func addResult(_ result: SearchResult) {
        currentSearch?.results.append(result)
    }

    func addResults(_ results: [SearchResult]) {
        currentSearch?.results.append(contentsOf: results)
    }

    func finishSearch() {
        isSearching = false
        currentSearch?.isSearching = false

        if let search = currentSearch, !search.results.isEmpty {
            // Add to history, keeping last 10 searches
            searchHistory.insert(search, at: 0)
            if searchHistory.count > 10 {
                searchHistory.removeLast()
            }
        }
    }

    func clearResults() {
        currentSearch = nil
    }

    func clearFilters() {
        filterMinBitrate = nil
        filterMinSize = nil
        filterMaxSize = nil
        filterExtensions = []
        filterFreeSlotOnly = false
        sortOrder = .relevance
    }

    func selectHistorySearch(_ search: SearchQuery) {
        currentSearch = search
        searchQuery = search.query
        isSearching = false
    }
}
