import SwiftUI

struct BuddyRowView: View {
    @Environment(\.appState) private var appState
    let buddy: Buddy

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Username and info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(buddy.username)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    if buddy.isPrivileged {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SeeleColors.warning)
                    }

                    if let code = buddy.countryCode {
                        Text(countryFlag(for: code))
                            .font(.system(size: 12))
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
            Button("View Profile") { viewProfile() }
            Button("Browse Files") { browseFiles() }
            Button("Send Message") { startChat() }
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

    private var statusColor: Color {
        switch buddy.status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.textTertiary
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatSpeed(_ bytesPerSecond: UInt32) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    private func countryFlag(for code: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(Character(unicode))
            }
        }
        return flag
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
