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

    // MARK: - Corner Radius
    static let cornerRadiusXS: CGFloat = 2
    static let cornerRadiusSmall: CGFloat = 4
    static let cornerRadius: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 12

    // MARK: - Component Heights
    static let rowHeight: CGFloat = 32
    static let inputHeight: CGFloat = 28
    static let buttonHeight: CGFloat = 28
    static let tabBarHeight: CGFloat = 36
    static let progressBarHeight: CGFloat = 4
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
        bottom: SeeleSpacing.listRowPadding,
        trailing: SeeleSpacing.lg
    )
}
