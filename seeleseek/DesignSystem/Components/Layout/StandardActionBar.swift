import SwiftUI
import SeeleseekCore

/// Top-of-view control row with fixed metrics. Every view that adopts it
/// renders its header at the same height, so the divider below never
/// shifts when the user switches views (#67).
struct StandardActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            content
        }
        .frame(minHeight: SeeleSpacing.controlHeight)
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface.opacity(0.5))
    }
}

#Preview {
    VStack(spacing: 0) {
        StandardActionBar {
            StandardSearchField(text: .constant(""), placeholder: "Search...")
            PrimaryButton("Search", fullWidth: false) {}
        }
        Divider().background(SeeleColors.surfaceSecondary)
        Spacer()
    }
    .background(SeeleColors.background)
    .frame(width: 500, height: 200)
}
