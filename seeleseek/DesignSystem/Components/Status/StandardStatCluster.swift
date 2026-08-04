import SwiftUI
import SeeleseekCore

/// Capsule grouping for StandardLiveStat pairs in a header's trailing
/// cluster. One quiet container — stat pairs inside stay flat, never
/// their own capsules.
struct StandardStatCluster<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: SeeleSpacing.lg) {
            content
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(Capsule())
    }
}

#Preview {
    StandardStatCluster {
        StandardLiveStat(
            icon: "arrow.down",
            value: "1.2 MB/s",
            iconColor: SeeleColors.info,
            accessibilityLabel: "Download speed 1.2 MB/s"
        )
        StandardLiveStat(
            icon: "arrow.up",
            value: "256 KB/s",
            iconColor: SeeleColors.success,
            accessibilityLabel: "Upload speed 256 KB/s"
        )
        StandardLiveStat(
            icon: "person.2.fill",
            value: "14",
            accessibilityLabel: "14 active peers"
        )
    }
    .padding()
    .background(SeeleColors.background)
}
