import SwiftUI

enum SeeleSpacing {
    // MARK: - Base Scale
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    // MARK: - Component Specific
    static let rowVertical: CGFloat = 6
    static let rowHorizontal: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let listRowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let tagSpacing: CGFloat = 6
    static let dividerSpacing: CGFloat = 1   // Gap for divider lines between items

    // MARK: - Icon Sizes
    static let iconSizeXS: CGFloat = 10
    static let iconSizeSmall: CGFloat = 14
    static let iconSize: CGFloat = 16
    static let iconSizeMedium: CGFloat = 20
    static let iconSizeLarge: CGFloat = 24
    static let iconSizeXL: CGFloat = 32
    static let iconSizeHero: CGFloat = 48    // For empty states

    // MARK: - Status Indicators
    static let statusDotSmall: CGFloat = 6
    static let statusDot: CGFloat = 8
    static let statusDotLarge: CGFloat = 10

    // MARK: - Corner Radius (Apple HIG aligned)
    // Use .continuous style for Apple's "squircle" corners

    /// 4pt - Tiny elements: progress bars, chart bars, very small badges
    static let radiusXS: CGFloat = 4

    /// 6pt - Small elements: tags, inline badges, small pills
    static let radiusSM: CGFloat = 6

    /// 8pt - Standard controls: buttons, text fields, list rows, menus
    static let radiusMD: CGFloat = 8

    /// 12pt - Cards, panels, popovers, grouped content
    static let radiusLG: CGFloat = 12

    /// 16pt - Sheets, modals, large containers
    static let radiusXL: CGFloat = 16

    // Legacy aliases (deprecated - use radius* instead)
    @available(*, deprecated, renamed: "radiusXS")
    static let cornerRadiusXS: CGFloat = 2
    @available(*, deprecated, renamed: "radiusXS")
    static let cornerRadiusSmall: CGFloat = 4
    @available(*, deprecated, renamed: "radiusSM")
    static let cornerRadius: CGFloat = 6
    @available(*, deprecated, renamed: "radiusMD")
    static let cornerRadiusMedium: CGFloat = 8
    @available(*, deprecated, renamed: "radiusLG")
    static let cornerRadiusLarge: CGFloat = 12

    // MARK: - Component Heights
    static let rowHeight: CGFloat = 32
    static let inputHeight: CGFloat = 28
    static let buttonHeight: CGFloat = 28
    static let tabBarHeight: CGFloat = 36
    static let progressBarHeight: CGFloat = 4
}

// MARK: - Continuous Corner Shape Helpers

extension RoundedRectangle {
    /// Creates a RoundedRectangle with Apple's continuous corner style (squircle)
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // Convenience initializers for common sizes
    static var cardShape: RoundedRectangle { .continuous(SeeleSpacing.radiusLG) }
    static var buttonShape: RoundedRectangle { .continuous(SeeleSpacing.radiusMD) }
    static var badgeShape: RoundedRectangle { .continuous(SeeleSpacing.radiusSM) }
    static var tinyShape: RoundedRectangle { .continuous(SeeleSpacing.radiusXS) }
}

extension EdgeInsets {
    static let seeleCard = EdgeInsets(
        top: SeeleSpacing.cardPadding,
        leading: SeeleSpacing.cardPadding,
        bottom: SeeleSpacing.cardPadding,
        trailing: SeeleSpacing.cardPadding
    )

    static let seeleListRow = EdgeInsets(
        top: SeeleSpacing.listRowPadding,
        leading: SeeleSpacing.lg,
        bottom: SeeleSpacing.lg,
        trailing: SeeleSpacing.lg
    )
}

// MARK: - View Extension for Continuous Corners

extension View {
    /// Clips view to a continuous corner rectangle (Apple's squircle style)
    func continuousCorners(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Standard card corner radius with continuous corners
    func cardCorners() -> some View {
        continuousCorners(SeeleSpacing.radiusLG)
    }

    /// Standard button/control corner radius with continuous corners
    func buttonCorners() -> some View {
        continuousCorners(SeeleSpacing.radiusMD)
    }
}
