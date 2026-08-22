import AppKit
import SwiftUI

/// Thin divider closing an expanded folder group.
final class SearchResultAppKitGroupEndView: NSTableCellView {
    static let cellIdentifier = NSUserInterfaceItemIdentifier("searchResult.appKit.groupEnd")

    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.backgroundColor = NSColor(SeeleColors.surface).cgColor

        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(SeeleColors.surfaceSecondary).cgColor
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        divider.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }
}
