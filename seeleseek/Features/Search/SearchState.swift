import SwiftUI
import os
import SeeleseekCore

@Observable
@MainActor
final class SearchState {
    // MARK: - Search Input
    var searchQuery: String = ""

    // MARK: - URL Resolution
    var isResolvingURL: Bool = false
    let urlResolver = URLResolverClient()

    // MARK: - Tabbed Searches
    /// All active search tabs - results stream in over time
    var searches: [SearchQuery] = []

    /// Currently selected search tab index
    var selectedSearchIndex: Int = 0 {
        didSet { if selectedSearchIndex != oldValue { recomputeFilteredResults() } }
    }

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

    // MARK: - Inactivity Timers
    /// SoulSeek has no "search finished" message — without a client-side
    /// inactivity timer any search that stays under `maxSearchResults`
    /// spins forever, and zero-result searches never reach the empty
    /// state. One Task per token, reset on each incoming batch; fires
    /// `markSearchComplete` after `searchInactivityTimeout` of silence.
    @ObservationIgnored private var inactivityTimers: [UInt32: Task<Void, Never>] = [:]
    private static let searchInactivityTimeout: Duration = .seconds(20)

    private func scheduleInactivityTimer(token: UInt32) {
        inactivityTimers[token]?.cancel()
        inactivityTimers[token] = Task { [weak self] in
            try? await Task.sleep(for: Self.searchInactivityTimeout)
            guard let self, !Task.isCancelled else { return }
            self.inactivityTimers.removeValue(forKey: token)
            self.markSearchComplete(token: token)
        }
    }

    private func cancelInactivityTimer(token: UInt32) {
        inactivityTimers[token]?.cancel()
        inactivityTimers.removeValue(forKey: token)
    }

    // MARK: - Send Failures
    /// Error message per search tab (keyed by `SearchQuery.id`), set when
    /// the search request itself failed to send. Rendered by `SearchView`
    /// as a distinct error state (instead of "No results found").
    private(set) var searchErrors: [UUID: String] = [:]

    /// Error message for the currently-selected tab, if any.
    var currentSearchError: String? {
        guard let search = currentSearch else { return nil }
        return searchErrors[search.id]
    }

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Settings Reference
    weak var settings: SettingsState? {
        didSet { syncPersistedSettings() }
    }

    private func syncPersistedSettings() {
        isGrouped = settings?.groupSearchResults ?? false
        applyPersistedFilters(settings?.searchFilters ?? .empty)
    }

    // MARK: - Shared Activity Tracker
    static let activityTracker = SearchActivityState()

    // MARK: - Search History
    var searchHistory: [String] = []

    private let logger = Logger(subsystem: "com.seeleseek", category: "SearchState")

