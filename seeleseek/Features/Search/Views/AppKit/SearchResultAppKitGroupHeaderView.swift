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
    private let downloadButton = NSButton()
    private let folderProgress = NSProgressIndicator()
    private let folderFailedView = NSImageView()

    private var showsSelectionCheckbox = false
    private var isExpanded = false
    private var showsQuality = false
    private var group: SearchResultGroup?
    private var onRowActivate: (() -> Void)?
    private var onDownloadFolder: ((SearchResult) -> Void)?
    private var folderRequestState: AppState.FolderRequestState?

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

        downloadButton.isBordered = false
        downloadButton.imagePosition = .imageOnly
        downloadButton.imageScaling = .scaleProportionallyUpOrDown
        downloadButton.contentTintColor = NSColor(SeeleColors.textSecondary)
        downloadButton.image = SearchResultSymbolCache.download
        downloadButton.toolTip = "Download entire folder"
        downloadButton.setAccessibilityLabel("Download entire folder")
        downloadButton.target = self
        downloadButton.action = #selector(downloadClicked)

        folderProgress.style = .spinning
        folderProgress.controlSize = .small
        folderProgress.isDisplayedWhenStopped = false
        folderProgress.isHidden = true

        folderFailedView.imageScaling = .scaleProportionallyUpOrDown
        folderFailedView.contentTintColor = NSColor(SeeleColors.warning)
        folderFailedView.image = SearchResultSymbolCache.folderRequestFailed
        folderFailedView.isHidden = true

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
            userArrowView, userField, summaryField, downloadButton, folderProgress, folderFailedView
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

        let trailingFrame = SearchResultAppKitLayout.trailingClusterFrame(
            in: b,
            verticalCenter: b.height / 2
        )
        downloadButton.frame = trailingFrame
        folderProgress.frame = trailingFrame
        folderFailedView.frame = trailingFrame
    }

    func configure(
        model: SearchResultAppKitGroupDisplayModel,
        group: SearchResultGroup,
        isExpanded: Bool,
        isSelectionMode: Bool,
        groupSelection: SearchState.GroupSelection,
        folderRequestState: AppState.FolderRequestState?,
        onRowActivate: @escaping () -> Void,
        onDownloadFolder: @escaping (SearchResult) -> Void
    ) {
        self.group = group
        self.onRowActivate = onRowActivate
        self.onDownloadFolder = onDownloadFolder
        self.folderRequestState = folderRequestState
        self.isExpanded = isExpanded
        showsSelectionCheckbox = isSelectionMode
        selectionView.isHidden = !isSelectionMode
        selectionView.image = SearchResultSymbolCache.groupSelectionSymbol(for: groupSelection)

        // Swap symbols (same as Browse) — rotating `chevron.right` clipped
        // outside this ornament's rounded mask.
        chevronOrnament.configure(
            image: isExpanded
                ? SearchResultSymbolCache.chevronSmallDown
                : SearchResultSymbolCache.chevronSmall
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

        applyFolderRequestState(folderRequestState, username: group.username)

        needsLayout = true
    }

    private func applyFolderRequestState(_ state: AppState.FolderRequestState?, username: String) {
        switch state {
        case .fetching:
            downloadButton.isHidden = true
            folderFailedView.isHidden = true
            folderProgress.isHidden = false
            folderProgress.startAnimation(nil)
            folderProgress.toolTip = "Getting folder contents from \(username)..."
            folderProgress.setAccessibilityLabel("Getting folder contents from \(username)")
        case .failed(let reason):
            folderProgress.stopAnimation(nil)
            folderProgress.isHidden = true
            downloadButton.isHidden = true
            folderFailedView.isHidden = false
            folderFailedView.toolTip = reason
            folderFailedView.setAccessibilityLabel("Folder download failed. \(reason)")
        case nil:
            folderProgress.stopAnimation(nil)
            folderProgress.isHidden = true
            folderFailedView.isHidden = true
            downloadButton.isHidden = false
            downloadButton.image = SearchResultSymbolCache.download
            downloadButton.contentTintColor = NSColor(SeeleColors.textSecondary)
            downloadButton.toolTip = "Download entire folder"
            downloadButton.setAccessibilityLabel("Download entire folder")
            downloadButton.isEnabled = true
        }
    }

    @objc private func downloadClicked() {
        guard folderRequestState == nil, let representative = group?.results.first else { return }
        onDownloadFolder?(representative)
    }

    /// Expand / selection lives on the cell so labels cannot swallow the click
    /// and so we do not fight `NSTableView`'s `action` (double-toggle = no-op).
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if isPointInDownloadChrome(local) {
            super.mouseDown(with: event)
            return
        }
        onRowActivate?()
    }

    /// Keep the download control as its own hit target; everything else hits
    /// the cell so `mouseDown` above can expand.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === downloadButton
            || hit === folderProgress
            || hit === folderFailedView
            || hit.isDescendant(of: downloadButton) {
            return hit
        }
        return self
    }

    private func isPointInDownloadChrome(_ point: NSPoint) -> Bool {
        if !downloadButton.isHidden, downloadButton.frame.contains(point) { return true }
        if !folderProgress.isHidden, folderProgress.frame.contains(point) { return true }
        if !folderFailedView.isHidden, folderFailedView.frame.contains(point) { return true }
        return false
    }

    /// Test seam — fires the same path as a click on the download button.
    func performDownloadForTesting() {
        downloadClicked()
    }

    /// Test seam — fires the same path as a click on the row body.
    func performRowActivateForTesting() {
        onRowActivate?()
    }

    /// Test seam — disclosure symbol after the last `configure`.
    var chevronImageForTesting: NSImage? {
        chevronOrnament.imageForTesting
    }
}
