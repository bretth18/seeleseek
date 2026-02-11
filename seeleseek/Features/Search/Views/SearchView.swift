import SwiftUI

struct SearchView: View {
    @Environment(\.appState) private var appState

    // Use shared searchState from AppState to persist callbacks
    private var searchState: SearchState {
        appState.searchState
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            searchBar(binding: $state.searchState.searchQuery)

            // Search tabs
            if !searchState.searches.isEmpty {
                searchTabs
            }

            SearchFilterBar(searchState: searchState)

            Divider().background(SeeleColors.surfaceSecondary)

            // ZStack so filter panel overlays results instead of pushing layout
            ZStack(alignment: .top) {
                resultsArea

                if searchState.showFilters {
                    SearchFilterPanel(searchState: searchState)
                        .zIndex(1)
                }
            }
        }
        .background(SeeleColors.background)
    }

    private func searchBar(binding: Binding<String>) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Search for music...", text: binding)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .onSubmit {
                        performSearch()
                    }

                if !searchState.searchQuery.isEmpty {
                    Button {
                        searchState.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))

            Button {
                performSearch()
            } label: {
                Text("Search")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textOnAccent)
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.md)
                    .background(searchState.canSearch ? SeeleColors.accent : SeeleColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!searchState.canSearch)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface.opacity(0.5))
    }

    private var searchTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SeeleSpacing.xs) {
                ForEach(Array(searchState.searches.enumerated()), id: \.element.id) { index, search in
                    searchTab(search: search, index: index)
                }
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.sm)
        }
        .background(SeeleColors.surface.opacity(0.3))
    }

    private func searchTab(search: SearchQuery, index: Int) -> some View {
        let isSelected = index == searchState.selectedSearchIndex

        return HStack(spacing: SeeleSpacing.xs) {
            // Activity indicator if still searching
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

            // Close button
            Button {
                searchState.closeSearch(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: SeeleSpacing.iconSizeXS - 2, weight: .bold))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
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
        .onTapGesture {
            searchState.selectSearch(at: index)
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if let search = searchState.currentSearch {
            if search.results.isEmpty && search.isSearching {
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
            // Results header
            HStack {
                if let search = searchState.currentSearch {
                    HStack(spacing: SeeleSpacing.sm) {
                        Text("\(searchState.filteredResults.count) results")
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.textSecondary)

                        if searchState.filteredResults.count != search.results.count {
                            Text("(\(search.results.count) total)")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }

                        Text("from \(search.uniqueUsers) users")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        if search.isSearching {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }

                Spacer()

                // Sort picker
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
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.surface.opacity(0.3))

            // Results list
            ScrollView {
                LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                    ForEach(searchState.filteredResults) { result in
                        SearchResultRow(result: result)
                    }
                }
            }
        }
    }

    private func performSearch() {
        guard searchState.canSearch else { return }

        let token = UInt32.random(in: 1...UInt32.max)
        searchState.startSearch(token: token)

        Task {
            do {
                try await appState.networkClient.search(query: searchState.searchQuery, token: token)
                // Results stream in from peers - no "finish" needed
                // The search tab stays open until user closes it
            } catch {
                print("Search error: \(error)")
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
