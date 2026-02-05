import SwiftUI

struct MyProfileView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    @State private var editingDescription: String = ""
    @State private var hasChanges = false

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            // Header
            HStack {
                Text("My Profile")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                if hasChanges {
                    Button("Save") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SeeleColors.accent)
                }
            }

            Text("This information is shared when other users view your profile.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            // Description editor
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Description")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textSecondary)

                TextEditor(text: $editingDescription)
                    .font(SeeleTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(SeeleSpacing.sm)
                    .frame(height: 120)
                    .background(SeeleColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
                    .onChange(of: editingDescription) { _, newValue in
                        hasChanges = newValue != socialState.myDescription
                    }

                Text("\(editingDescription.count) / 1000 characters")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // My Interests Summary
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                HStack {
                    Text("My Interests")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)

                    Spacer()

                    Button("Edit") {
                        appState.sidebarSelection = .social
                    }
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)
                }

                if socialState.myLikes.isEmpty && socialState.myHates.isEmpty {
                    Text("No interests added yet. Add some to help others find you.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                        if !socialState.myLikes.isEmpty {
                            HStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                                Text(socialState.myLikes.prefix(5).joined(separator: ", "))
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                if socialState.myLikes.count > 5 {
                                    Text("+\(socialState.myLikes.count - 5) more")
                                        .font(SeeleTypography.caption)
                                        .foregroundStyle(SeeleColors.textTertiary)
                                }
                            }
                        }

                        if !socialState.myHates.isEmpty {
                            HStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "heart.slash.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                Text(socialState.myHates.prefix(5).joined(separator: ", "))
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                if socialState.myHates.count > 5 {
                                    Text("+\(socialState.myHates.count - 5) more")
                                        .font(SeeleTypography.caption)
                                        .foregroundStyle(SeeleColors.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
        .onAppear {
            editingDescription = socialState.myDescription
        }
    }

    private func saveProfile() {
        socialState.myDescription = editingDescription
        Task {
            await socialState.saveMyProfile()
            hasChanges = false
        }
    }
}

#Preview {
    MyProfileView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.myDescription = "Music lover sharing my collection."
            state.socialState.myLikes = ["jazz", "electronic", "ambient", "classical", "experimental", "vinyl"]
            state.socialState.myHates = ["pop", "country"]
            return state
        }())
        .frame(width: 400)
        .padding()
}
