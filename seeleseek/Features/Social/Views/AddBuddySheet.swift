import SwiftUI

struct AddBuddySheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: SeeleSpacing.lg) {
            // Header
            Text("Add Buddy")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textPrimary)

            Text("Enter the username of the person you want to add to your buddy list.")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textSecondary)
                .multilineTextAlignment(.center)

            // Username field
            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                Text("Username")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)

                TextField("Enter username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addBuddy()
                    }
            }

            // Buttons
            HStack(spacing: SeeleSpacing.md) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    addBuddy()
                }
                .buttonStyle(.borderedProminent)
                .tint(SeeleColors.accent)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
        }
        .padding(SeeleSpacing.xl)
        .frame(width: 350)
        .background(SeeleColors.surface)
    }

    private func addBuddy() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }

        isAdding = true

        Task {
            await appState.socialState.addBuddy(trimmedUsername)
            dismiss()
        }
    }
}

#Preview {
    AddBuddySheet()
        .environment(\.appState, AppState())
}
