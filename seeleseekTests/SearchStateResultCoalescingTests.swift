import Testing
import Foundation
@testable import seeleseek
@testable import SeeleseekCore

/// Each peer reply is its own `addResults` call; the visible list must not
/// rebuild per reply (one `LazyVStack` layout pass each) but per window.
@Suite("SearchState result coalescing")
@MainActor
struct SearchStateResultCoalescingTests {

    private func makeState() -> SearchState {
        let state = SearchState()
        state.searchQuery = "q"
        state.startSearch(token: 7)
        return state
    }

    private func result(_ name: String) -> SearchResult {
        SearchResult(username: "u", filename: "f\\\(name)", size: 1)
    }

    @Test("Rapid batches stay staged, then land together after the window")
    func coalesces() async throws {
        let state = makeState()
        state.addResults([result("a.flac")], forToken: 7)
        state.addResults([result("b.flac")], forToken: 7)
        #expect(state.searches[0].results.isEmpty)
        #expect(state.filteredResults.isEmpty)

        try await Task.sleep(for: .milliseconds(400))
        #expect(state.searches[0].results.count == 2)
        #expect(state.filteredResults.count == 2)
    }

    @Test("Completion lands the staged batch immediately")
    func completionFlushes() {
        let state = makeState()
        state.addResults([result("a.flac")], forToken: 7)
        #expect(state.filteredResults.isEmpty)

        state.markSearchComplete(token: 7)
        #expect(state.searches[0].results.count == 1)
        #expect(state.filteredResults.count == 1)
    }

    @Test("Result limit counts staged replies and flushes on hitting it")
    func limitCountsStaged() {
        let state = makeState()
        let limit = state.settings?.maxSearchResults ?? 500
        let batch = (0..<limit).map { result("\($0).flac") }
        state.addResults(batch, forToken: 7)
        #expect(state.searches[0].results.count == limit)
        #expect(!state.searches[0].isSearching)

        state.addResults([result("extra.flac")], forToken: 7)
        state.markSearchComplete(token: 7)
        #expect(state.searches[0].results.count == limit)
    }
}
