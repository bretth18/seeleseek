import SwiftUI

struct InterestsView: View {
    @Environment(\.appState) private var appState

    @State private var newInterest: String = ""
    @State private var interestType: InterestType = .like

    enum InterestType: String, CaseIterable {
        case like = "Like"
        case hate = "Dislike"
    }

    private var socialState: SocialState {
        appState.socialState
    }

    var body: some View {
        VStack(spacing: 0) {
            // Add new interest
            addInterestSection

            Divider().background(SeeleColors.surfaceSecondary)

            // Interests lists
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
                    likesSection
                    hatesSection
                }
                .padding(SeeleSpacing.lg)
            }
        }
    }

    private var addInterestSection: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Interest input
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: interestType == .like ? "heart" : "heart.slash")
                    .foregroundStyle(interestType == .like ? .green : .red)

                TextField("Add an interest...", text: $newInterest)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        addInterest()
                    }
            }
            .padding(SeeleSpacing.sm)
            .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

            // Type picker
            Picker("Type", selection: $interestType) {
                ForEach(InterestType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            // Add button
            Button("Add") {
                addInterest()
            }
            .buttonStyle(.borderedProminent)
            .tint(SeeleColors.accent)
            .disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
    }

    private var likesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.green)
                Text("Things I Like")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(socialState.myLikes.count) items")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if socialState.myLikes.isEmpty {
                Text("No likes added yet. Add interests to help discover similar users.")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SeeleSpacing.md)
                    .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
            } else {
                FlowLayout(spacing: SeeleSpacing.sm) {
                    ForEach(socialState.myLikes, id: \.self) { interest in
                        interestTag(interest, color: .green) {
                            Task {
                                await socialState.removeLike(interest)
                            }
                        }
                    }
                }
            }
        }
    }

    private var hatesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Image(systemName: "heart.slash.fill")
                    .foregroundStyle(.red)
                Text("Things I Dislike")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(socialState.myHates.count) items")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if socialState.myHates.isEmpty {
                Text("No dislikes added yet.")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SeeleSpacing.md)
                    .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
            } else {
                FlowLayout(spacing: SeeleSpacing.sm) {
                    ForEach(socialState.myHates, id: \.self) { interest in
                        interestTag(interest, color: .red) {
                            Task {
                                await socialState.removeHate(interest)
                            }
                        }
                    }
                }
            }
        }
    }

    private func interestTag(_ text: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Text(text)
                .font(SeeleTypography.body)
                .foregroundStyle(color)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func addInterest() {
        let trimmed = newInterest.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        Task {
            switch interestType {
            case .like:
                await socialState.addLike(trimmed)
            case .hate:
                await socialState.addHate(trimmed)
            }
            newInterest = ""
        }
    }
}

#Preview {
    InterestsView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.myLikes = ["jazz", "electronic", "classical", "vinyl", "lossless"]
            state.socialState.myHates = ["pop", "country"]
            return state
        }())
        .frame(width: 500, height: 400)
}
