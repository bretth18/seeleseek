import SwiftUI

struct IgnoredUsersView: View {
    @Environment(\.appState) private var appState
    @State private var usernameInput: String = ""
    @State private var reasonInput: String = ""

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            HStack(spacing: SeeleSpacing.md) {
                Text("Ignored Users")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(socialState.ignoredUsers.count) ignored")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            VStack(spacing: SeeleSpacing.md) {
                HStack(spacing: SeeleSpacing.sm) {
                    TextField("Username", text: $usernameInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)

                    TextField("Reason (optional)", text: $reasonInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Ignore") {
                        let reason = reasonInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await socialState.ignoreUser(
                                usernameInput,
                                reason: reason.isEmpty ? nil : reason
                            )
                            usernameInput = ""
                            reasonInput = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                StandardSearchField(
                    text: $state.socialState.ignoreSearchQuery,
                    placeholder: "Search ignored users..."
                )
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface.opacity(0.5))

            Divider().background(SeeleColors.surfaceSecondary)

            if socialState.filteredIgnoredUsers.isEmpty {
                StandardEmptyState(
                    icon: "eye.slash",
                    title: "No ignored users",
                    subtitle: "Users you ignore will appear here"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(socialState.filteredIgnoredUsers) { ignored in
                            row(ignored)
                        }
                    }
                    .padding(.top, SeeleSpacing.sm)
                }
            }
        }
    }

    private func row(_ ignored: IgnoredUser) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(SeeleColors.warning)
                .frame(width: SeeleSpacing.iconSize)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(ignored.username)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)

                HStack(spacing: SeeleSpacing.sm) {
                    if let reason = ignored.reason {
                        Text(reason)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }

                    Text("Ignored \(formatDate(ignored.dateIgnored))")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            Spacer()

            Button("Unignore") {
                Task { await socialState.unignoreUser(ignored.username) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    IgnoredUsersView()
        .environment(\.appState, AppState())
        .frame(width: 640, height: 460)
}
