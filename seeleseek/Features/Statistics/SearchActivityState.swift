import SwiftUI
import SeeleseekCore

@Observable
@MainActor
class SearchActivityState {
    var recentEvents: [SearchEvent] = []
    var incomingSearches: [IncomingSearch] = []
    var isActive: Bool = false

    private var activityTimer: Timer?

    struct SearchEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let query: String
        let direction: Direction
        var resultsCount: Int?

        enum Direction {
            case outgoing
            case incoming
        }
    }

    struct IncomingSearch: Identifiable {
        let id = UUID()
        let timestamp: Date
        let username: String
        let query: String
        let matchCount: Int
    }

    func recordOutgoingSearch(query: String) {
        let event = SearchEvent(
            timestamp: Date(),
            query: query,
            direction: .outgoing
        )
        recentEvents.insert(event, at: 0)

        // Keep last 100 events
        if recentEvents.count > 100 {
            recentEvents.removeLast()
        }

        triggerActivity()
    }

    func recordSearchResults(query: String, count: Int) {
        // Accumulate across batches — results stream in over time, and
        // matching only `resultsCount == nil` froze the display at the
        // first batch's size.
        if let index = recentEvents.firstIndex(where: { $0.query == query && $0.direction == .outgoing }) {
            recentEvents[index].resultsCount = (recentEvents[index].resultsCount ?? 0) + count
        }
    }

    func recordIncomingSearch(username: String, query: String, matchCount: Int) {
        let search = IncomingSearch(
            timestamp: Date(),
            username: username,
            query: query,
            matchCount: matchCount
        )
        incomingSearches.insert(search, at: 0)

        // Keep last 50 incoming searches
        if incomingSearches.count > 50 {
            incomingSearches.removeLast()
        }

        // Also add to events timeline
        let event = SearchEvent(
            timestamp: Date(),
            query: query,
            direction: .incoming,
            resultsCount: matchCount
        )
        recentEvents.insert(event, at: 0)

        triggerActivity()
    }

    private func triggerActivity() {
        isActive = true
        activityTimer?.invalidate()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.isActive = false
            }
        }
    }
}
