import SwiftUI
import SeeleseekCore

/// Convenience wrapper over `.seelePrimary` that adds a loading spinner.
/// For a plain button, prefer `Button + .buttonStyle(.seelePrimary)`.
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let fullWidth: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                }
                Text(title)
            }
        }
        .buttonStyle(.seelePrimary(fullWidth: fullWidth))
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
        .animation(.easeInOut(duration: SeeleSpacing.animationFast), value: isLoading)
    }
}

#Preview("Buttons") {
    VStack(spacing: SeeleSpacing.lg) {
        PrimaryButton("Connect", icon: "network") {}
        PrimaryButton("Loading...", isLoading: true) {}
    }
    .padding()
    .background(SeeleColors.background)
}
