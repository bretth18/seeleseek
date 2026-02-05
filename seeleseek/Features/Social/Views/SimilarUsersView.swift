import SwiftUI

struct SimilarUsersView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider().background(SeeleColors.surfaceSecondary)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
                    similarUsersSection
                    recommendationsSection
                }
                .padding(SeeleSpacing.lg)
            }
        }
        .onAppear {
            // Load data when view appears if not already loaded
            if socialState.similarUsers.isEmpty && socialState.recommendations.isEmpty {
                refresh()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: SeeleSpacing.md) {
            Text("Discovery")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Spacer()

            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(socialState.isLoadingSimilar || socialState.isLoadingRecommendations)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
    }

    private var similarUsersSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(SeeleColors.accent)
                Text("Similar Users")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                if socialState.isLoadingSimilar {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("Users with similar interests based on your likes and dislikes.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            if socialState.myLikes.isEmpty && socialState.myHates.isEmpty {
                emptyInterestsPrompt
            } else if socialState.similarUsers.isEmpty && !socialState.isLoadingSimilar {
                noResultsView("No similar users found. Try adding more interests.")
            } else {
                LazyVStack(spacing: SeeleSpacing.sm) {
                    ForEach(socialState.similarUsers, id: \.username) { user in
                        similarUserRow(username: user.username, rating: user.rating)
                    }
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(SeeleColors.accent)
                Text("Recommended Interests")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                if socialState.isLoadingRecommendations {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("Interests you might like based on similar users.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            if socialState.myLikes.isEmpty && socialState.myHates.isEmpty {
                // Don't show another prompt, similar users section has it
            } else if socialState.recommendations.isEmpty && !socialState.isLoadingRecommendations {
                noResultsView("No recommendations found.")
            } else {
                FlowLayout(spacing: SeeleSpacing.sm) {
                    ForEach(socialState.recommendations.prefix(20), id: \.item) { rec in
                        recommendationTag(item: rec.item, score: rec.score)
                    }
                }
            }
        }
    }

    private var emptyInterestsPrompt: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(SeeleColors.accent)
                Text("Popular Interests")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)
            }

            Text("Add some interests to find similar users. Here are popular interests across the network:")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            if socialState.globalRecommendations.isEmpty {
                Text("Loading popular interests...")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SeeleSpacing.md)
            } else {
                FlowLayout(spacing: SeeleSpacing.sm) {
                    ForEach(socialState.globalRecommendations.prefix(30), id: \.item) { rec in
                        recommendationTag(item: rec.item, score: rec.score)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func noResultsView(_ message: String) -> some View {
        Text(message)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func similarUserRow(username: String, rating: UInt32) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            // Avatar placeholder
            Circle()
                .fill(SeeleColors.surfaceSecondary)
                .frame(width: SeeleSpacing.iconSizeXL + 4, height: SeeleSpacing.iconSizeXL + 4)
                .overlay {
                    Text(String(username.prefix(1)).uppercased())
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

            // Username
            Text(username)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)

            Spacer()

            // Similarity score
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "star.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.warning)
                Text("\(rating)")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.xs)
            .background(SeeleColors.surface, in: Capsule())

            // Actions
            HStack(spacing: SeeleSpacing.sm) {
                Button {
                    Task {
                        await socialState.addBuddy(username)
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .help("Add Buddy")

                Button {
                    appState.browseState.browseUser(username)
                    appState.sidebarSelection = .browse
                } label: {
                    Image(systemName: "folder")
                }
                .help("Browse Files")

                Button {
                    appState.chatState.selectPrivateChat(username)
                    appState.sidebarSelection = .chat
                } label: {
                    Image(systemName: "bubble.left")
                }
                .help("Send Message")
            }
            .buttonStyle(.plain)
            .foregroundStyle(SeeleColors.accent)
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func recommendationTag(item: String, score: Int32) -> some View {
        Button {
            Task {
                await socialState.addLike(item)
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Text(item)
                    .font(SeeleTypography.body)

                Image(systemName: "plus.circle")
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
            }
            .foregroundStyle(SeeleColors.accent)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.accent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Add '\(item)' to your likes")
    }

    private func refresh() {
        Task {
            await socialState.loadSimilarUsers()
            await socialState.loadRecommendations()
        }
    }
}

#Preview {
    SimilarUsersView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.myLikes = ["jazz", "electronic"]
            state.socialState.similarUsers = [
                (username: "jazzfan42", rating: 85),
                (username: "electrohead", rating: 72),
                (username: "musiclover", rating: 65),
            ]
            state.socialState.recommendations = [
                (item: "ambient", score: 45),
                (item: "experimental", score: 38),
                (item: "downtempo", score: 32),
            ]
            return state
        }())
        .frame(width: 500, height: 500)
}
