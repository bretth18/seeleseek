import SwiftUI
import SeeleseekCore

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
                .accessibilityHidden(true)

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Similarity rating \(rating)")

            HStack(spacing: SeeleSpacing.sm) {
                Button {
                    viewProfile()
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .help("View Profile")
                .accessibilityLabel("View \(username)'s profile")

                Button {
                    addBuddy()
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .help("Add Buddy")
                .accessibilityLabel("Add \(username) as buddy")

                Button {
                    browseFiles()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Browse Files")
                .accessibilityLabel("Browse \(username)'s files")

                Button {
                    startChat()
                } label: {
                    Image(systemName: "bubble.left")
                }
                .help("Send Message")
                .accessibilityLabel("Send message to \(username)")
            }
            .buttonStyle(.plain)
            .foregroundStyle(SeeleColors.accent)
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(username), similarity rating \(rating)")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityActions {
            Button("View profile") { viewProfile() }
            Button("Add buddy") { addBuddy() }
            Button("Browse files") { browseFiles() }
            Button("Send message") { startChat() }
        }
    }

    private func viewProfile() {
        Task { await appState.socialState.loadProfile(for: username) }
    }

    private func addBuddy() {
        Task { await appState.socialState.addBuddy(username) }
    }

    private func browseFiles() {
        appState.browseState.browseUser(username)
        appState.sidebarSelection = .browse
    }

    private func startChat() {
        appState.chatState.selectPrivateChat(username)
        appState.sidebarSelection = .chat
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
