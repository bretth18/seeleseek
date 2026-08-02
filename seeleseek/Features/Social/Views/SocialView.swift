import SwiftUI
import SeeleseekCore

struct SocialView: View {
    @Environment(\.appState) private var appState

    enum SocialTab: String, CaseIterable {
        case buddies = "Buddies"
        case ignored = "Ignored"
        case interests = "Interests"
        case discover = "Discover"

        var icon: String {
            switch self {
            case .buddies: "person.2"
            case .ignored: "eye.slash"
            case .interests: "heart"
            case .discover: "sparkles"
            }
        }
    }

    @State private var selectedTab: SocialTab = .buddies

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardTabBar(selection: $selectedTab, icon: { $0.icon })

            Divider().background(SeeleColors.surfaceSecondary)

            // Tab content
            Group {
                switch selectedTab {
                case .buddies:
                    BuddyListView()
                case .ignored:
                    IgnoredUsersView()
                case .interests:
                    InterestsView()
                case .discover:
                    SimilarUsersView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SeeleColors.background)
        .focusedSceneValue(\.tabCommands, .cycling($selectedTab))
        .sheet(isPresented: Bindable(socialState).showAddBuddySheet) {
            AddBuddySheet()
        }
        // Profile sheet is now on MainView for global access
    }
}

#Preview {
    SocialView()
        .environment(\.appState, AppState())
        .frame(width: 600, height: 500)
}
