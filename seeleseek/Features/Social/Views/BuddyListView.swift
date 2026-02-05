import SwiftUI

struct BuddyListView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: SeeleSpacing.md) {
                // Search field
                StandardSearchField(
                    text: $state.socialState.buddySearchQuery,
                    placeholder: "Search buddies..."
                )

                Spacer()

                // Stats
                if !socialState.buddies.isEmpty {
                    Text("\(socialState.onlineBuddies.count) online / \(socialState.buddies.count) total")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                // Add button
                Button {
                    socialState.showAddBuddySheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: SeeleSpacing.iconSizeSmall, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeeleColors.accent)
            }
            .padding(SeeleSpacing.md)

            Divider().background(SeeleColors.surfaceSecondary)

            // Buddy list
            if socialState.buddies.isEmpty {
                emptyState
            } else {
                buddyList
            }
        }
    }

    private var emptyState: some View {
        StandardEmptyState(
            icon: "person.2.slash",
            title: "No buddies yet",
            subtitle: "Add friends to see when they're online and quickly browse their files.",
            actionTitle: "Add Buddy"
        ) {
            socialState.showAddBuddySheet = true
        }
    }

    private var buddyList: some View {
        List {
            // Online section
            if !socialState.filteredBuddies.filter({ $0.status != .offline }).isEmpty {
                Section("Online") {
                    ForEach(socialState.filteredBuddies.filter { $0.status != .offline }) { buddy in
                        BuddyRowView(buddy: buddy)
                    }
                }
            }

            // Offline section
            if !socialState.filteredBuddies.filter({ $0.status == .offline }).isEmpty {
                Section("Offline") {
                    ForEach(socialState.filteredBuddies.filter { $0.status == .offline }) { buddy in
                        BuddyRowView(buddy: buddy)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(SeeleColors.background)
    }
}

#Preview {
    BuddyListView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.buddies = [
                Buddy(username: "alice", status: .online, averageSpeed: 1_500_000, fileCount: 12000),
                Buddy(username: "bob", status: .away, averageSpeed: 500_000, fileCount: 5000),
                Buddy(username: "charlie", status: .offline, fileCount: 3000),
            ]
            return state
        }())
        .frame(width: 400, height: 400)
}
