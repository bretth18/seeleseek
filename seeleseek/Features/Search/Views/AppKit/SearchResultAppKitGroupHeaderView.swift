import AppKit
import SeeleseekCore
import SwiftUI

/// Row-glyph badge container — flipped so `RowGlyphOrnament` placement
/// matches SwiftUI `.overlay(alignment: .bottomTrailing)`.
private final class SearchResultAppKitFlippedBadgeView: NSView {
    override var isFlipped: Bool { true }
}

final class SearchResultAppKitGroupHeaderView: NSTableCellView {
    static let cellIdentifier = NSUserInterfaceItemIdentifier("searchResult.appKit.groupHeader")

    private let rowBackground = NSView()
    private let selectionView = NSImageView()
    private let folderBadge = SearchResultAppKitFlippedBadgeView()
    private let folderIconView = NSImageView()
    private let chevronOrnament = SearchResultAppKitRowGlyphOrnament(frame: .zero)
    private let titleField = NSTextField(labelWithString: "")
    private let qualityBadge = SearchResultAppKitMetadataBadge(frame: .zero)
    private let userArrowView = NSImageView()
    private let userField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let downloadView = NSImageView()

    private var showsSelectionCheckbox = false
    private var isExpanded = false
    private var showsQuality = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        autoresizingMask = [.width, .height]

        rowBackground.wantsLayer = true
        rowBackground.layer?.backgroundColor = NSColor(SeeleColors.surface).cgColor

        folderBadge.wantsLayer = true
        folderBadge.layer?.cornerRadius = SeeleSpacing.radiusMD / 2
        folderBadge.layer?.backgroundColor = NSColor(SeeleColors.warning)
            .withAlphaComponent(SeeleColors.alphaMedium).cgColor

        selectionView.imageScaling = .scaleProportionallyUpOrDown
        selectionView.contentTintColor = NSColor(SeeleColors.accent)
        selectionView.isHidden = true

        folderIconView.imageScaling = .scaleProportionallyUpOrDown
        folderIconView.contentTintColor = NSColor(SeeleColors.warning)
        folderIconView.image = SearchResultSymbolCache.folder

        downloadView.imageScaling = .scaleProportionallyUpOrDown
        downloadView.contentTintColor = NSColor(SeeleColors.textSecondary)
        downloadView.image = SearchResultSymbolCache.download

        userArrowView.imageScaling = .scaleProportionallyUpOrDown
        userArrowView.contentTintColor = NSColor(SeeleColors.textTertiary)
        userArrowView.image = SearchResultSymbolCache.uploadArrow

        configureAppKitLabel(titleField, size: 13, color: .labelColor, middleTruncate: true)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        configureAppKitLabel(userField, size: 11, color: .secondaryLabelColor)
        configureAppKitLabel(summaryField, size: 10, color: .tertiaryLabelColor, mono: true)

        folderBadge.addSubview(folderIconView)
        folderBadge.addSubview(chevronOrnament)

        let views: [NSView] = [
            rowBackground, selectionView, folderBadge, titleField, qualityBadge,
            userArrowView, userField, summaryField, downloadView
        ]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
    }

    override var isFlipped: Bool { true }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layout()
    }

    override func layout() {
        super.layout()
        let b = bounds
        let pad = SearchResultAppKitLayout.horizontalPad
        let glyphSide = RowGlyph.size
        let top = SearchResultAppKitLayout.textBlockTop(in: b.height)
        let titleH = SearchResultAppKitLayout.titleLineHeight
        let lineH = SearchResultAppKitLayout.contextLineHeight
        let contextY = top + titleH + SearchResultAppKitLayout.lineGap

        rowBackground.frame = b

        let reservedTrailing = SearchResultAppKitLayout.reservedTrailingWidth(includesMetadata: false)
        var leading = pad

        if showsSelectionCheckbox {
            let checkboxSide = SeeleSpacing.iconSizeXL
            selectionView.frame = CGRect(
                x: leading,
                y: (b.height - checkboxSide) / 2,
                width: checkboxSide,
                height: checkboxSide
            )
            leading += checkboxSide + SeeleSpacing.sm
        }

        folderBadge.frame = CGRect(x: leading, y: (b.height - glyphSide) / 2, width: glyphSide, height: glyphSide)
        let iconSide = SeeleSpacing.iconSize
        folderIconView.frame = CGRect(
            x: (glyphSide - iconSide) / 2,
            y: (glyphSide - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )
        chevronOrnament.frame = SearchResultAppKitRowGlyphOrnament.frame(inGlyphOfSize: glyphSide)

        leading += glyphSide + SeeleSpacing.sm
        let textX = leading
        let textW = max(40, b.width - textX - reservedTrailing)

        SearchResultAppKitLayout.layoutTitleLine(
            titleField: titleField,
            qualityBadge: qualityBadge,
            showsQuality: showsQuality,
            textX: textX,
            textW: textW,
            top: top,
            titleH: titleH
        )

        SearchResultAppKitPeerCellLayout.layoutUsernameCell(
            arrowView: userArrowView,
            usernameField: userField,
            at: textX,
            contextY: contextY,
            lineH: lineH
        )
        summaryField.frame = CGRect(
            x: textX + RowLayout.peerUsernameWidth,
            y: contextY,
            width: max(0, textX + textW - textX - RowLayout.peerUsernameWidth),
            height: lineH
        )

        SearchResultAppKitLayout.layoutTrailingCluster(
            downloadView: downloadView,
            in: b,
            verticalCenter: b.height / 2
        )
    }

    func configure(
        model: SearchResultAppKitGroupDisplayModel,
        isExpanded: Bool,
        isSelectionMode: Bool,
        groupSelection: SearchState.GroupSelection
    ) {
        self.isExpanded = isExpanded
        showsSelectionCheckbox = isSelectionMode
        selectionView.isHidden = !isSelectionMode
        selectionView.image = SearchResultSymbolCache.groupSelectionSymbol(for: groupSelection)

        chevronOrnament.configure(
            image: SearchResultSymbolCache.chevronSmall,
            rotationDegrees: isExpanded ? 90 : 0
        )

        titleField.stringValue = model.displayName
        userField.stringValue = model.username
        summaryField.stringValue = model.fileCountText

        if let quality = model.qualityLabel {
            showsQuality = true
            qualityBadge.isHidden = false
            qualityBadge.configure(text: quality, color: model.qualityColor)
        } else {
            showsQuality = false
            qualityBadge.isHidden = true
        }

        needsLayout = true
    }
}
