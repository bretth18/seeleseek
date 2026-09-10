import SwiftUI
import SeeleseekCore

struct SocialView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        @Bindable var navigation = appState.navigation

        VStack(spacing: 0) {
            StandardTabBar(selection: $navigation.socialTab, icon: { $0.icon })

            Divider().background(SeeleColors.surfaceSecondary)

            // Tab content
            Group {
                switch navigation.socialTab {
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
        .focusedSceneValue(\.tabCommands, .cycling($navigation.socialTab))
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
