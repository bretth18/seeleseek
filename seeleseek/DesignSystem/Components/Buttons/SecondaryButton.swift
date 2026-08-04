import SwiftUI
import SeeleseekCore

/// Convenience wrapper over `.seeleSecondary`.
/// For a plain button, prefer `Button + .buttonStyle(.seeleSecondary)`.
struct SecondaryButton: View {
    let title: String
    let icon: String?
    let fullWidth: Bool
    let role: ButtonRole?
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        fullWidth: Bool = true,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fullWidth = fullWidth
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: SeeleSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                }
                Text(title)
            }
        }
        .buttonStyle(.seeleSecondary(fullWidth: fullWidth))
    }
}

#Preview("Secondary Button") {
    VStack(spacing: SeeleSpacing.lg) {
        SecondaryButton("Cancel", icon: "xmark") {}
    }
    .padding()
    .background(SeeleColors.background)
}
