import SwiftUI
import SeeleseekCore

struct SearchView: View {
    @Environment(\.appState) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @State private var highlightedIndex: Int? = nil
    @State private var hoveredIndex: Int? = nil
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTabStripFocused: Bool

    /// What the dropdown row should render as highlighted. Hover wins only when
    /// the mouse is actually over a row; otherwise keyboard-driven highlight.
    private var visibleHighlight: Int? { hoveredIndex ?? highlightedIndex }

    // Use shared searchState from AppState to persist callbacks
    private var searchState: SearchState {
        appState.searchState
    }

    /// History items filtered by current query text
    private var filteredHistory: [String] {
        let query = searchState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return searchState.searchHistory
        }
        return searchState.searchHistory.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            searchBar(binding: $state.searchState.searchQuery)
                .zIndex(10)

            Divider().background(SeeleColors.surfaceSecondary)

            if !searchState.searches.isEmpty {
                searchTabs
            }

            SearchFilterBar(searchState: searchState)

            resultsArea
                .overlay(alignment: .top) {
                    if searchState.showFilters {
                        SearchFilterPanel(searchState: searchState)
                            .transition(reduceMotion ? .opacity : .move(edge: .top))
                    }
                }
                .clipped()
        }
        .onTapGesture {
            isSearchFocused = false
        }
        .background(SeeleColors.background)
        .focusedSceneValue(\.tabCommands, searchTabCommands)
        .onAppear {
            consumePendingSearchFocus()
        }
        .onChange(of: appState.searchFieldFocusPending) { _, pending in
            if pending { consumePendingSearchFocus() }
        }
    }

    private var searchTabCommands: TabCommands? {
        guard !searchState.searches.isEmpty else { return nil }
        let state = searchState
        return TabCommands(
            selectNext: {
                state.selectSearch(at: TabCycler.wrappedNext(state.selectedSearchIndex, count: state.searches.count))
            },
            selectPrevious: {
                state.selectSearch(at: TabCycler.wrappedPrevious(state.selectedSearchIndex, count: state.searches.count))
            },
            closeCurrent: {
                state.closeSearch(at: state.selectedSearchIndex)
            }
        )
    }

    private func consumePendingSearchFocus() {
        guard appState.searchFieldFocusPending else { return }
        appState.searchFieldFocusPending = false
        // A view appearing in this same update cannot take focus until the next runloop.
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func searchBar(binding: Binding<String>) -> some View {
        StandardActionBar {
            ZStack(alignment: .top) {
                StandardSearchField(
                    text: binding,
                    placeholder: "Search or paste a music URL...",
                    isLoading: searchState.isResolvingURL,
                    onSubmit: {
                        if showHistory, let i = visibleHighlight,
                           i >= 0, i < filteredHistory.count {
                            binding.wrappedValue = filteredHistory[i]
                        }
                        showHistory = false
                        highlightedIndex = nil
                        hoveredIndex = nil
                        performSearch()
                    }
                )
                .focused($isSearchFocused)
                .onChange(of: isSearchFocused) { _, focused in
                    showHistory = focused && !filteredHistory.isEmpty
                    if !focused { highlightedIndex = nil }
                }
                .onChange(of: searchState.searchQuery) { _, _ in
                    showHistory = isSearchFocused && !filteredHistory.isEmpty
                    highlightedIndex = nil
                }
                .onKeyPress(.downArrow) {
                    guard showHistory, !filteredHistory.isEmpty else { return .ignored }
                    let last = min(filteredHistory.count, 10) - 1
                    highlightedIndex = min((highlightedIndex ?? -1) + 1, last)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard showHistory, !filteredHistory.isEmpty else { return .ignored }
                    if let i = highlightedIndex {
                        highlightedIndex = i > 0 ? i - 1 : nil
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard showHistory else { return .ignored }
                    showHistory = false
                    highlightedIndex = nil
                    return .handled
                }

                if showHistory && !filteredHistory.isEmpty {
                    searchHistoryDropdown(binding: binding)
                        .offset(y: 40)
                        .zIndex(10)
                }
            }

            PrimaryButton("Search", fullWidth: false) {
                showHistory = false
                performSearch()
            }
            .disabled(!searchState.canSearch)
        }
    }

    private func searchHistoryDropdown(binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredHistory.prefix(10).enumerated()), id: \.element) { index, item in
                Button {
                    binding.wrappedValue = item
                    showHistory = false
                    highlightedIndex = nil
                    isSearchFocused = false
                    performSearch()
                } label: {
                    HStack(spacing: SeeleSpacing.sm) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: SeeleSpacing.iconSizeSmall))
                            .foregroundStyle(SeeleColors.textTertiary)

                        Text(item)
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, SeeleSpacing.md)
                    .padding(.vertical, SeeleSpacing.sm)
                    .contentShape(Rectangle())
                    .background(visibleHighlight == index ? SeeleColors.surfaceSecondary : Color.clear)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hoveredIndex = index
                        NSCursor.pointingHand.push()
                    } else {
                        if hoveredIndex == index { hoveredIndex = nil }
                        NSCursor.pop()
                    }
                }
            }
        }
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                .stroke(SeeleColors.surfaceSecondary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private var searchTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SeeleSpacing.xs) {
                    ForEach(Array(searchState.searches.enumerated()), id: \.element.id) { index, search in
                        searchTab(search: search, index: index)
                            .id(search.id)
                    }
                }
                .padding(.horizontal, SeeleSpacing.lg)
                .padding(.vertical, SeeleSpacing.sm)
            }
            .background(SeeleColors.surface.opacity(0.3))
            .focusable()
            .focused($isTabStripFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: searchState.selectSearch(at: searchState.selectedSearchIndex - 1)
                case .right: searchState.selectSearch(at: searchState.selectedSearchIndex + 1)
                default: break
                }
            }
            .onChange(of: searchState.selectedSearchIndex) { _, index in
                guard searchState.searches.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(searchState.searches[index].id)
                }
            }
        }
    }

    private func searchTab(search: SearchQuery, index: Int) -> some View {
        let isSelected = index == searchState.selectedSearchIndex

        return HStack(spacing: SeeleSpacing.xs) {
            Button {
                searchState.selectSearch(at: index)
            } label: {
                HStack(spacing: SeeleSpacing.xs) {
                    if search.isSearching {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: SeeleSpacing.iconSizeSmall, height: SeeleSpacing.iconSizeSmall)
                    }

                    Text(search.query)
                        .font(SeeleTypography.caption)
                        .lineLimit(1)

                    Text("(\(search.results.count))")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                searchState.closeSearch(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: SeeleSpacing.iconSizeXS - 2, weight: .bold))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            // VoiceOver closes the search through the rotor action on
            // the combined tab element; keyboard users close with ⌘W.
            .accessibilityHidden(true)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(isSelected ? SeeleColors.accent.opacity(0.2) : SeeleColors.surface)
        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD / 2))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD / 2)
                .stroke(isSelected ? SeeleColors.accent : Color.clear, lineWidth: 1)
        )
        .seeleTabFocusRing(isSelected && isTabStripFocused, cornerRadius: SeeleSpacing.radiusMD / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(searchTabAccessibilityLabel(for: search))
        .accessibilityTab(isSelected: isSelected)
        // Combining children strips the inner buttons' AXPress action.
        // Supply the default action explicitly.
        .accessibilityAction {
            searchState.selectSearch(at: index)
        }
        .accessibilityActions {
            Button("Close search") {
                searchState.closeSearch(at: index)
            }
        }
    }

    private func searchTabAccessibilityLabel(for search: SearchQuery) -> String {
        var label = "Search for \(search.query), \(search.results.count) results"
        if search.isSearching {
            label += ", searching"
        }
        return label
    }

    @ViewBuilder
    private var resultsArea: some View {
        if let search = searchState.currentSearch {
            if let error = searchState.currentSearchError, search.results.isEmpty {
                searchErrorView(error)
            } else if search.results.isEmpty && search.isSearching {
                searchingView
            } else if search.results.isEmpty {
                noResultsView
            } else {
                resultsListView
            }
        } else {
            emptyStateView
        }
    }

    /// Distinct state for "the search request itself failed to send" —
    /// previously this silently rendered as "No results found".
    private func searchErrorView(_ message: String) -> some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: SeeleSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(SeeleColors.warning)

            Text("Search failed")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Text(message)
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                retryCurrentSearch()
            }
            .buttonStyle(.seelePrimary)
        }
        .padding(SeeleSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchingView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(SeeleColors.accent)

            Text("Searching...")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Text("Results will appear as peers respond")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        StandardEmptyState(
            icon: "magnifyingglass",
            title: "No results found",
            subtitle: "Try different search terms"
        )
    }

    private var emptyStateView: some View {
        StandardEmptyState(
            icon: "music.note.list",
            title: "Search for Music",
            subtitle: "Enter an artist, album, or song name above"
        )
    }

    private var resultsListView: some View {
        VStack(spacing: 0) {
            Group {
                if let search = searchState.currentSearch {
                    StandardSectionHeader("Results from \(search.uniqueUsers) users", count: searchState.filteredResults.count) {
                        HStack(spacing: SeeleSpacing.sm) {
                            if searchState.filteredResults.count != search.results.count {
                                Text("\(search.results.count) total")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }

                            // Selection mode toggle
                            Button {
                                if searchState.isSelectionMode {
                                    searchState.isSelectionMode = false
                                } else {
                                    searchState.isSelectionMode = true
                                }
                            } label: {
                                HStack(spacing: SeeleSpacing.xxs) {
                                    Image(systemName: searchState.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                                    Text("Select")
                                        .font(SeeleTypography.caption)
                                }
                                .foregroundStyle(searchState.isSelectionMode ? SeeleColors.accent : SeeleColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select results")
                            .accessibilityValue(searchState.isSelectionMode ? "on" : "off")

                            Menu {
                                ForEach(SearchState.SortOrder.allCases, id: \.self) { order in
                                    Button {
                                        searchState.sortOrder = order
                                    } label: {
                                        HStack {
                                            Text(order.rawValue)
                                            if searchState.sortOrder == order {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: SeeleSpacing.xs) {
                                    Text("Sort: \(searchState.sortOrder.rawValue)")
                                        .font(SeeleTypography.caption)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: SeeleSpacing.iconSizeXS))
                                }
                                .foregroundStyle(SeeleColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)

                            if search.isSearching {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                }
            }
            .background(SeeleColors.surface.opacity(0.3))

            // Results list
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        if searchState.isGrouped {
                            ForEach(searchState.displayItems) { item in
                                SearchResultListItemView(item: item)
                            }
                        } else {
                            ForEach(searchState.filteredResults) { result in
                                SearchResultRow(
                                    result: result,
                                    isSelectionMode: searchState.isSelectionMode,
                                    isSelected: searchState.selectedResults.contains(result.id),
                                    onToggleSelection: {
                                        searchState.toggleSelection(result.id)
                                    }
                                )
                            }
                        }
                    }
                    // Add bottom padding when action bar is visible
                    .padding(.bottom, searchState.isSelectionMode ? 60 : 0)
                }

                // Floating action bar
                if searchState.isSelectionMode {
                    selectionActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: SeeleSpacing.md) {
            Button {
                searchState.selectAll()
            } label: {
                Text("Select All")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                searchState.deselectAll()
            } label: {
                Text("Deselect All")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(searchState.selectedResults.count) selected")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            Button("Download Selected (\(searchState.selectedResults.count))") {
                downloadSelected()
            }
            .buttonStyle(.seelePrimary)
            .disabled(searchState.selectedResults.isEmpty)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
        .background(
            SeeleColors.surface
                .shadow(.drop(color: .black.opacity(0.3), radius: 8, y: -2))
        )
    }

    private func downloadSelected() {
        let selectedIDs = searchState.selectedResults
        let results = searchState.filteredResults.filter { selectedIDs.contains($0.id) }

        for result in results {
            if !appState.transferState.isFileQueued(filename: result.filename, username: result.username) {
                appState.downloadManager.queueDownload(from: result)
            }
        }

        searchState.isSelectionMode = false
    }

    private func performSearch() {
        guard searchState.canSearch else { return }

        let query = searchState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if query is a music streaming URL
        if URLResolverClient.detectService(from: query) != nil {
            Task {
                searchState.isResolvingURL = true
                defer { searchState.isResolvingURL = false }

                do {
                    let resolved = try await searchState.urlResolver.resolve(url: query)
                    let searchQuery = URLResolverClient.buildSearchQuery(artist: resolved.artist, title: resolved.title)
                    searchState.searchQuery = searchQuery
                    executeSearch()
                } catch {
                    // Resolution failed — fall through and search with the raw text
                    executeSearch()
                }
            }
            return
        }

        executeSearch()
    }

    private func executeSearch() {
        let token = UInt32.random(in: 1..<0x8000_0000)
        searchState.startSearch(token: token)
        send(query: searchState.searchQuery, token: token)
    }

    /// Re-send the currently-selected (failed) search with a fresh token.
    private func retryCurrentSearch() {
        guard let search = searchState.currentSearch else { return }
        let token = UInt32.random(in: 1..<0x8000_0000)
        searchState.retrySearch(at: searchState.selectedSearchIndex, newToken: token)
        send(query: search.query, token: token)
    }

    private func send(query: String, token: UInt32) {
        Task {
            do {
                try await appState.networkClient.search(query: query, token: token)
            } catch {
                searchState.markSearchFailed(token: token, message: error.localizedDescription)
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
