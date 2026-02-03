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
    static let cardPadding: CGFloat = 16
    static let listRowPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    static let iconSize: CGFloat = 20
    static let iconSizeSmall: CGFloat = 16
    static let iconSizeLarge: CGFloat = 28

    // MARK: - Corner Radius
    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadius: CGFloat = 10
    static let cornerRadiusLarge: CGFloat = 16
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
