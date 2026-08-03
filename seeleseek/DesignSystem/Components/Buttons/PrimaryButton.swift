import SwiftUI
import SeeleseekCore

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let fullWidth: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

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
                    .font(SeeleTypography.headline)
            }
            .padding(.horizontal, fullWidth ? SeeleSpacing.xl : SeeleSpacing.lg)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: SeeleSpacing.controlHeight)
            // isLoading also disables the button; keep the accent fill
            // while loading so only a true disable dims it.
            .background(isEnabled || isLoading ? SeeleColors.accent : SeeleColors.textTertiary)
            .foregroundStyle(SeeleColors.textOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
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
