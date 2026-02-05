import SwiftUI

struct BlocklistView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    @State private var newUsername: String = ""
    @State private var newReason: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider().background(SeeleColors.surfaceSecondary)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                    addBlockSection
                    blockedUsersSection
                }
                .padding(SeeleSpacing.lg)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: SeeleSpacing.md) {
            Text("Blocked Users")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Spacer()

            Text("\(socialState.blockedUsers.count) blocked")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
    }

    private var addBlockSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Block a User")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            HStack(spacing: SeeleSpacing.sm) {
                TextField("Username", text: $newUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                TextField("Reason (optional)", text: $newReason)
                    .textFieldStyle(.roundedBorder)

                Button("Block") {
                    guard !newUsername.isEmpty else { return }
                    Task {
                        await socialState.blockUser(newUsername, reason: newReason.isEmpty ? nil : newReason)
                        newUsername = ""
                        newReason = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newUsername.isEmpty)
            }

            Text("Blocked users cannot download from you or send you messages.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private var blockedUsersSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Blocked Users")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)

                Spacer()

                if !socialState.blockedUsers.isEmpty {
                    TextField("Search...", text: Bindable(socialState).blockSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            if socialState.filteredBlockedUsers.isEmpty {
                if socialState.blockedUsers.isEmpty {
                    emptyState
                } else {
                    Text("No users match your search")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(SeeleSpacing.xl)
                }
            } else {
                LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                    ForEach(socialState.filteredBlockedUsers) { blocked in
                        blockedUserRow(blocked)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SeeleSpacing.md) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: SeeleSpacing.iconSizeHero - 8, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No blocked users")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Users you block will appear here")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(SeeleSpacing.xl)
    }

    private func blockedUserRow(_ blocked: BlockedUser) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            // Avatar placeholder
            Circle()
                .fill(SeeleColors.error.opacity(0.2))
                .frame(width: SeeleSpacing.iconSizeXL + 4, height: SeeleSpacing.iconSizeXL + 4)
                .overlay {
                    Image(systemName: "nosign")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.error)
                }

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(blocked.username)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)

                HStack(spacing: SeeleSpacing.sm) {
                    if let reason = blocked.reason {
                        Text(reason)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }

                    Text("Blocked \(formatDate(blocked.dateBlocked))")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            Spacer()

            Button("Unblock") {
                Task {
                    await socialState.unblockUser(blocked.username)
                }
            }
            .buttonStyle(.bordered)
            .foregroundStyle(SeeleColors.error)
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    BlocklistView()
        .environment(\.appState, {
            let state = AppState()
            return state
        }())
        .frame(width: 600, height: 400)
}
