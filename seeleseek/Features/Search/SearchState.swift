import SwiftUI
import os

@Observable
@MainActor
final class SearchState {
    // MARK: - Search Input
    var searchQuery: String = ""

    // MARK: - Tabbed Searches
    /// All active search tabs - results stream in over time
    var searches: [SearchQuery] = []

    /// Currently selected search tab index
    var selectedSearchIndex: Int = 0

    /// The currently selected search (convenience accessor)
    var currentSearch: SearchQuery? {
        get {
            guard selectedSearchIndex >= 0, selectedSearchIndex < searches.count else { return nil }
            return searches[selectedSearchIndex]
        }
        set {
            guard selectedSearchIndex >= 0, selectedSearchIndex < searches.count, let newValue else { return }
            searches[selectedSearchIndex] = newValue
        }
    }

    /// Map of token -> search index for routing incoming results
    private var tokenToSearchIndex: [UInt32: Int] = [:]

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Shared Activity Tracker
    static let activityTracker = SearchActivityState()

    // MARK: - Search History
    var searchHistory: [String] = []

    private let logger = Logger(subsystem: "com.seeleseek", category: "SearchState")

    // MARK: - Setup
    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        logger.info("Setting up callbacks with NetworkClient...")

        client.onSearchResults = { [weak self] token, results in
            self?.logger.info("Received \(results.count) results for token \(token)")
            if let self = self {
                self.addResults(results, forToken: token)
                self.logger.info("Results added to search")
            } else {
                self?.logger.warning("self is nil in callback!")
            }
        }

        logger.info("Callbacks configured with NetworkClient")

