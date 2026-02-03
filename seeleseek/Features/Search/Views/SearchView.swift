import SwiftUI

struct SearchView: View {
    @Environment(\.appState) private var appState
    @State private var searchState = SearchState()

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().background(SeeleColors.surfaceSecondary)
            resultsArea
        }
        .background(SeeleColors.background)
        .onAppear {
            searchState.setupCallbacks(client: appState.networkClient)
        }
    }

    private var searchBar: some View {
        HStack(spacing: SeeleSpacing.md) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Search for music...", text: $searchState.searchQuery)
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
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

            Button {
                performSearch()
            } label: {
                Text("Search")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.md)
                    .background(searchState.canSearch ? SeeleColors.accent : SeeleColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!searchState.canSearch)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface.opacity(0.5))
    }

    @ViewBuilder
    private var resultsArea: some View {
        if searchState.isSearching {
            searchingView
        } else if let search = searchState.currentSearch {
            if search.results.isEmpty {
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

            if let search = searchState.currentSearch {
                Text("\(search.results.count) results from \(search.uniqueUsers) users")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No results found")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Try different search terms")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("Search for Music")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Enter an artist, album, or song name above")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)

            if !searchState.searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    Text("Recent Searches")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.top, SeeleSpacing.lg)

                    ForEach(searchState.searchHistory.prefix(5)) { search in
                        Button {
                            searchState.selectHistorySearch(search)
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(SeeleColors.textTertiary)
                                Text(search.query)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                Spacer()
                                Text("\(search.resultCount) results")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                            .padding(.vertical, SeeleSpacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SeeleSpacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsListView: some View {
        VStack(spacing: 0) {
            // Results header
            HStack {
                if let search = searchState.currentSearch {
                    Text("\(searchState.filteredResults.count) results")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textSecondary)

                    if searchState.filteredResults.count != search.results.count {
                        Text("(\(search.results.count) total)")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
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
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(SeeleColors.textSecondary)
                }
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.surface.opacity(0.3))

            // Results list
            ScrollView {
                LazyVStack(spacing: 1) {
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
                // Results will come in via message handler
                // For now, simulate finishing after a delay
                try await Task.sleep(for: .seconds(5))
                searchState.finishSearch()
            } catch {
                searchState.finishSearch()
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
