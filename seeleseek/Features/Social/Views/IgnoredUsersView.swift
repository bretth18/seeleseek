import SwiftUI
import SeeleseekCore

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
            // Toolbar
            HStack(spacing: SeeleSpacing.md) {
                StandardSearchField(
                    text: $state.socialState.ignoreSearchQuery,
                    placeholder: "Search ignored users..."
                )

                Spacer()

                Text("\(socialState.ignoredUsers.count) ignored")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                Button {
                    socialState.showIgnoreInput.toggle()
                } label: {
                    Label("Ignore", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ignore a user")
                .accessibilityValue(socialState.showIgnoreInput ? "expanded" : "collapsed")
            }
            .padding(SeeleSpacing.lg)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            if socialState.showIgnoreInput {
                HStack(spacing: SeeleSpacing.sm) {
                    TextField("Username", text: $usernameInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Username to ignore")

                    TextField("Reason (optional)", text: $reasonInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Reason for ignoring, optional")

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
                .padding(SeeleSpacing.lg)

                Divider().background(SeeleColors.surfaceSecondary)
            }

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
                .accessibilityHidden(true)

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ignoredRowLabel(ignored))
            .accessibilityAddTraits(.isStaticText)

            Spacer()

            Button("Unignore") {
                Task { await socialState.unignoreUser(ignored.username) }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Unignore \(ignored.username)")
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    private func ignoredRowLabel(_ ignored: IgnoredUser) -> String {
        var parts: [String] = [ignored.username]
        if let reason = ignored.reason {
            parts.append(reason)
        }
        parts.append("ignored \(spokenDate(ignored.dateIgnored))")
        return parts.joined(separator: ", ")
    }

    /// Cached — allocating a formatter per row render is expensive.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Full-style formatter for spoken labels. The abbreviated visual
    /// form is unclear when VoiceOver reads it.
    private static let spokenRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func spokenDate(_ date: Date) -> String {
        Self.spokenRelativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    IgnoredUsersView()
        .environment(\.appState, AppState())
        .frame(width: 640, height: 460)
}
