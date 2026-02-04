import SwiftUI
import Charts

/// Real-time visualization of search activity - both outgoing and incoming
struct SearchActivityView: View {
    @Environment(\.appState) private var appState

    // Use shared activity tracker from SearchState
    private var searchActivity: SearchActivityState {
        SearchState.activityTracker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            // Header
            HStack {
                Text("Search Activity")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                // Live indicator
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(SeeleColors.info)
                        .frame(width: 6, height: 6)
                        .opacity(searchActivity.isActive ? 1 : 0.3)
                    Text("Live")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            // Activity timeline
            SearchTimelineView(events: searchActivity.recentEvents)
                .frame(height: 60)

            // Recent searches list
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Recent Queries")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)

                if searchActivity.recentEvents.isEmpty {
                    Text("No search activity yet")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.vertical, SeeleSpacing.md)
                } else {
                    ForEach(searchActivity.recentEvents.prefix(10)) { event in
                        SearchEventRow(event: event)
                    }
                }
            }

            // Incoming search requests (people searching our shares)
            if !searchActivity.incomingSearches.isEmpty {
                Divider()
                    .background(SeeleColors.surfaceSecondary)

                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    HStack {
                        Text("Incoming Search Requests")
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.textSecondary)

                        Spacer()

                        Text("\(searchActivity.incomingSearches.count) total")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }

                    ForEach(searchActivity.incomingSearches.prefix(5)) { search in
                        IncomingSearchRow(search: search)
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

// MARK: - Search Timeline

struct SearchTimelineView: View {
    let events: [SearchActivityState.SearchEvent]

    private var groupedByMinute: [Date: Int] {
        let calendar = Calendar.current
        var grouped: [Date: Int] = [:]

        // Create buckets for last 30 minutes
        let now = Date()
        for i in 0..<30 {
            let minute = calendar.date(byAdding: .minute, value: -i, to: now)!
            let truncated = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: minute))!
            grouped[truncated] = 0
        }

        // Count events
        for event in events {
            let truncated = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp))!
            grouped[truncated, default: 0] += 1
        }

        return grouped
    }

    private var maxCount: Int {
        max(groupedByMinute.values.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(groupedByMinute.keys.sorted().suffix(30), id: \.self) { minute in
                    let count = groupedByMinute[minute] ?? 0
                    let height = CGFloat(count) / CGFloat(maxCount) * geometry.size.height

                    RoundedRectangle(cornerRadius: 2)
                        .fill(count > 0 ? SeeleColors.info : SeeleColors.surfaceSecondary)
                        .frame(width: max((geometry.size.width - 60) / 30, 4), height: max(height, 2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Search Event Row

struct SearchEventRow: View {
    let event: SearchActivityState.SearchEvent

    private var icon: String {
        switch event.direction {
        case .outgoing:
            return "arrow.up.circle.fill"
        case .incoming:
            return "arrow.down.circle.fill"
        }
    }

    private var color: Color {
        switch event.direction {
        case .outgoing:
            return SeeleColors.info
        case .incoming:
            return SeeleColors.accent
        }
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))

            Text(event.query)
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)

            Spacer()

            if let resultsCount = event.resultsCount {
                Text("\(resultsCount) results")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Text(formatTime(event.timestamp))
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Incoming Search Row

struct IncomingSearchRow: View {
    let search: SearchActivityState.IncomingSearch

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            // User avatar placeholder
            Circle()
                .fill(SeeleColors.surfaceSecondary)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(String(search.username.prefix(1)).uppercased())
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(search.username)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(search.query)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(search.matchCount) matches")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)

                Text(formatTime(search.timestamp))
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Search Activity State

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

    func startMonitoring(client: NetworkClient) {
        // Monitor outgoing searches from SearchState if available
        // This would be wired up from the SearchView
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
        if let index = recentEvents.firstIndex(where: { $0.query == query && $0.resultsCount == nil }) {
            recentEvents[index].resultsCount = count
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

#Preview {
    SearchActivityView()
        .environment(\.appState, AppState())
        .frame(width: 500, height: 400)
}
