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
                VStack(alignment: .leading, spacing: SeeleSpacing.md) {
                    likesSection
                    hatesSection
                }
                .padding(SeeleSpacing.sm)
            }
        }
    }

    private var addInterestSection: some View {
        HStack(spacing: SeeleSpacing.sm) {
            // Interest input
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: interestType == .like ? "heart" : "heart.slash")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(interestType == .like ? SeeleColors.success : SeeleColors.error)

                TextField("Add an interest...", text: $newInterest)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .onSubmit {
                        addInterest()
                    }
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.rowVertical)
            .background(SeeleColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))

            // Type picker
            Picker("Type", selection: $interestType) {
                ForEach(InterestType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Add button
            Button("Add") {
                addInterest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.rowVertical)
        .background(SeeleColors.surface)
    }

    private var likesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.success)
                Text("Things I Like")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Text("\(socialState.myLikes.count) items")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if socialState.myLikes.isEmpty {
                Text("No likes added yet.")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .padding(.horizontal, SeeleSpacing.rowHorizontal)
                    .padding(.vertical, SeeleSpacing.rowVertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            } else {
                FlowLayout(spacing: SeeleSpacing.tagSpacing) {
                    ForEach(socialState.myLikes, id: \.self) { interest in
                        interestTag(interest, color: SeeleColors.success) {
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
        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
            HStack {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.error)
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
                    .padding(.horizontal, SeeleSpacing.rowHorizontal)
                    .padding(.vertical, SeeleSpacing.rowVertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            } else {
                FlowLayout(spacing: SeeleSpacing.tagSpacing) {
                    ForEach(socialState.myHates, id: \.self) { interest in
                        interestTag(interest, color: SeeleColors.error) {
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
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.xs)
        .background(color.opacity(0.12), in: Capsule())
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
