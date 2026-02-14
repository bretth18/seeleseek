import SwiftUI

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
            // Tab bar
            HStack(spacing: SeeleSpacing.sm) {
                ForEach(SocialTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.surface)

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
        .sheet(isPresented: Binding(
            get: { socialState.showAddBuddySheet },
            set: { socialState.showAddBuddySheet = $0 }
        )) {
            AddBuddySheet()
        }
        // Profile sheet is now on MainView for global access
    }

    private func tabButton(for tab: SocialTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 1, weight: isSelected ? .semibold : .regular))
                Text(tab.rawValue)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .font(SeeleTypography.body)
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(isSelected ? SeeleColors.selectionBorder : Color.clear, lineWidth: 1)
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
