import SwiftUI
import Charts

/// Real-time visualization of search activity - both outgoing and incoming
struct SearchActivityView: View {
    @Environment(\.appState) private var appState

    private var searchActivity: SearchActivityState {
        SearchState.activityTracker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            HStack {
                Text("Search Activity")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

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

            SearchTimelineView(events: searchActivity.recentEvents)
                .frame(height: 60)

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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

// MARK: - Search Timeline

struct SearchTimelineView: View {
    let events: [SearchActivityState.SearchEvent]

    private var groupedByMinute: [Date: Int] {
        let calendar = Calendar.current
        var grouped: [Date: Int] = [:]

        let now = Date()
        for i in 0..<30 {
            guard let minute = calendar.date(byAdding: .minute, value: -i, to: now),
                  let truncated = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: minute)) else {
                continue
            }
            grouped[truncated] = 0
        }

        for event in events {
            guard let truncated = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.timestamp)) else {
                continue
            }
            grouped[truncated, default: 0] += 1
        }

        return grouped
    }

    private var maxCount: Int {
        max(groupedByMinute.values.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: SeeleSpacing.xxs) {
                ForEach(groupedByMinute.keys.sorted().suffix(30), id: \.self) { minute in
                    let count = groupedByMinute[minute] ?? 0
                    let height = CGFloat(count) / CGFloat(maxCount) * geometry.size.height

                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusXS, style: .continuous)
                        .fill(count > 0 ? SeeleColors.info : SeeleColors.surfaceSecondary)
                        .frame(width: max((geometry.size.width - 60) / 30, SeeleSpacing.xs), height: max(height, SeeleSpacing.xxs))
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
        case .outgoing: "arrow.up.circle.fill"
        case .incoming: "arrow.down.circle.fill"
        }
    }

    private var color: Color {
        switch event.direction {
        case .outgoing: SeeleColors.info
        case .incoming: SeeleColors.accent
        }
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: SeeleSpacing.iconSizeSmall))

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
            Circle()
                .fill(SeeleColors.surfaceSecondary)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(String(search.username.prefix(1)).uppercased())
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(search.username)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(search.query)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
                Text("\(search.matchCount) matches")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)

                Text(formatTime(search.timestamp))
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
        .padding(.vertical, SeeleSpacing.xs)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SearchActivityView()
        .environment(\.appState, AppState())
        .frame(width: 500, height: 400)
}
