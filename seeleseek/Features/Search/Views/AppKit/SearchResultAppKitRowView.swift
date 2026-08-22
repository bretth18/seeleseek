import AppKit
import SeeleseekCore
import SwiftUI

protocol SearchResultAppKitRowConfiguring: AnyObject {
    var identifier: NSUserInterfaceItemIdentifier? { get set }
    func configure(
        model: SearchResultAppKitDisplayModel,
        isSelectionMode: Bool,
        isSelected: Bool,
        isNested: Bool
    )
}

/// Fixed-frame search row with cached symbols. Matches `SearchResultRow` column anchors.
final class SearchResultAppKitRowView: NSTableCellView, SearchResultAppKitRowConfiguring {
    static let cellIdentifier = NSUserInterfaceItemIdentifier("searchResult.appKit.cached")

    private let rowBackground = NSView()
    private let selectionBackground = NSView()
    private let nestedRail = NSView()
    private let selectionView = NSImageView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let userArrowView = NSImageView()
    private let userField = NSTextField(labelWithString: "")
    private let speedField = NSTextField(labelWithString: "")
    private let folderIconView = NSImageView()
    private let folderField = NSTextField(labelWithString: "")
    private let qualityBadge = SearchResultAppKitMetadataBadge(frame: .zero)
    private let bitrateField = NSTextField(labelWithString: "")
    private let sampleField = NSTextField(labelWithString: "")
    private let durationField = NSTextField(labelWithString: "")
    private let sizeField = NSTextField(labelWithString: "")
    private let availabilityField = NSTextField(labelWithString: "")
    private let downloadView = NSImageView()

    private var showsSelectionCheckbox = false
    private var isNested = false

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

        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = SeeleSpacing.radiusMD / 2
        selectionBackground.layer?.borderWidth = SeeleSpacing.strokeThin
        selectionBackground.isHidden = true

        nestedRail.wantsLayer = true
        nestedRail.layer?.backgroundColor = NSColor(SeeleColors.warning).withAlphaComponent(0.55).cgColor
        nestedRail.isHidden = true

        selectionView.imageScaling = .scaleProportionallyUpOrDown
        selectionView.contentTintColor = NSColor(SeeleColors.accent)
        selectionView.isHidden = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        downloadView.imageScaling = .scaleProportionallyUpOrDown
        downloadView.contentTintColor = NSColor(SeeleColors.textSecondary)
        downloadView.image = SearchResultSymbolCache.download

        userArrowView.imageScaling = .scaleProportionallyUpOrDown
        userArrowView.contentTintColor = NSColor(SeeleColors.textTertiary)
        userArrowView.image = SearchResultSymbolCache.uploadArrow

        folderIconView.imageScaling = .scaleProportionallyUpOrDown
        folderIconView.contentTintColor = NSColor(SeeleColors.textTertiary)
        folderIconView.image = SearchResultSymbolCache.folderOutline

        configureAppKitLabel(titleField, size: 13, color: .labelColor, middleTruncate: true)
        configureAppKitLabel(userField, size: 11, color: .secondaryLabelColor)
        configureAppKitLabel(speedField, size: 10, color: .tertiaryLabelColor, mono: true)
        configureAppKitLabel(folderField, size: 10, color: .tertiaryLabelColor, mono: true, middleTruncate: true)
        configureAppKitLabel(bitrateField, size: 10, color: .secondaryLabelColor, mono: true, align: .right)
        configureAppKitLabel(sampleField, size: 10, color: .tertiaryLabelColor, mono: true, align: .right)
        configureAppKitLabel(durationField, size: 10, color: .tertiaryLabelColor, mono: true, align: .right)
        configureAppKitLabel(sizeField, size: 10, color: .tertiaryLabelColor, mono: true, align: .right)
        configureAppKitLabel(availabilityField, size: 11, color: .secondaryLabelColor, align: .right)

