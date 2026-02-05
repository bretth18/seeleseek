import SwiftUI

struct LeechSettingsView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider().background(SeeleColors.surfaceSecondary)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                    enableSection
                    thresholdsSection
                    actionSection
                    messageSection
                    detectedLeechesSection
                }
                .padding(SeeleSpacing.lg)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: SeeleSpacing.md) {
            Text("Leech Detection")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Spacer()

            if socialState.leechSettings.enabled {
                Text("\(socialState.detectedLeeches.count) detected")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.warning)
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Toggle(isOn: Bindable(socialState).leechSettings.enabled) {
                VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                    Text("Enable Leech Detection")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("Detect users who download without sharing files")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: socialState.leechSettings.enabled) { _, _ in
                Task { await socialState.saveLeechSettings() }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Detection Thresholds")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            VStack(spacing: SeeleSpacing.md) {
                HStack {
                    Text("Minimum shared files")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Spacer()

                    TextField("", value: Bindable(socialState).leechSettings.minSharedFiles, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: socialState.leechSettings.minSharedFiles) { _, _ in
                            Task { await socialState.saveLeechSettings() }
                        }
                }

                HStack {
                    Text("Minimum shared folders")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Spacer()

                    TextField("", value: Bindable(socialState).leechSettings.minSharedFolders, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: socialState.leechSettings.minSharedFolders) { _, _ in
                            Task { await socialState.saveLeechSettings() }
                        }
                }
            }

            Text("Users with fewer shares than these thresholds are considered leeches")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .opacity(socialState.leechSettings.enabled ? 1 : 0.5)
        .disabled(!socialState.leechSettings.enabled)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Action")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            ForEach(LeechAction.allCases, id: \.self) { action in
                actionRow(action)
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .opacity(socialState.leechSettings.enabled ? 1 : 0.5)
        .disabled(!socialState.leechSettings.enabled)
    }

    private func actionRow(_ action: LeechAction) -> some View {
        Button {
            socialState.leechSettings.action = action
            Task { await socialState.saveLeechSettings() }
        } label: {
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
            .padding(SeeleSpacing.sm)
            .background(socialState.leechSettings.action == action ? SeeleColors.accent.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD / 2))
        }
        .buttonStyle(.plain)
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Custom Message")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

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

            // Message templates
            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                Text("Templates:")
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
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .opacity(socialState.leechSettings.enabled && socialState.leechSettings.action == .message ? 1 : 0.5)
        .disabled(!socialState.leechSettings.enabled || socialState.leechSettings.action != .message)
    }

    private var detectedLeechesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Detected Leeches (this session)")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)

                Spacer()

                if !socialState.detectedLeeches.isEmpty {
                    Button("Clear") {
                        socialState.detectedLeeches.removeAll()
                        socialState.warnedLeeches.removeAll()
                    }
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)
                }
            }

            if socialState.detectedLeeches.isEmpty {
                Text("No leeches detected in this session")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(SeeleSpacing.lg)
            } else {
                LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                    ForEach(Array(socialState.detectedLeeches).sorted(), id: \.self) { username in
                        leechRow(username)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .opacity(socialState.leechSettings.enabled ? 1 : 0.5)
    }

    private func leechRow(_ username: String) -> some View {
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
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surfaceSecondary)
    }
}

#Preview {
    LeechSettingsView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.leechSettings.enabled = true
            state.socialState.detectedLeeches = ["leech_user1", "no_shares_bob"]
            state.socialState.warnedLeeches = ["leech_user1"]
            return state
        }())
        .frame(width: 600, height: 700)
}
