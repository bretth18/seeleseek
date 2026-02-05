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
                HStack(spacing: SeeleSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SeeleColors.textTertiary)
                    TextField("Search buddies...", text: $state.socialState.buddySearchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(SeeleSpacing.sm)
                .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

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
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "person.2.slash")
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No buddies yet")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Add friends to see when they're online and quickly browse their files.")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Add Buddy") {
                socialState.showAddBuddySheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(SeeleColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
