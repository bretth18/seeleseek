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
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(tab.rawValue)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .font(SeeleTypography.body)
            .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(
                isSelected ? SeeleColors.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall)
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
