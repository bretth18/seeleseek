import SwiftUI

struct SimilarUserRow: View {
    @Environment(\.appState) private var appState
    let username: String
    let rating: UInt32

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            Circle()
                .fill(SeeleColors.surfaceSecondary)
                .frame(width: SeeleSpacing.iconSizeXL + 4, height: SeeleSpacing.iconSizeXL + 4)
                .overlay {
                    Text(String(username.prefix(1)).uppercased())
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

            Text(username)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)

            Spacer()

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

            HStack(spacing: SeeleSpacing.sm) {
                Button {
                    Task { await appState.socialState.loadProfile(for: username) }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .help("View Profile")

                Button {
                    Task { await appState.socialState.addBuddy(username) }
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
}

#Preview {
    VStack {
        SimilarUserRow(username: "jazzfan42", rating: 85)
        SimilarUserRow(username: "electrohead", rating: 72)
    }
    .padding()
    .environment(\.appState, AppState())
    .background(SeeleColors.background)
}