        let views: [NSView] = [
            rowBackground, selectionBackground, nestedRail, selectionView, iconView,
            titleField, userArrowView, userField, speedField, folderIconView, folderField,
            qualityBadge, bitrateField, sampleField, durationField, sizeField,
            availabilityField, downloadView
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
        let top = SearchResultAppKitLayout.textBlockTop(in: b.height)
        let titleH = SearchResultAppKitLayout.titleLineHeight
        let lineH = SearchResultAppKitLayout.contextLineHeight
        let contextY = top + titleH + SearchResultAppKitLayout.lineGap

        rowBackground.frame = b

        let reservedTrailing = SearchResultAppKitLayout.reservedTrailingWidth(includesMetadata: true)
        let metadataWidth = SearchResultAppKitLayout.metadataBlockWidth
        let metadataMinX = b.width - reservedTrailing + SeeleSpacing.sm

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

        let iconSide = SeeleSpacing.iconSizeXL
        iconView.frame = CGRect(x: leading, y: (b.height - iconSide) / 2, width: iconSide, height: iconSide)
        leading += iconSide + SeeleSpacing.sm

        let textX = leading
        let textW = max(40, metadataMinX - SeeleSpacing.sm - textX)
        titleField.frame = CGRect(x: textX, y: top, width: textW, height: titleH)

        if !userField.isHidden {
            SearchResultAppKitPeerCellLayout.layoutUsernameCell(
                arrowView: userArrowView,
                usernameField: userField,
                at: textX,
                contextY: contextY,
                lineH: lineH
            )
            speedField.frame = SearchResultAppKitPeerCellLayout.speedFrame(
                textX: textX,
                contextY: contextY,
                lineH: lineH
            )
            SearchResultAppKitPeerCellLayout.layoutFolderCell(
                iconView: folderIconView,
                pathField: folderField,
                textX: textX,
                textW: textW,
                contextY: contextY,
                lineH: lineH
            )
        }

        SearchResultAppKitLayout.layoutMetadataBlock(
            qualityBadge: qualityBadge,
            statFields: [bitrateField, sampleField, durationField, sizeField],
            availabilityField: availabilityField,
            in: CGRect(x: metadataMinX, y: 0, width: metadataWidth, height: b.height),
            titleY: top,
            contextY: contextY
        )

        SearchResultAppKitLayout.layoutTrailingCluster(
            downloadView: downloadView,
            in: b,
            verticalCenter: b.height / 2
        )

        selectionBackground.frame = b.insetBy(dx: SeeleSpacing.xs, dy: 1)

        if isNested {
            nestedRail.isHidden = false
            nestedRail.frame = CGRect(x: 0, y: 0, width: SeeleSpacing.strokeMedium, height: b.height)
        } else {
            nestedRail.isHidden = true
        }
    }

    func configure(
        model: SearchResultAppKitDisplayModel,
        isSelectionMode: Bool,
        isSelected: Bool,
        isNested: Bool = false
    ) {
        self.isNested = isNested
        showsSelectionCheckbox = isSelectionMode
        selectionView.isHidden = !isSelectionMode
        selectionView.image = isSelected ? SearchResultSymbolCache.selectionOn : SearchResultSymbolCache.selectionOff

        iconView.image = SearchResultSymbolCache.icon(named: model.glyphName)
        iconView.contentTintColor = model.glyphTint

        titleField.stringValue = model.displayFilename
        let hideContext = isNested
        userArrowView.isHidden = hideContext
        userField.isHidden = hideContext
        speedField.isHidden = hideContext
        folderIconView.isHidden = hideContext
        folderField.isHidden = hideContext

        if !hideContext {
            userField.stringValue = model.username
            speedField.stringValue = model.peerSpeedText
            speedField.textColor = model.peerSpeedColor
            folderField.stringValue = model.folderText
        }

        qualityBadge.configure(text: model.qualityLabel, color: model.qualityColor)
        bitrateField.stringValue = model.formatBitrateText.isEmpty ? "—" : model.formatBitrateText
        sampleField.stringValue = model.sampleBitDepthText.isEmpty ? "—" : model.sampleBitDepthText
        durationField.stringValue = model.durationText.isEmpty ? "—" : model.durationText
        sizeField.stringValue = model.sizeText
        availabilityField.stringValue = model.availabilityText
        availabilityField.textColor = model.availabilityColor

        if isSelected {
            selectionBackground.isHidden = false
            selectionBackground.layer?.backgroundColor = NSColor(SeeleColors.selectionBackground).cgColor
            selectionBackground.layer?.borderColor = NSColor(SeeleColors.selectionBorder).cgColor
        } else {
            selectionBackground.isHidden = true
        }

        needsLayout = true
    }
}

func configureAppKitLabel(
    _ field: NSTextField,
    size: CGFloat,
    color: NSColor,
    mono: Bool = false,
    align: NSTextAlignment = .left,
    middleTruncate: Bool = false
) {
    field.isEditable = false
    field.isBordered = false
    field.drawsBackground = false
    field.font = mono
        ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        : NSFont.systemFont(ofSize: size, weight: .regular)
    field.textColor = color
    field.alignment = align
    field.lineBreakMode = middleTruncate ? .byTruncatingMiddle : .byTruncatingTail
}