    // MARK: - Setup
    // Results are not subscribed here: `AppState.wireNetworkClient` routes
    // wishlist tokens away and calls `addResults` for the rest.
    func wireNetworkEvents(client: NetworkClient) {
        self.networkClient = client

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

    // MARK: - Selection Mode
    var selectedResults: Set<UUID> = []
    var isSelectionMode: Bool = false {
        didSet {
            if !isSelectionMode { selectedResults.removeAll() }
        }
    }

    func toggleSelection(_ id: UUID) {
        if selectedResults.contains(id) {
            selectedResults.remove(id)
        } else {
            selectedResults.insert(id)
        }
    }

    func selectAll() {
        selectedResults = Set(filteredResults.map(\.id))
    }

    func deselectAll() {
        selectedResults.removeAll()
    }

    // MARK: - Filters
    // Every filter mutator must call `recomputeFilteredResults()` via
    // didSet: `filteredResults` is a stored cache, never computed in body.
    // Filter values also write through to `settings.searchFilters` (see
    // `persistFiltersIfNeeded`); sort order and `showFilters` stay session-only.
    @ObservationIgnored private var suppressFilterPersist = false

    var filterMinBitrate: Int? = nil {
        didSet {
            guard filterMinBitrate != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterMinSampleRate: Int? = nil {
        didSet {
            guard filterMinSampleRate != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterMinBitDepth: Int? = nil {
        didSet {
            guard filterMinBitDepth != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterMinSize: Int64? = nil {
        didSet {
            guard filterMinSize != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterMaxSize: Int64? = nil {
        didSet {
            guard filterMaxSize != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterExtensions: Set<String> = [] {
        didSet {
            guard filterExtensions != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var filterFreeSlotOnly: Bool = false {
        didSet {
            guard filterFreeSlotOnly != oldValue else { return }
            recomputeFilteredResults()
            persistFiltersIfNeeded()
        }
    }
    var sortOrder: SortOrder = .relevance {
        didSet { if sortOrder != oldValue { recomputeFilteredResults() } }
    }
    var showFilters: Bool = false

    private var currentPersistedFilters: PersistedSearchFilters {
        PersistedSearchFilters(
            minBitrate: filterMinBitrate,
            minSampleRate: filterMinSampleRate,
            minBitDepth: filterMinBitDepth,
            minSize: filterMinSize,
            maxSize: filterMaxSize,
            extensions: filterExtensions,
            freeSlotOnly: filterFreeSlotOnly
        )
    }

    private func applyPersistedFilters(_ prefs: PersistedSearchFilters) {
        suppressFilterPersist = true
        defer { suppressFilterPersist = false }
        filterMinBitrate = prefs.minBitrate
        filterMinSampleRate = prefs.minSampleRate
        filterMinBitDepth = prefs.minBitDepth
        filterMinSize = prefs.minSize
        filterMaxSize = prefs.maxSize
        filterExtensions = prefs.extensions
        filterFreeSlotOnly = prefs.freeSlotOnly
    }

    private func persistFiltersIfNeeded() {
        guard !suppressFilterPersist, let settings else { return }
        let prefs = currentPersistedFilters
        guard settings.searchFilters != prefs else { return }
        settings.searchFilters = prefs
    }

    var hasActiveFilters: Bool {
        filterMinBitrate != nil ||
        filterMinSampleRate != nil ||
        filterMinBitDepth != nil ||
        filterMinSize != nil ||
        filterMaxSize != nil ||
        !filterExtensions.isEmpty ||
        filterFreeSlotOnly
    }

    var activeFilterCount: Int {
        var count = 0
        if filterMinBitrate != nil { count += 1 }
        if filterMinSampleRate != nil { count += 1 }
        if filterMinBitDepth != nil { count += 1 }
        if !filterExtensions.isEmpty { count += 1 }
        if filterFreeSlotOnly { count += 1 }
        if filterMinSize != nil { count += 1 }
        if filterMaxSize != nil { count += 1 }
        return count
    }

    enum FilterPreset {
        case mp3_320
        case flac
        case lossless
        case hiRes

        var extensions: Set<String> {
            switch self {
            case .mp3_320: return ["mp3"]
            case .flac: return ["flac"]
            case .lossless: return ["flac", "wav", "aiff", "alac", "ape"]
            case .hiRes: return ["flac", "wav", "aiff", "alac"]
            }
        }

        var minBitrate: Int? {
            switch self {
            case .mp3_320: return 320
            case .flac, .lossless, .hiRes: return nil
            }
        }

        var minSampleRate: Int? {
            switch self {
            case .hiRes: return 96000
            default: return nil
            }
        }

        var minBitDepth: Int? {
            switch self {
            case .hiRes: return 24
            default: return nil
            }
        }
    }

    func applyPreset(_ preset: FilterPreset) {
        if isPresetActive(preset) {
            // Toggle off if already active
            filterExtensions = []
            filterMinBitrate = nil
            filterMinSampleRate = nil
            filterMinBitDepth = nil
        } else {
            filterExtensions = preset.extensions
            filterMinBitrate = preset.minBitrate
            filterMinSampleRate = preset.minSampleRate
            filterMinBitDepth = preset.minBitDepth
        }
    }

    func isPresetActive(_ preset: FilterPreset) -> Bool {
        filterExtensions == preset.extensions &&
        filterMinBitrate == preset.minBitrate &&
        filterMinSampleRate == preset.minSampleRate &&
        filterMinBitDepth == preset.minBitDepth
    }

    func toggleExtension(_ ext: String) {
        if filterExtensions.contains(ext) {
            filterExtensions.remove(ext)
        } else {
            filterExtensions.insert(ext)
        }
    }

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case bitrate = "Bitrate"
        case sampleRate = "Sample Rate"
        case size = "Size"
        case speed = "Speed"
        case queue = "Queue"
    }

    // MARK: - Filtered Results (cached)

    /// Cached filter + sort output for the currently-selected search tab.
    /// Recomputed explicitly (see `recomputeFilteredResults`) whenever any
    /// input changes — new incoming results, filter edits, sort change,
    /// tab switch. The view reads this as a plain stored property, so
    /// unrelated @Observable mutations (peer status, connections, etc.)
    /// never re-run the filter pass.
    private(set) var filteredResults: [SearchResult] = []

    // MARK: - Grouping

    /// Group results by the folder each peer offers them from. Built in the
    /// same pass as `filteredResults` so the two can never disagree about
    /// what is visible. Persisted via `settings.groupSearchResults`, so the
    /// filter-bar toggle and the Settings toggle stay in sync.
    var isGrouped: Bool = false {
        didSet {
            guard isGrouped != oldValue else { return }
            settings?.groupSearchResults = isGrouped
            recomputeFilteredResults()
        }
    }

    private(set) var resultGroups: [SearchResultGroup] = []

    /// The flattened list the view renders: every filtered result as
    /// `.loose` when ungrouped, otherwise derived from `resultGroups` plus
    /// `expandedGroups`. See `SearchListItem` for why the view must not do
    /// this flattening itself.
    private(set) var displayItems: [SearchListItem] = []

    /// Expanded group ids per search token — group ids are `username\folder`,
    /// so a shared set would leak one tab's disclosure into another surfacing
    /// the same peer folder. Pruned in `closeSearch`. Mutate only via
    /// `toggleExpansion`, which rebuilds `displayItems`.
    private var expandedGroupsByToken: [UInt32: Set<String>] = [:]

    private var expandedGroups: Set<String> {
        guard let token = currentSearch?.token else { return [] }
        return expandedGroupsByToken[token] ?? []
    }

    func isExpanded(_ group: SearchResultGroup) -> Bool {
        group.isSingleFile || expandedGroups.contains(group.id)
    }

    func toggleExpansion(_ group: SearchResultGroup) {
        guard !group.isSingleFile, let token = currentSearch?.token else { return }
        if !expandedGroupsByToken[token, default: []].insert(group.id).inserted {
            expandedGroupsByToken[token]?.remove(group.id)
        }
        rebuildDisplayItems()
    }

    private func rebuildDisplayItems() {
        // Capacity is group count, not result count: collapsed is the
        // default, so the common case is one item per group.
        var items: [SearchListItem] = []
        items.reserveCapacity(resultGroups.count)
        let expanded = expandedGroups
        for group in resultGroups {
            if group.isSingleFile, let only = group.results.first {
                items.append(.loose(only))
                continue
            }
            items.append(.header(group))
            guard expanded.contains(group.id) else { continue }
            for result in group.results {
                items.append(.child(result))
            }
            items.append(.groupEnd(groupID: group.id))
        }
        displayItems = items
    }

    // MARK: - Group selection

    func selectionState(of group: SearchResultGroup) -> GroupSelection {
        // Stops as soon as both a selected and an unselected member are seen,
        // rather than scanning the whole group — this runs per header render.
        var sawSelected = false
        var sawUnselected = false
        for result in group.results {
            if selectedResults.contains(result.id) { sawSelected = true } else { sawUnselected = true }
            if sawSelected && sawUnselected { return .partial }
        }
        return sawSelected ? .all : .none
    }

    /// Selecting a partially-selected group completes it rather than
    /// clearing it — the same convention as Finder.
    func toggleSelection(of group: SearchResultGroup) {
        if selectionState(of: group) == .all {
            for result in group.results { selectedResults.remove(result.id) }
        } else {
            for result in group.results { selectedResults.insert(result.id) }
        }
    }

    enum GroupSelection {
        case none, partial, all
    }

    func recomputeFilteredResults() {
        guard let search = currentSearch else {
            filteredResults = []
            resultGroups = []
            displayItems = []
            return
        }

        var results = search.results

        if let minBitrate = filterMinBitrate {
            results = results.filter { ($0.bitrate ?? 0) >= UInt32(minBitrate) }
        }
        if let minSampleRate = filterMinSampleRate {
            results = results.filter { ($0.sampleRate ?? 0) >= UInt32(minSampleRate) }
        }
        if let minBitDepth = filterMinBitDepth {
            results = results.filter { ($0.bitDepth ?? 0) >= UInt32(minBitDepth) }
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

        switch sortOrder {
        case .relevance:
            break // Keep original order
        case .bitrate:
            results.sort { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        case .sampleRate:
            results.sort { ($0.sampleRate ?? 0) > ($1.sampleRate ?? 0) }
        case .size:
            results.sort { $0.size > $1.size }
        case .speed:
            results.sort { $0.uploadSpeed > $1.uploadSpeed }
        case .queue:
            results.sort { $0.queueLength < $1.queueLength }
        }

        filteredResults = results
        if isGrouped {
            resultGroups = Self.group(results)
            rebuildDisplayItems()
        } else {
            resultGroups = []
            displayItems = results.map(SearchListItem.loose)
        }
    }

    /// Groups in encounter order over the already-sorted array, so the
    /// active sort still decides which group leads — "Speed" means the
    /// fastest peer's folder first — without needing a second sort control.
    private static func group(_ results: [SearchResult]) -> [SearchResultGroup] {
        var indexByKey: [String: Int] = [:]
        var buckets: [[SearchResult]] = []

        for result in results {
            let key = SearchResultGroup.key(username: result.username, folderPath: result.folderPath)
            if let index = indexByKey[key] {
                buckets[index].append(result)
            } else {
                indexByKey[key] = buckets.count
                buckets.append([result])
            }
        }

        return buckets.map { bucket in
            SearchResultGroup(
                username: bucket[0].username,
                folderPath: bucket[0].folderPath,
                results: bucket
            )
        }
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

        // Start the completion watchdog
        scheduleInactivityTimer(token: token)

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
        // `selectedSearchIndex.didSet` would normally handle the
        // recompute, but when the first tab is loaded from cache both
        // sides of the assignment are 0 and the guard short-circuits —
        // leaving `filteredResults` empty while `currentSearch.results`
        // is populated. Recompute explicitly so this entry point is
        // safe regardless of caller state.
        recomputeFilteredResults()

        logger.info("Loaded cached search '\(cachedQuery.query)' with \(cachedQuery.results.count) results")
    }

    /// Add results to a specific search by token
    func addResults(_ results: [SearchResult], forToken token: UInt32) {
        guard let index = tokenToSearchIndex[token], index < searches.count else {
            logger.warning("No search found for token \(token)")
            return
        }

        let maxResults = settings?.maxSearchResults ?? 500
        let currentCount = searches[index].results.count + (pendingResults[token]?.count ?? 0)

        // Check if we've already reached the limit
        if maxResults > 0 && currentCount >= maxResults {
            // Already at limit, mark search complete if still searching
            if searches[index].isSearching {
                logger.info("Search '\(self.searches[index].query)' reached limit of \(maxResults) results, stopping")
                searches[index].isSearching = false
                announceSearchComplete(searches[index])
            }
            cancelInactivityTimer(token: token)
            return
        }

        // Fresh activity — push the completion watchdog out again.
        if searches[index].isSearching {
            scheduleInactivityTimer(token: token)
        }

        // Calculate how many results we can add
        var resultsToAdd = results
        if maxResults > 0 {
            let remaining = maxResults - currentCount
            if results.count > remaining {
                resultsToAdd = Array(results.prefix(remaining))
                logger.info("Truncating results from \(results.count) to \(remaining) to stay within limit")
            }
        }

        if oldestPendingArrival == nil { oldestPendingArrival = .now }
        pendingResults[token, default: []].append(contentsOf: resultsToAdd)
        scheduleFlush()
        logger.info("Staged \(resultsToAdd.count) results for '\(self.searches[index].query)' (total: \(currentCount + resultsToAdd.count))")

        // Record results count in activity tracker
        SearchState.activityTracker.recordSearchResults(query: searches[index].query, count: resultsToAdd.count)

        // Check if we've now reached the limit
        if maxResults > 0 && currentCount + resultsToAdd.count >= maxResults {
            logger.info("Search '\(self.searches[index].query)' reached limit of \(maxResults) results, stopping")
            flushPendingResults(force: true)
            searches[index].isSearching = false
            cancelInactivityTimer(token: token)
            announceSearchComplete(searches[index])
        }
    }

    // Every peer reply is its own `addResults` call; appending straight to
    // `searches[i].results` invalidated `SearchView` and every live row per
    // reply (~11k row bodies for one 500-result search). Replies stage here
    // and land once per window.
    @ObservationIgnored private var pendingResults: [UInt32: [SearchResult]] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    private static let flushInterval: Duration = .milliseconds(250)

    /// Landing a batch mid-scroll drops frames (the only drops seen in the
    /// auto-scroll harness coincided with flushes), so a flush that finds
    /// the list moved within `scrollQuietWindow` re-arms instead, up to
    /// `maxFlushDeferral`.
    @ObservationIgnored private var lastScrollActivity: ContinuousClock.Instant?
    @ObservationIgnored private var oldestPendingArrival: ContinuousClock.Instant?
    private static let scrollQuietWindow: Duration = .milliseconds(200)
    /// 4s, not 2s: on a real search a 2s ceiling force-landed a list
    /// restructure mid-scroll every 2s (33–69 ticks >33ms per 5s); 4s gives
    /// 0–5, indistinguishable from 8s.
    private static let maxFlushDeferral: Duration = .seconds(4)

    /// True while the results list is in motion; false ~150ms after it
    /// settles. Fed into `\.rowHoverSuppressed`, which nested hosting
    /// views inherit: rows sliding under a parked cursor otherwise fire
    /// hover enter/exit per row, each re-rendering that cell. Measured
    /// under trackpad-style flicks at 120Hz: ~9 drops per 5s with this,
    /// ~80 without. Flips are edge-triggered and deferred one turn so the
    /// per-frame scroll callback never writes observable state.
    private(set) var isListScrolling = false
    @ObservationIgnored private var scrollSettleTask: Task<Void, Never>?
    private static let hoverResumeQuiet: Duration = .milliseconds(150)

    func noteResultsScrollActivity() {
        lastScrollActivity = .now
        guard scrollSettleTask == nil else { return }
        scrollSettleTask = Task { [weak self] in
            guard let self else { return }
            self.isListScrolling = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                if let last = self.lastScrollActivity,
                   ContinuousClock.now - last > Self.hoverResumeQuiet {
                    break
                }
            }
            self.isListScrolling = false
            self.scrollSettleTask = nil
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard !Task.isCancelled, let self else { return }
            self.flushPendingResults()
        }
    }

    /// `force` skips the mid-scroll deferral; completion and tab-close paths
    /// must land immediately.
    private func flushPendingResults(force: Bool = false) {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingResults.isEmpty else { return }

        if !force,
           let lastScroll = lastScrollActivity,
           ContinuousClock.now - lastScroll < Self.scrollQuietWindow,
           let oldest = oldestPendingArrival,
           ContinuousClock.now - oldest < Self.maxFlushDeferral {
            scheduleFlush()
            return
        }
        oldestPendingArrival = nil

        var touchedSelected = false
        for (token, results) in pendingResults {
            guard let index = tokenToSearchIndex[token], index < searches.count else { continue }
            searches[index].results.append(contentsOf: results)
            if index == selectedSearchIndex { touchedSelected = true }
        }
        pendingResults.removeAll(keepingCapacity: true)
        if touchedSelected { recomputeFilteredResults() }
    }

    /// Mark a search as complete (no longer receiving results)
    func markSearchComplete(token: UInt32) {
        cancelInactivityTimer(token: token)
        guard let index = tokenToSearchIndex[token], index < searches.count else { return }

        flushPendingResults(force: true)

        let wasSearching = searches[index].isSearching
        searches[index].isSearching = false
        if wasSearching {
            announceSearchComplete(searches[index])
        }

        // Persist the completed search for caching
        persistSearch(searches[index])
    }

    /// A VoiceOver user cannot see the spinner stop or the result
    /// counter change. Speak the result one time when the search
    /// completes.
    private func announceSearchComplete(_ search: SearchQuery) {
        let count = search.results.count
        let results = count == 1 ? "1 result" : "\(count) results"
        VoiceOverAnnouncer.shared.announce("Search complete: \(results) for \(search.query)")
    }

    /// Mark a search as failed to send. The tab stops spinning and
    /// `SearchView` renders a distinct error state with a Retry button.
    func markSearchFailed(token: UInt32, message: String) {
        cancelInactivityTimer(token: token)
        guard let index = tokenToSearchIndex[token], index < searches.count else { return }

        searches[index].isSearching = false
        searchErrors[searches[index].id] = message
        logger.error("Search '\(self.searches[index].query)' failed to send: \(message)")
    }

    /// Reset a failed tab in place for a fresh attempt with `newToken`.
    /// The caller is responsible for actually re-sending the request.
    func retrySearch(at index: Int, newToken: UInt32) {
        guard index >= 0, index < searches.count else { return }

        let old = searches[index]
        cancelInactivityTimer(token: old.token)
        tokenToSearchIndex.removeValue(forKey: old.token)
        searchErrors.removeValue(forKey: old.id)

        searches[index] = SearchQuery(query: old.query, token: newToken)
        tokenToSearchIndex[newToken] = index
        scheduleInactivityTimer(token: newToken)
        if index == selectedSearchIndex {
            recomputeFilteredResults()
        }
        logger.info("Retrying search '\(old.query)' with token \(newToken)")
    }

    /// Close a search tab
    func closeSearch(at index: Int) {
        guard index >= 0, index < searches.count else { return }

        // Before indices shift below, or a later flush lands in the wrong tab.
        flushPendingResults(force: true)
        let search = searches[index]

        // Persist search results before closing if it has results
        if !search.results.isEmpty {
            persistSearch(search)
        }

        cancelInactivityTimer(token: search.token)
        searchErrors.removeValue(forKey: search.id)
        tokenToSearchIndex.removeValue(forKey: search.token)
        expandedGroupsByToken.removeValue(forKey: search.token)
        searches.remove(at: index)

        // Update token mappings for remaining searches
        tokenToSearchIndex.removeAll()
        for (i, s) in searches.enumerated() {
            tokenToSearchIndex[s.token] = i
        }

        // Adjust selected index
        if selectedSearchIndex >= searches.count {
            selectedSearchIndex = max(0, searches.count - 1)
        } else {
            // Same index, possibly different underlying search (lower tab
            // was closed, shifting the selection). Re-snap filter cache.
            recomputeFilteredResults()
        }
    }

    /// Select a search tab
    func selectSearch(at index: Int) {
        guard index >= 0, index < searches.count else { return }
        selectedSearchIndex = index
    }

    func clearFilters() {
        filterMinBitrate = nil
        filterMinSampleRate = nil
        filterMinBitDepth = nil
        filterMinSize = nil
        filterMaxSize = nil
        filterExtensions = []
        filterFreeSlotOnly = false
        sortOrder = .relevance
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
