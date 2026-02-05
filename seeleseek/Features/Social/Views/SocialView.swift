import SwiftUI

struct SocialView: View {
    @Environment(\.appState) private var appState

    enum SocialTab: String, CaseIterable {
        case buddies = "Buddies"
        case interests = "Interests"
        case discover = "Discover"
        case blocklist = "Blocklist"
        case leech = "Leech"

        var icon: String {
            switch self {
            case .buddies: "person.2"
            case .interests: "heart"
            case .discover: "sparkles"
            case .blocklist: "nosign"
            case .leech: "exclamationmark.triangle"
            }
        }
    }

    @State private var selectedTab: SocialTab = .buddies

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: SeeleSpacing.md) {
                ForEach(SocialTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.md)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            // Tab content
            Group {
                switch selectedTab {
                case .buddies:
                    BuddyListView()
                case .interests:
                    InterestsView()
                case .discover:
                    SimilarUsersView()
                case .blocklist:
                    BlocklistView()
                case .leech:
                    LeechSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SeeleColors.background)
        .sheet(isPresented: Binding(
            get: { socialState.showAddBuddySheet },
            set: { socialState.showAddBuddySheet = $0 }
        )) {
            AddBuddySheet()
        }
        .sheet(isPresented: Binding(
            get: { socialState.showProfileSheet },
            set: { socialState.showProfileSheet = $0 }
        )) {
            if let profile = socialState.viewingProfile {
                UserProfileSheet(profile: profile)
            }
        }
    }

    private func tabButton(for tab: SocialTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: tab.icon)
                Text(tab.rawValue)
            }
            .font(SeeleTypography.body)
            .foregroundStyle(selectedTab == tab ? SeeleColors.accent : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                selectedTab == tab ? SeeleColors.accent.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SocialView()
        .environment(\.appState, AppState())
        .frame(width: 600, height: 500)
}
