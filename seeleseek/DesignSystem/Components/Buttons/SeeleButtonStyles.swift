import SwiftUI
import SeeleseekCore

/// Size axis for the Seele button styles.
enum SeeleButtonSize {
    /// Bars, CTAs, sheet footers.
    case regular
    /// Inline and row-level actions.
    case small

    var minHeight: CGFloat {
        switch self {
        case .regular: SeeleSpacing.controlHeight
        case .small: SeeleSpacing.buttonHeight
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: SeeleSpacing.lg
        case .small: SeeleSpacing.md
        }
    }

    var font: Font {
        switch self {
        case .regular: SeeleTypography.headline
        case .small: SeeleTypography.subheadline
        }
    }
}

/// Accent pill — the primary action on a surface. At most one per surface.
struct SeelePrimaryButtonStyle: ButtonStyle {
    var size: SeeleButtonSize = .regular
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, size: size, fullWidth: fullWidth)
    }

    // @Environment only updates on a View, not on the style struct.
    private struct StyledLabel: View {
        let configuration: Configuration
        let size: SeeleButtonSize
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(SeeleColors.textOnAccent)
                .padding(.horizontal, fullWidth ? SeeleSpacing.xl : size.horizontalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
                .background(isEnabled ? SeeleColors.accent : SeeleColors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1.0)
        }
    }
}

/// Neutral pill for secondary actions that still need chrome.
struct SeeleSecondaryButtonStyle: ButtonStyle {
    var size: SeeleButtonSize = .regular
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, size: size, fullWidth: fullWidth)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let size: SeeleButtonSize
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        private var labelColor: Color {
            guard isEnabled else { return SeeleColors.textTertiary }
            return configuration.role == .destructive ? SeeleColors.error : SeeleColors.textPrimary
        }

        var body: some View {
            configuration.label
                .font(size.font)
                .foregroundStyle(labelColor)
                .padding(.horizontal, fullWidth ? SeeleSpacing.xl : size.horizontalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
                .background(SeeleColors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                        .stroke(SeeleColors.textTertiary.opacity(0.3), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1.0)
        }
    }
}

/// Square icon-only button; also styles Menu labels, which the IconButton
/// wrapper view cannot.
struct SeeleIconButtonStyle: ButtonStyle {
    var iconSize: CGFloat = SeeleSpacing.iconSize

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, iconSize: iconSize)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let iconSize: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isEnabled ? SeeleColors.textSecondary : SeeleColors.textTertiary)
                .frame(width: iconSize + SeeleSpacing.lg, height: iconSize + SeeleSpacing.lg)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        }
    }
}

extension ButtonStyle where Self == SeelePrimaryButtonStyle {
    static var seelePrimary: SeelePrimaryButtonStyle { .init() }
    static func seelePrimary(_ size: SeeleButtonSize = .regular, fullWidth: Bool = false) -> SeelePrimaryButtonStyle {
        .init(size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SeeleSecondaryButtonStyle {
    static var seeleSecondary: SeeleSecondaryButtonStyle { .init() }
    static func seeleSecondary(_ size: SeeleButtonSize = .regular, fullWidth: Bool = false) -> SeeleSecondaryButtonStyle {
        .init(size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SeeleIconButtonStyle {
    static var seeleIcon: SeeleIconButtonStyle { .init() }
    static func seeleIcon(iconSize: CGFloat) -> SeeleIconButtonStyle {
        .init(iconSize: iconSize)
    }
}

#Preview("Seele Button Styles") {
    VStack(spacing: SeeleSpacing.lg) {
        HStack {
            Button("Search") {}.buttonStyle(.seelePrimary)
            Button("Cancel") {}.buttonStyle(.seeleSecondary)
            Button("Disabled") {}.buttonStyle(.seelePrimary).disabled(true)
        }
        HStack {
            Button("Add", systemImage: "plus") {}.buttonStyle(.seelePrimary(.small))
            Button("Remove") {}.buttonStyle(.seeleSecondary(.small))
            Button("Trash", systemImage: "trash") {}.labelStyle(.iconOnly).buttonStyle(.seeleIcon)
        }
        Button("Connect") {}.buttonStyle(.seelePrimary(fullWidth: true))
    }
    .padding()
    .background(SeeleColors.background)
}
