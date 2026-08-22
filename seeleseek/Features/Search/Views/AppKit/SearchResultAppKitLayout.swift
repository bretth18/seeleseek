import AppKit
import SeeleseekCore
import SwiftUI

/// Column anchors for AppKit search rows — mirrors `SearchResultRow` /
/// `SearchResultGroupHeader` so metadata and action buttons land at the
/// same X as the SwiftUI list.
enum SearchResultAppKitLayout {
    static let horizontalPad = SeeleSpacing.lg
    static let titleLineHeight: CGFloat = 16
    static let contextLineHeight: CGFloat = 14
    static let lineGap = SeeleSpacing.xxs

    /// `StandardListRow` uses `.padding(.vertical, SeeleSpacing.md)` around the
    /// two-line block — 12 + 32 + 12 = 56.
    static let rowHeight: CGFloat = SeeleSpacing.md * 2 + titleLineHeight + lineGap + contextLineHeight
    /// One hairline, matching `SearchResultListItemView`'s bare `Divider()`.
    static let groupEndHeight: CGFloat = 1

    static let qualitySlotWidth = SearchResultRowLayout.qualityChipSlotWidth

    static let statColumnWidths: [CGFloat] = [
        SearchResultStatColumn.formatBitrate.width,
        SearchResultStatColumn.sampleBitDepth.width,
        SearchResultStatColumn.duration.width,
        SearchResultStatColumn.size.width
    ]

    static var metadataBlockWidth: CGFloat {
        let stats = statColumnWidths.reduce(0, +)
            + SeeleSpacing.xs * CGFloat(max(0, statColumnWidths.count - 1))
        return qualitySlotWidth + SeeleSpacing.sm + stats
    }

    static var trailingClusterWidth: CGFloat {
        SearchResultRowLayout.trailingClusterWidth
    }

    static var secondaryActionsWidth: CGFloat {
        RowLayout.secondaryActionsWidth(2)
    }

    /// `RowIconButton(isProminent:)` — 20pt glyph in a 32pt hit target.
    static var primaryGlyphSize: CGFloat {
        SeeleSpacing.iconSizeMedium
    }

    static var primaryHitTarget: CGFloat {
        SeeleSpacing.iconSizeXL
    }

    /// Space reserved on the trailing edge: metadata, gaps, action cluster, pad.
    static func reservedTrailingWidth(includesMetadata: Bool) -> CGFloat {
        horizontalPad + trailingClusterWidth + SeeleSpacing.sm
            + (includesMetadata ? metadataBlockWidth + SeeleSpacing.sm : 0)
    }

    static var textBlockHeight: CGFloat {
        titleLineHeight + lineGap + contextLineHeight
    }

    static func textBlockTop(in height: CGFloat) -> CGFloat {
        SeeleSpacing.md
    }

    static func measuredTextWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Title line: title hugs leading edge, badge sits right after it
    /// (SwiftUI `HStack` parity — not trailing-aligned within the flex slot).
    static func layoutTitleLine(
        titleField: NSTextField,
        qualityBadge: SearchResultAppKitMetadataBadge,
        showsQuality: Bool,
        textX: CGFloat,
        textW: CGFloat,
        top: CGFloat,
        titleH: CGFloat
    ) {
        let badgeSize = showsQuality ? qualityBadge.preferredContentSize : .zero
        let badgeGap = showsQuality ? SeeleSpacing.xs : 0
        let badgeW = showsQuality ? badgeSize.width : 0
        let availableForTitle = showsQuality ? max(0, textW - badgeW - badgeGap) : textW
        let titleFont = titleField.font ?? NSFont.systemFont(ofSize: 13)
        let naturalTitleW = measuredTextWidth(titleField.stringValue, font: titleFont)
        let titleFieldW = min(naturalTitleW, availableForTitle)

        titleField.frame = CGRect(x: textX, y: top, width: titleFieldW, height: titleH)

        guard showsQuality else { return }

        qualityBadge.frame = CGRect(
            x: textX + titleFieldW + badgeGap,
            y: top + (titleH - badgeSize.height) / 2,
            width: badgeW,
            height: badgeSize.height
        )
    }

    /// Lays out fixed-width metadata columns trailing-aligned within `blockRect`.
    static func layoutMetadataBlock(
        qualityBadge: SearchResultAppKitMetadataBadge,
        statFields: [NSTextField],
        availabilityField: NSTextField,
        in blockRect: NSRect,
        titleY: CGFloat,
        contextY: CGFloat
    ) {
        var x = blockRect.minX
        let lineH = contextLineHeight

        let badgeSize = qualityBadge.preferredContentSize
        let badgeW = max(badgeSize.width, 1)
        qualityBadge.frame = CGRect(
            x: x + qualitySlotWidth - badgeW,
            y: titleY + (titleLineHeight - badgeSize.height) / 2,
            width: badgeW,
            height: badgeSize.height
        )
        x += qualitySlotWidth + SeeleSpacing.sm

        for (field, width) in zip(statFields, statColumnWidths) {
            field.frame = CGRect(x: x, y: titleY, width: width, height: lineH)
            x += width + SeeleSpacing.xs
        }

        availabilityField.frame = CGRect(
            x: blockRect.minX,
            y: contextY,
            width: blockRect.width,
            height: lineH
        )
    }

    /// Primary download glyph centered in the trailing hit target column.
    static func layoutTrailingCluster(
        downloadView: NSView,
        in bounds: NSRect,
        verticalCenter: CGFloat
    ) {
        let hitTarget = primaryHitTarget
        let glyphSize = primaryGlyphSize
        let primaryX = bounds.maxX - horizontalPad - hitTarget
        downloadView.frame = CGRect(
            x: primaryX + (hitTarget - glyphSize) / 2,
            y: verticalCenter - glyphSize / 2,
            width: glyphSize,
            height: glyphSize
        )
    }
}
