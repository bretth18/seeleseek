import SwiftUI
import SeeleseekCore

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
                        .accessibilityLabel("\(profile.username)'s profile picture")
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: SeeleSpacing.iconSizeXL + 4))
                        .foregroundStyle(SeeleColors.textTertiary)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(profile.username)
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    if profile.isPrivileged {
                        // Only the star shows the privileged state.
                        // Thus the star gets a label and stays visible
                        // to VoiceOver.
                        Image(systemName: "star.fill")
                            .font(.system(size: SeeleSpacing.iconSizeSmall))
                            .foregroundStyle(SeeleColors.warning)
                            .accessibilityLabel("Privileged user")
                    }

                    if let flag = resolvedCountryFlag {
                        Text(flag)
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

                    if let info = liveExtendedClientInfo {
                        Text(info.displayLabel)
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.accent)
                            .padding(.horizontal, SeeleSpacing.xs)
                            .padding(.vertical, SeeleSpacing.xxs)
                            .background(SeeleColors.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeMedium))
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close profile")
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("About")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

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
                .accessibilityAddTraits(.isHeader)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Interests")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

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
                .buttonStyle(.seeleSecondary(.small))
                .disabled(isBuddy)

                Button {
                    browseFiles()
                } label: {
                    Label("Browse Files", systemImage: "folder")
                }
                .buttonStyle(.seeleSecondary(.small))

                Button {
                    startChat()
                } label: {
                    Label("Message", systemImage: "bubble.left")
                }
                .buttonStyle(.seelePrimary(.small))
            }

            HStack(spacing: SeeleSpacing.md) {
                Button {
                    showGivePrivileges.toggle()
                } label: {
                    Label("Give Privileges", systemImage: "star")
                }
                .buttonStyle(.seeleSecondary(.small))
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
                        // The segmented style hides the picker title.
                        // An explicit label keeps the purpose audible.
                        .accessibilityLabel("Days of privileges")

                        Button("Give \(selectedDays) day\(selectedDays == 1 ? "" : "s")") {
                            appState.socialState.givePrivileges(to: profile.username, days: selectedDays)
                            showGivePrivileges = false
                        }
                        .buttonStyle(.seelePrimary)
                    }
                    .padding(SeeleSpacing.lg)
                    .frame(width: 260)
                }

                if appState.socialState.isIgnored(profile.username) {
                    Button {
                        Task { await appState.socialState.unignoreUser(profile.username) }
                    } label: {
                        Label("Unignore", systemImage: "eye")
                    }
                    .buttonStyle(.seeleSecondary(.small))
                } else {
                    Button(role: .destructive) {
                        Task { await appState.socialState.ignoreUser(profile.username) }
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .buttonStyle(.seeleSecondary(.small))
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

    /// Live-best country flag for the profile's user. Prefers the
    /// app-wide `UserInfoCache` (GeoIP-resolved from peer IPs — the
    /// same source rows use, so the sheet never lags behind a row),
    /// falls back to the persisted `profile.countryCode`. Returns nil
    /// when neither source has resolved a country.
    private var resolvedCountryFlag: String? {
        let live = appState.networkClient.userInfoCache.flag(for: profile.username)
        if !live.isEmpty { return live }
        return profile.countryCode.map { CountryFormatter.flag(for: $0) }
    }

    /// Advertised extensions for this user, looked up in the dedicated
    /// per-username dict on the pool. Reading the dict invalidates this
    /// view only when capabilities are discovered (a rare, sticky event),
    /// not on every connection-state or bytes mutation the way observing
    /// `connections` would.
    private var liveExtendedClientInfo: ExtendedClientInfo? {
        appState.networkClient.peerConnectionPool.extendedClientInfoByUser[profile.username]
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
