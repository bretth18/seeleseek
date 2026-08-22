import AppKit

/// Pre-warmed SF Symbol images for search result rows. Rasterizes once at
/// table creation so cell reuse never hits `NSImage(systemSymbolName:)`.
enum SearchResultSymbolCache {
    private static var icons: [String: NSImage] = [:]
    private static var chevronImage: NSImage?
    private static var downloadImage: NSImage?
    private static var selectionOnImage: NSImage?
    private static var selectionOffImage: NSImage?
    private static var folderImage: NSImage?
    private static var folderOutlineImage: NSImage?
    private static var uploadArrowImage: NSImage?
    private static var chevronSmallImage: NSImage?
    private static var groupSelectionNoneImage: NSImage?
    private static var groupSelectionPartialImage: NSImage?
    private static var groupSelectionAllImage: NSImage?
    private static var warmed = false

    static let fileGlyphNames = [
        "waveform",
        "music.note",
        "photo",
        "video",
        "doc",
    ]

    static var folder: NSImage {
        warmIfNeeded()
        return folderImage!
    }

    static var folderOutline: NSImage {
        warmIfNeeded()
        return folderOutlineImage!
    }

    static var uploadArrow: NSImage {
        warmIfNeeded()
        return uploadArrowImage!
    }

    static var chevronSmall: NSImage {
        warmIfNeeded()
        return chevronSmallImage!
    }

    static func groupSelectionSymbol(for state: SearchState.GroupSelection) -> NSImage {
        warmIfNeeded()
        switch state {
        case .none: return groupSelectionNoneImage!
        case .partial: return groupSelectionPartialImage!
        case .all: return groupSelectionAllImage!
        }
    }

    static var chevron: NSImage {
        warmIfNeeded()
        return chevronImage!
    }

    static var download: NSImage {
        warmIfNeeded()
        return downloadImage!
    }

    static var selectionOn: NSImage {
        warmIfNeeded()
        return selectionOnImage!
    }

    static var selectionOff: NSImage {
        warmIfNeeded()
        return selectionOffImage!
    }

    static func icon(named name: String) -> NSImage {
        warmIfNeeded()
        return icons[name] ?? icons["doc"]!
    }

    static func warmIfNeeded() {
        guard !warmed else { return }
        warmed = true

        let iconConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSize, weight: .medium)
        for name in fileGlyphNames {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
                  let configured = base.withSymbolConfiguration(iconConfig) else {
                continue
            }
            configured.isTemplate = true
            icons[name] = configured
        }

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSizeXS, weight: .semibold)
        if let base = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(chevronConfig) {
            configured.isTemplate = true
            chevronImage = configured
        }

        let downloadConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSizeMedium, weight: .semibold)
        if let base = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(downloadConfig) {
            configured.isTemplate = true
            downloadImage = configured
        }

        let selectionConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSize, weight: .regular)
        if let base = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(selectionConfig) {
            configured.isTemplate = true
            selectionOnImage = configured
        }
        if let base = NSImage(systemSymbolName: "circle", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(selectionConfig) {
            configured.isTemplate = true
            selectionOffImage = configured
            groupSelectionNoneImage = configured
        }
        if let base = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(selectionConfig) {
            configured.isTemplate = true
            groupSelectionPartialImage = configured
        }
        if let base = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(selectionConfig) {
            configured.isTemplate = true
            groupSelectionAllImage = configured
        }

        let folderConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSize, weight: .medium)
        if let base = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(folderConfig) {
            configured.isTemplate = true
            folderImage = configured
        }

        let folderOutlineConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSizeXS, weight: .regular)
        if let base = NSImage(systemSymbolName: "folder", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(folderOutlineConfig) {
            configured.isTemplate = true
            folderOutlineImage = configured
        }

        let uploadConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSizeXS, weight: .bold)
        if let base = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(uploadConfig) {
            configured.isTemplate = true
            uploadArrowImage = configured
        }

        let chevronSmallConfig = NSImage.SymbolConfiguration(pointSize: SeeleSpacing.iconSizeXXS, weight: .bold)
        if let base = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil),
           let configured = base.withSymbolConfiguration(chevronSmallConfig) {
            configured.isTemplate = true
            chevronSmallImage = configured
        }
    }
}
