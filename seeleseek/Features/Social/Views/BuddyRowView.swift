import SwiftUI

struct BuddyRowView: View {
    @Environment(\.appState) private var appState
    let buddy: Buddy

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Status indicator
            StandardStatusDot(status: buddy.status, size: SeeleSpacing.statusDotLarge)

            // Username and info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(buddy.username)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    if buddy.isPrivileged {
                        Image(systemName: "star.fill")
                            .font(.system(size: SeeleSpacing.iconSizeXS))
                            .foregroundStyle(SeeleColors.warning)
                    }

                    if let code = buddy.countryCode {
                        Text(countryFlag(for: code))
                            .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                    }
                }

                // Stats line
                if buddy.fileCount > 0 || buddy.averageSpeed > 0 {
                    HStack(spacing: SeeleSpacing.sm) {
                        if buddy.fileCount > 0 {
                            Label("\(formatNumber(buddy.fileCount)) files", systemImage: "doc")
                        }
                        if buddy.averageSpeed > 0 {
                            Label(formatSpeed(buddy.averageSpeed), systemImage: "arrow.up")
                        }
                    }
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            Spacer()

            // Hover actions
            if isHovering {
                HStack(spacing: SeeleSpacing.sm) {
                    Button {
                        viewProfile()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .help("View Profile")

                    Button {
                        browseFiles()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Browse Files")

                    Button {
                        startChat()
                    } label: {
                        Image(systemName: "bubble.left")
                    }
                    .help("Send Message")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SeeleColors.accent)
            }
        }
        .padding(.vertical, SeeleSpacing.xs)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            UserContextMenuItems(username: buddy.username, navigateOnBrowse: true, navigateOnMessage: true)
            Divider()
            Button("Refresh Status") {
                Task {
                    await appState.socialState.refreshBuddyStatus(buddy.username)
                }
            }
            Divider()
            Button("Remove Buddy", role: .destructive) {
                Task {
                    await appState.socialState.removeBuddy(buddy.username)
                }
            }
        }
    }

    private func viewProfile() {
        Task {
            await appState.socialState.loadProfile(for: buddy.username)
        }
    }

    private func browseFiles() {
        appState.browseState.browseUser(buddy.username)
        appState.sidebarSelection = .browse
    }

    private func startChat() {
        appState.chatState.selectPrivateChat(buddy.username)
        appState.sidebarSelection = .chat
    }

    private func formatNumber(_ value: UInt32) -> String {
        NumberFormatters.format(value)
    }

    private func formatSpeed(_ bytesPerSecond: UInt32) -> String {
        ByteFormatter.formatSpeed(bytesPerSecond)
    }

    private func countryFlag(for code: String) -> String {
        CountryFormatter.flag(for: code)
    }
}

#Preview {
    VStack(spacing: 0) {
        BuddyRowView(buddy: Buddy(
            username: "alice",
            status: .online,
            isPrivileged: true,
            averageSpeed: 1_500_000,
            fileCount: 12345,
            countryCode: "US"
        ))
        Divider()
        BuddyRowView(buddy: Buddy(
            username: "bob",
            status: .away,
            averageSpeed: 500_000,
            fileCount: 5000,
            countryCode: "GB"
        ))
        Divider()
        BuddyRowView(buddy: Buddy(
            username: "charlie",
            status: .offline,
            fileCount: 3000
        ))
    }
    .padding()
    .environment(\.appState, AppState())
}
