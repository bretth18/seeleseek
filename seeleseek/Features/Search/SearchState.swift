import SwiftUI

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

    // MARK: - Setup
    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        print("🔧 SearchState: Setting up callbacks with NetworkClient...")

        client.onSearchResults = { [weak self] token, results in
            print("🔔 SearchState: Received \(results.count) results for token \(token)")
            if let self = self {
                self.addResults(results, forToken: token)
                print("✅ SearchState: Results added to search")
            } else {
                print("⚠️ SearchState: self is nil in callback!")
            }
        }

        print("✅ SearchState: Callbacks configured with NetworkClient")
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
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
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

        print("SearchState: Started search '\(searchQuery)' with token \(token), tab \(newIndex)")
    }

    /// Add results to a specific search by token
    func addResults(_ results: [SearchResult], forToken token: UInt32) {
        guard let index = tokenToSearchIndex[token], index < searches.count else {
            print("SearchState: No search found for token \(token)")
            return
        }

        searches[index].results.append(contentsOf: results)
        print("SearchState: Added \(results.count) results to '\(searches[index].query)' (total: \(searches[index].results.count))")

        // Record results count in activity tracker
        SearchState.activityTracker.recordSearchResults(query: searches[index].query, count: results.count)
    }

    /// Close a search tab
    func closeSearch(at index: Int) {
        guard index >= 0, index < searches.count else { return }

        let search = searches[index]
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
    }
}
