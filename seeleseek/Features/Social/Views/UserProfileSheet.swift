import SwiftUI

struct UserProfileSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile

    @State private var showGivePrivileges = false
    @State private var selectedDays: UInt32 = 1

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
                        .font(.system(size: SeeleSpacing.iconSizeXL + 4))
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
                            .font(.system(size: SeeleSpacing.iconSizeSmall))
                            .foregroundStyle(SeeleColors.warning)
                    }

                    if let code = profile.countryCode {
                        Text(countryFlag(for: code))
                            .font(.system(size: SeeleSpacing.iconSize))
                    }
                }

                // Status badge
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)
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
                    .font(.system(size: SeeleSpacing.iconSizeLarge))
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
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Text(value)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SeeleSpacing.sm)
        .background(SeeleColors.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
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
                            interestTag(interest, color: SeeleColors.success)
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
                            interestTag(interest, color: SeeleColors.error)
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
            .padding(.vertical, SeeleSpacing.xs)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var actionsSection: some View {
        VStack(spacing: SeeleSpacing.md) {
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

            HStack(spacing: SeeleSpacing.md) {
                Button {
                    showGivePrivileges.toggle()
                } label: {
                    Label("Give Privileges", systemImage: "star")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showGivePrivileges) {
                    VStack(spacing: SeeleSpacing.md) {
                        Text("Give Privileges")
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Text("Give days of privileges to \(profile.username)")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        Picker("Days", selection: $selectedDays) {
                            Text("1 day").tag(UInt32(1))
                            Text("5 days").tag(UInt32(5))
                            Text("10 days").tag(UInt32(10))
                            Text("30 days").tag(UInt32(30))
                        }
                        .pickerStyle(.segmented)

                        Button("Give \(selectedDays) day\(selectedDays == 1 ? "" : "s")") {
                            appState.socialState.givePrivileges(to: profile.username, days: selectedDays)
                            showGivePrivileges = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SeeleColors.warning)
                    }
                    .padding(SeeleSpacing.lg)
                    .frame(width: 260)
                }
            }
        }
        .padding(.top, SeeleSpacing.md)
    }

    private var statusColor: Color {
        switch profile.status {
        case .online: SeeleColors.success
        case .away: SeeleColors.warning
        case .offline: SeeleColors.textTertiary
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
        CountryFormatter.flag(for: code)
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
