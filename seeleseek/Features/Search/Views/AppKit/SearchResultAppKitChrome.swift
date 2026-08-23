import AppKit
import SeeleseekCore
import SwiftUI

/// Colored pill matching `StandardMetadataBadge` (mono label + tinted fill).
final class SearchResultAppKitMetadataBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var displayText: String = ""
    private(set) var preferredContentSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = SeeleSpacing.radiusSM
        layer?.masksToBounds = true

        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = Self.badgeFont
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = false
        label.translatesAutoresizingMaskIntoConstraints = true
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: NSColor) {
        displayText = text
        label.stringValue = text
        label.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(SeeleColors.alphaMedium).cgColor
        preferredContentSize = Self.measureContentSize(for: label)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let padH = SeeleSpacing.xs
        let padV = SeeleSpacing.xxs
        label.frame = bounds.insetBy(dx: padH, dy: padV)
    }

    private static var badgeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    }

    /// Size from the live field — NSString metrics underestimate AppKit cell padding.
    private static func measureContentSize(for field: NSTextField) -> NSSize {
        guard !field.stringValue.isEmpty else {
            return NSSize(width: SeeleSpacing.xs * 2, height: 14 + SeeleSpacing.xxs * 2)
        }

        field.sizeToFit()
        let text = field.frame.size
        return NSSize(
            width: ceil(text.width) + SeeleSpacing.xs * 2 + 2,
            height: ceil(text.height) + SeeleSpacing.xxs * 2
        )
    }

    static func measuredSize(for text: String) -> NSSize {
        let probe = NSTextField(labelWithString: text)
        probe.font = badgeFont
        probe.lineBreakMode = .byClipping
        probe.cell?.usesSingleLineMode = true
        probe.cell?.wraps = false
        return measureContentSize(for: probe)
    }
}

/// Corner ornament on a row glyph — circle backing + small symbol (`RowGlyphOrnament`).
final class SearchResultAppKitRowGlyphOrnament: NSView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(SeeleColors.surface).cgColor
        layer?.cornerRadius = frameRect.width / 2

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = NSColor(SeeleColors.textPrimary)
        imageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static var preferredSize: CGFloat {
        SeeleSpacing.iconSizeXXS + SeeleSpacing.xxs * 2
    }

    /// Test seam — which symbol is currently shown.
    var imageForTesting: NSImage? { imageView.image }

    func configure(image: NSImage) {
        imageView.image = image
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        let inset = SeeleSpacing.xxs
        imageView.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    /// Bottom-trailing placement on a `RowGlyph`-sized badge, including the
    /// +xxs nudge that lets the ornament sit on the corner without resizing
    /// the glyph column (`RowGlyphTests.ornamentDoesNotResize`).
    static func frame(inGlyphOfSize glyphSide: CGFloat) -> CGRect {
        let size = preferredSize
        let offset = SeeleSpacing.xxs
        return CGRect(
            x: glyphSide - size + offset,
            y: glyphSide - size + offset,
            width: size,
            height: size
        )
    }
}

enum SearchResultAppKitPeerCellLayout {
    static let arrowIconSide = SeeleSpacing.iconSizeXS
    static let arrowGap = SeeleSpacing.xs
    static let folderIconSide = SeeleSpacing.iconSizeXS
    static let folderGap = SeeleSpacing.xs

    static func layoutUsernameCell(
        arrowView: NSView,
        usernameField: NSTextField,
        at textX: CGFloat,
        contextY: CGFloat,
        lineH: CGFloat
    ) {
        arrowView.frame = CGRect(
            x: textX,
            y: contextY + (lineH - arrowIconSide) / 2,
            width: arrowIconSide,
            height: arrowIconSide
        )
        let nameX = textX + arrowIconSide + arrowGap
        let nameW = max(0, RowLayout.peerUsernameWidth - arrowIconSide - arrowGap)
        usernameField.frame = CGRect(x: nameX, y: contextY, width: nameW, height: lineH)
        usernameField.cell?.usesSingleLineMode = true
        usernameField.cell?.lineBreakMode = .byTruncatingTail
    }

    static func speedFrame(textX: CGFloat, contextY: CGFloat, lineH: CGFloat) -> CGRect {
        CGRect(
            x: textX + RowLayout.peerUsernameWidth,
            y: contextY,
            width: RowLayout.peerCellWidth - RowLayout.peerUsernameWidth,
            height: lineH
        )
    }

    static func layoutFolderCell(
        iconView: NSView,
        pathField: NSTextField,
        textX: CGFloat,
        textW: CGFloat,
        contextY: CGFloat,
        lineH: CGFloat
    ) {
        let folderX = textX + RowLayout.peerCellWidth
        iconView.frame = CGRect(
            x: folderX,
            y: contextY + (lineH - folderIconSide) / 2,
            width: folderIconSide,
            height: folderIconSide
        )
        pathField.frame = CGRect(
            x: folderX + folderIconSide + folderGap,
            y: contextY,
            width: max(0, textX + textW - folderX - folderIconSide - folderGap),
            height: lineH
        )
    }
}
