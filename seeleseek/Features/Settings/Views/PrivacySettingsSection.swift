import SwiftUI

struct PrivacySettingsSection: View {
    @Bindable var settings: SettingsState
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    @State private var newBlockUsername: String = ""
    @State private var newBlockReason: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Privacy")

            settingsGroup("Visibility") {
                settingsToggle("Show online status", isOn: $settings.showOnlineStatus)
                settingsToggle("Allow users to browse my files", isOn: $settings.allowBrowsing)
            }

            settingsGroup("Search Responses") {
                settingsToggle("Respond to search requests", isOn: $settings.respondToSearches)
                    .onChange(of: settings.respondToSearches) { _, newValue in
                        Task {
                            try? await appState.networkClient.setAcceptDistributedChildren(newValue)
                        }
                    }
                settingsNumberField("Min query length", value: $settings.minSearchQueryLength, range: 1...20)
                settingsNumberField("Max results per response", value: $settings.maxSearchResponseResults, range: 0...500, placeholder: "0 = unlimited")
            }

            // MARK: - Blocklist
            blocklistSection

            // MARK: - Leech Detection
            leechDetectionSection
        }
    }

    // MARK: - Blocklist Section

    private var blocklistSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Blocklist")
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                if !socialState.blockedUsers.isEmpty {
                    Text("\(socialState.blockedUsers.count) blocked")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }

            settingsGroup("Block a User") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        HStack(spacing: SeeleSpacing.sm) {
                            TextField("Username", text: $newBlockUsername)
                                .textFieldStyle(SeeleTextFieldStyle())
                                .frame(maxWidth: 200)

                            TextField("Reason (optional)", text: $newBlockReason)
                                .textFieldStyle(SeeleTextFieldStyle())

                            Button("Block") {
                                guard !newBlockUsername.isEmpty else { return }
                                Task {
                                    await socialState.blockUser(newBlockUsername, reason: newBlockReason.isEmpty ? nil : newBlockReason)
                                    newBlockUsername = ""
                                    newBlockReason = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newBlockUsername.isEmpty)
                        }

                        Text("Blocked users cannot download from you or send you messages.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
            }

            if !socialState.blockedUsers.isEmpty {
                settingsGroup("Blocked Users") {
                    ForEach(socialState.filteredBlockedUsers) { blocked in
                        blockedUserRow(blocked)
                    }
                }
            }
        }
    }

    private func blockedUserRow(_ blocked: BlockedUser) -> some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.md) {
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
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Leech Detection Section

    private var leechDetectionSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Leech Detection")
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                if socialState.leechSettings.enabled && !socialState.detectedLeeches.isEmpty {
                    Text("\(socialState.detectedLeeches.count) detected")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.warning)
                }
            }

            settingsGroup("Detection") {
                settingsRow {
                    HStack {
                        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                            Text("Enable Leech Detection")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)

                            Text("Detect users who download without sharing files")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: Bindable(socialState).leechSettings.enabled)
                            .toggleStyle(SeeleToggleStyle())
                            .labelsHidden()
                            .onChange(of: socialState.leechSettings.enabled) { _, _ in
                                Task { await socialState.saveLeechSettings() }
                            }
                    }
                }
            }

            settingsGroup("Detection Thresholds") {
                settingsRow {
                    HStack {
                        Text("Minimum shared files")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        TextField("", value: Bindable(socialState).leechSettings.minSharedFiles, format: .number)
                            .textFieldStyle(SeeleTextFieldStyle())
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: socialState.leechSettings.minSharedFiles) { _, _ in
                                Task { await socialState.saveLeechSettings() }
                            }
                    }
                }
                settingsRow {
                    HStack {
                        Text("Minimum shared folders")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        TextField("", value: Bindable(socialState).leechSettings.minSharedFolders, format: .number)
                            .textFieldStyle(SeeleTextFieldStyle())
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: socialState.leechSettings.minSharedFolders) { _, _ in
                                Task { await socialState.saveLeechSettings() }
                            }
                    }
                }
                settingsRow {
                    Text("Users with fewer shares than these thresholds are considered leeches")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }
            .opacity(socialState.leechSettings.enabled ? 1 : 0.5)
            .disabled(!socialState.leechSettings.enabled)

            settingsGroup("Action") {
                ForEach(LeechAction.allCases, id: \.self) { action in
                    leechActionRow(action)
                }
            }
            .opacity(socialState.leechSettings.enabled ? 1 : 0.5)
            .disabled(!socialState.leechSettings.enabled)

            settingsGroup("Custom Message") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        TextEditor(text: Bindable(socialState).leechSettings.customMessage)
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(SeeleSpacing.sm)
                            .background(SeeleColors.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD / 2))
                            .frame(height: 80)
                            .onChange(of: socialState.leechSettings.customMessage) { _, _ in
                                Task { await socialState.saveLeechSettings() }
                            }

                        Text("This message is sent to leeches when action is set to \"Send message\"")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        FlowLayout(spacing: SeeleSpacing.xs) {
                            ForEach(LeechSettings.defaultMessages.indices, id: \.self) { index in
                                Button {
                                    socialState.leechSettings.customMessage = LeechSettings.defaultMessages[index]
                                    Task { await socialState.saveLeechSettings() }
                                } label: {
                                    Text("Template \(index + 1)")
                                        .font(SeeleTypography.caption)
                                        .foregroundStyle(SeeleColors.accent)
                                        .padding(.horizontal, SeeleSpacing.sm)
                                        .padding(.vertical, 4)
                                        .background(SeeleColors.accent.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .opacity(socialState.leechSettings.enabled && socialState.leechSettings.action == .message ? 1 : 0.5)
            .disabled(!socialState.leechSettings.enabled || socialState.leechSettings.action != .message)

            if socialState.leechSettings.enabled {
                settingsGroup("Detected Leeches (this session)") {
                    if socialState.detectedLeeches.isEmpty {
                        settingsRow {
                            Text("No leeches detected in this session")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        settingsRow {
                            HStack {
                                Spacer()
                                Button("Clear") {
                                    socialState.detectedLeeches.removeAll()
                                    socialState.warnedLeeches.removeAll()
                                }
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.accent)
                            }
                        }
                        ForEach(Array(socialState.detectedLeeches).sorted(), id: \.self) { username in
                            leechRow(username)
                        }
                    }
                }
            }
        }
    }

    private func leechActionRow(_ action: LeechAction) -> some View {
        Button {
            socialState.leechSettings.action = action
            Task { await socialState.saveLeechSettings() }
        } label: {
            settingsRow {
                HStack(spacing: SeeleSpacing.md) {
                    Image(systemName: socialState.leechSettings.action == action ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(socialState.leechSettings.action == action ? SeeleColors.accent : SeeleColors.textTertiary)

                    VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                        Text(action.displayName)
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Text(action.description)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }

                    Spacer()
                }
                .background(socialState.leechSettings.action == action ? SeeleColors.accent.opacity(0.1) : .clear)
            }
        }
        .buttonStyle(.plain)
    }

    private func leechRow(_ username: String) -> some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SeeleColors.warning)

                Text(username)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)

                if socialState.warnedLeeches.contains(username) {
                    Text("warned")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, 2)
                        .background(SeeleColors.surfaceSecondary, in: Capsule())
                }

                Spacer()

                Button("Block") {
                    Task {
                        await socialState.blockUser(username, reason: "Leech - no shared files")
                        socialState.detectedLeeches.remove(username)
                    }
                }
                .buttonStyle(.bordered)
                .foregroundStyle(SeeleColors.error)
            }
        }
    }
}

#Preview {
    ScrollView {
        PrivacySettingsSection(settings: SettingsState())
            .padding()
    }
    .environment(\.appState, AppState())
    .frame(width: 500, height: 600)
    .background(SeeleColors.background)
}
