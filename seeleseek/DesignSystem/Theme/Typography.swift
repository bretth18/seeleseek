import SwiftUI

enum SeeleTypography {
    // MARK: - Headings
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
    static let title = Font.system(size: 28, weight: .bold, design: .default)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .default)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .default)

    // MARK: - Body
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)

    // MARK: - Small
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    static let caption2 = Font.system(size: 11, weight: .regular, design: .default)

    // MARK: - Monospace (for file paths, speeds, etc.)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

extension View {
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
