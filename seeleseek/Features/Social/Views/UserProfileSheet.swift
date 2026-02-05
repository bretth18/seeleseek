import SwiftUI

struct UserProfileSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: SeeleSpacing.xl) {
                // Header
                header

                Divider().background(SeeleColors.surfaceSecondary)

                // Description
                if !profile.description.isEmpty {
                    descriptionSection
                }

                // Stats
                statsSection

                // Interests
                if !profile.likedInterests.isEmpty || !profile.hatedInterests.isEmpty {
                    interestsSection
                }

                // Actions
                actionsSection
            }
            .padding(SeeleSpacing.xl)
        }
        .frame(width: 450, height: 550)
        .background(SeeleColors.surface)
    }

    private var header: some View {
        HStack(spacing: SeeleSpacing.lg) {
            // Profile picture placeholder
            ZStack {
                Circle()
                    .fill(SeeleColors.surfaceSecondary)
                    .frame(width: 80, height: 80)

                if let pictureData = profile.picture,
                   let nsImage = NSImage(data: pictureData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(profile.username)
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    if profile.isPrivileged {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.yellow)
                    }

                    if let code = profile.countryCode {
                        Text(countryFlag(for: code))
                            .font(.system(size: 16))
                    }
                }

                // Status badge
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(profile.status.description)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("About")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Text(profile.description)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Stats")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: SeeleSpacing.md) {
                statItem(label: "Shared Files", value: profile.formattedFileCount)
                statItem(label: "Upload Speed", value: profile.formattedSpeed)
                statItem(label: "Total Uploads", value: "\(profile.totalUploads)")
                statItem(label: "Queue Size", value: "\(profile.queueSize)")
                statItem(label: "Free Slots", value: profile.hasFreeSlots ? "Yes" : "No")
                statItem(label: "Folders", value: "\(profile.sharedFolders)")
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Text(value)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.sm)
        .background(SeeleColors.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Interests")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            if !profile.likedInterests.isEmpty {
                VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                    Text("Likes")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    FlowLayout(spacing: SeeleSpacing.xs) {
                        ForEach(profile.likedInterests, id: \.self) { interest in
                            interestTag(interest, color: .green)
                        }
                    }
                }
            }

            if !profile.hatedInterests.isEmpty {
                VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                    Text("Dislikes")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    FlowLayout(spacing: SeeleSpacing.xs) {
                        ForEach(profile.hatedInterests, id: \.self) { interest in
                            interestTag(interest, color: .red)
                        }
                    }
                }
            }
        }
    }

    private func interestTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SeeleTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var actionsSection: some View {
        HStack(spacing: SeeleSpacing.md) {
            Button {
                addAsBuddy()
            } label: {
                Label("Add Buddy", systemImage: "person.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(isBuddy)

            Button {
                browseFiles()
            } label: {
                Label("Browse Files", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                startChat()
            } label: {
                Label("Message", systemImage: "bubble.left")
            }
            .buttonStyle(.borderedProminent)
            .tint(SeeleColors.accent)
        }
        .padding(.top, SeeleSpacing.md)
    }

    private var statusColor: Color {
        switch profile.status {
        case .online: .green
        case .away: .yellow
        case .offline: .gray
        }
    }

    private var isBuddy: Bool {
        appState.socialState.buddies.contains { $0.username == profile.username }
    }

    private func addAsBuddy() {
        Task {
            await appState.socialState.addBuddy(profile.username)
        }
    }

    private func browseFiles() {
        appState.browseState.browseUser(profile.username)
        appState.sidebarSelection = .browse
        dismiss()
    }

    private func startChat() {
        appState.chatState.selectPrivateChat(profile.username)
        appState.sidebarSelection = .chat
        dismiss()
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
    UserProfileSheet(profile: UserProfile(
        username: "testuser",
        description: "Music enthusiast sharing my collection. Mostly jazz, classical, and electronic.",
        totalUploads: 1234,
        queueSize: 5,
        hasFreeSlots: true,
        averageSpeed: 1_500_000,
        sharedFiles: 15000,
        sharedFolders: 200,
        likedInterests: ["jazz", "electronic", "classical", "vinyl"],
        hatedInterests: ["pop", "country"],
        status: .online,
        isPrivileged: true,
        countryCode: "US"
    ))
    .environment(\.appState, AppState())
}
