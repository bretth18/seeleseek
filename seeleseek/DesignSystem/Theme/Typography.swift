import SwiftUI

enum SeeleTypography {
    // MARK: - Headings (Fixed sizes for consistency)
    static let logo = Font.system(size: 24, weight: .black)
    static let largeTitle = Font.system(size: 22, weight: .bold)
    static let title = Font.system(size: 18, weight: .bold)
    static let title2 = Font.system(size: 16, weight: .semibold)
    static let title3 = Font.system(size: 14, weight: .semibold)

    // MARK: - Body
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let callout = Font.system(size: 12, weight: .regular)
    static let subheadline = Font.system(size: 12, weight: .regular)

    // MARK: - Small
    static let footnote = Font.system(size: 11, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let caption2 = Font.system(size: 10, weight: .regular)

    // MARK: - Monospace (for file paths, speeds, etc.)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    // MARK: - Fixed sizes for specific UI elements
    static let badgeText = Font.system(size: 10, weight: .medium)
    static let statusText = Font.system(size: 11, weight: .medium)
}

extension View {
    func seeleLogo() -> some View {
        font(SeeleTypography.logo)
            .foregroundStyle(SeeleColors.textPrimary)
    }
    func seeleTitle() -> some View {
        font(SeeleTypography.title)
            .foregroundStyle(SeeleColors.textPrimary)
    }

    func seeleHeadline() -> some View {
        font(SeeleTypography.headline)
            .foregroundStyle(SeeleColors.textPrimary)
    }

    func seeleBody() -> some View {
        font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)
    }

    func seeleSecondary() -> some View {
        font(SeeleTypography.subheadline)
            .foregroundStyle(SeeleColors.textSecondary)
    }

    func seeleMono() -> some View {
        font(SeeleTypography.mono)
            .foregroundStyle(SeeleColors.textSecondary)
    }
}