        // Load search history
        Task {
            await loadSearchHistory()
        }
    }

    // MARK: - Search History Persistence

    /// Load search history from database
    private func loadSearchHistory() async {
        do {
            searchHistory = try await SearchRepository.fetchHistory(limit: 20)
            logger.info("Loaded \(self.searchHistory.count) search history entries")
        } catch {
            logger.error("Failed to load search history: \(error.localizedDescription)")
        }
    }

    /// Save a completed search to database for caching
    private func persistSearch(_ search: SearchQuery) {
        Task {
            do {
                try await SearchRepository.saveComplete(search)
                logger.debug("Persisted search '\(search.query)' with \(search.results.count) results")
            } catch {
                logger.error("Failed to persist search: \(error.localizedDescription)")
            }
        }
    }

    /// Check for cached search results
    func checkCache(for query: String) async -> SearchQuery? {
        do {
            // Check for cached results (max 1 hour old)
            if let (queryRecord, resultRecords) = try await SearchRepository.findCached(query: query, maxAge: 3600) {
                let results = resultRecords.map { $0.toSearchResult() }
                var cachedQuery = SearchQuery(query: queryRecord.query, token: UInt32(queryRecord.token))
                cachedQuery.results = results
                cachedQuery.isSearching = false
                logger.info("Found cached search for '\(query)' with \(results.count) results")
                return cachedQuery
            }
        } catch {
            logger.error("Failed to check search cache: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Filters
    var filterMinBitrate: Int? = nil
    var filterMinSize: Int64? = nil
    var filterMaxSize: Int64? = nil
    var filterExtensions: Set<String> = []
    var filterFreeSlotOnly: Bool = false
    var sortOrder: SortOrder = .relevance
    var resultGrouping: ResultGrouping = .flat

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case bitrate = "Bitrate"
        case size = "Size"
        case speed = "Speed"
        case queue = "Queue"
    }

    enum ResultGrouping: String, CaseIterable {
        case flat = "Flat"
        case byUser = "By User"
        case byFolder = "By Folder"
        case byAlbum = "By Album"
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
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Results grouped according to the current grouping mode
    var groupedResults: [String: [SearchResult]] {
        let results = filteredResults

        switch resultGrouping {
        case .flat:
            return ["All Results": results]

        case .byUser:
            return Dictionary(grouping: results) { $0.username }

        case .byFolder:
            return Dictionary(grouping: results) { $0.folderPath.isEmpty ? "Root" : $0.folderPath }

        case .byAlbum:
            // Try to detect album from path structure (e.g., "Artist/Album/track.mp3")
            return Dictionary(grouping: results) { result in
                let components = result.folderPath.components(separatedBy: "\\")
                if components.count >= 2 {
                    // Return last two path components as "Artist - Album"
                    let album = components.suffix(2).joined(separator: " - ")
                    return album.isEmpty ? "Unknown Album" : album
                } else if !result.folderPath.isEmpty {
                    return result.folderPath
                } else {
                    return "Unknown Album"
                }
            }
        }
    }

    /// Sorted group keys for display
    var sortedGroupKeys: [String] {
        switch resultGrouping {
        case .flat:
            return ["All Results"]
        case .byUser:
            // Sort by number of results (most first), then alphabetically
            return groupedResults.keys.sorted { key1, key2 in
                let count1 = groupedResults[key1]?.count ?? 0
                let count2 = groupedResults[key2]?.count ?? 0
                if count1 != count2 {
                    return count1 > count2
                }
                return key1.localizedCaseInsensitiveCompare(key2) == .orderedAscending
            }
        case .byFolder, .byAlbum:
            return groupedResults.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    var isSearching: Bool {
        currentSearch?.isSearching ?? false
    }

    // MARK: - Actions

    /// Start a new search - creates a new tab
    func startSearch(token: UInt32) {
        let query = SearchQuery(query: searchQuery, token: token)

        // Add new search tab
        searches.append(query)
        let newIndex = searches.count - 1
        tokenToSearchIndex[token] = newIndex
        selectedSearchIndex = newIndex

        // Record in activity tracker
        SearchState.activityTracker.recordOutgoingSearch(query: searchQuery)

        // Log to activity feed
        ActivityLog.shared.logSearchStarted(query: searchQuery)

        // Update search history
        if !searchHistory.contains(where: { $0.lowercased() == searchQuery.lowercased() }) {
            searchHistory.insert(searchQuery, at: 0)
            if searchHistory.count > 20 {
                searchHistory.removeLast()
            }
        }

        logger.info("Started search '\(self.searchQuery)' with token \(token), tab \(newIndex)")
    }

    /// Start a search from cached results
    func startSearchFromCache(_ cachedQuery: SearchQuery) {
        searches.append(cachedQuery)
        let newIndex = searches.count - 1
        tokenToSearchIndex[cachedQuery.token] = newIndex
        selectedSearchIndex = newIndex

        logger.info("Loaded cached search '\(cachedQuery.query)' with \(cachedQuery.results.count) results")
    }

    /// Add results to a specific search by token
    func addResults(_ results: [SearchResult], forToken token: UInt32) {
        guard let index = tokenToSearchIndex[token], index < searches.count else {
            logger.warning("No search found for token \(token)")
            return
        }

        searches[index].results.append(contentsOf: results)
        logger.info("Added \(results.count) results to '\(self.searches[index].query)' (total: \(self.searches[index].results.count))")

        // Record results count in activity tracker
        SearchState.activityTracker.recordSearchResults(query: searches[index].query, count: results.count)
    }

    /// Mark a search as complete (no longer receiving results)
    func markSearchComplete(token: UInt32) {
        guard let index = tokenToSearchIndex[token], index < searches.count else { return }

        searches[index].isSearching = false

        // Persist the completed search for caching
        persistSearch(searches[index])
    }

    /// Close a search tab
    func closeSearch(at index: Int) {
        guard index >= 0, index < searches.count else { return }

        let search = searches[index]

        // Persist search results before closing if it has results
        if !search.results.isEmpty {
            persistSearch(search)
        }

        tokenToSearchIndex.removeValue(forKey: search.token)
        searches.remove(at: index)

        // Update token mappings for remaining searches
        tokenToSearchIndex.removeAll()
        for (i, s) in searches.enumerated() {
            tokenToSearchIndex[s.token] = i
        }

        // Adjust selected index
        if selectedSearchIndex >= searches.count {
            selectedSearchIndex = max(0, searches.count - 1)
        }
    }

    /// Select a search tab
    func selectSearch(at index: Int) {
        guard index >= 0, index < searches.count else { return }
        selectedSearchIndex = index
    }

    func clearFilters() {
        filterMinBitrate = nil
        filterMinSize = nil
        filterMaxSize = nil
        filterExtensions = []
        filterFreeSlotOnly = false
        sortOrder = .relevance
        resultGrouping = .flat
    }

    /// Clean up expired search cache
    func cleanupExpiredCache() {
        Task {
            do {
                try await SearchRepository.deleteExpired(olderThan: 3600) // 1 hour
                logger.debug("Cleaned up expired search cache")
            } catch {
                logger.error("Failed to cleanup search cache: \(error.localizedDescription)")
            }
        }
    }
}
