import SwiftUI

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SeeleSpacing.xl)
            .padding(.vertical, SeeleSpacing.md)
            .background(SeeleColors.accent)
            .foregroundStyle(SeeleColors.textOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                }
                Text(title)
                    .font(SeeleTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SeeleSpacing.xl)
            .padding(.vertical, SeeleSpacing.md)
            .background(SeeleColors.surfaceSecondary)
            .foregroundStyle(SeeleColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        size: CGFloat = SeeleSpacing.iconSize,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(SeeleColors.textSecondary)
                .frame(width: size + SeeleSpacing.lg, height: size + SeeleSpacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Buttons") {
    VStack(spacing: SeeleSpacing.lg) {
        PrimaryButton("Connect", icon: "network") {}
        PrimaryButton("Loading...", isLoading: true) {}
        SecondaryButton("Cancel", icon: "xmark") {}
        HStack {
            IconButton(icon: "gear") {}
            IconButton(icon: "magnifyingglass") {}
            IconButton(icon: "arrow.down.circle") {}
        }
    }
    .padding()
    .background(SeeleColors.background)
}
