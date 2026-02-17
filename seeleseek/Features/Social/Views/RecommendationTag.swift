import SwiftUI

struct RecommendationTag: View {
    @Environment(\.appState) private var appState
    let item: String
    let score: Int32

    var body: some View {
        Button {
            Task {
                await appState.socialState.addLike(item)
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Text(item)
                    .font(SeeleTypography.body)

                Image(systemName: "plus.circle")
                    .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
            }
            .foregroundStyle(SeeleColors.accent)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(SeeleColors.accent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Add '\(item)' to your likes")
    }
}

#Preview {
    FlowLayout(spacing: SeeleSpacing.sm) {
        RecommendationTag(item: "ambient", score: 45)
        RecommendationTag(item: "experimental", score: 38)
        RecommendationTag(item: "downtempo", score: 32)
    }
    .padding()
    .environment(\.appState, AppState())
    .background(SeeleColors.background)
}
