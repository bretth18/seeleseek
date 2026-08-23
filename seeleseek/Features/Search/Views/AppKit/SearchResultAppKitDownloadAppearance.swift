import AppKit
import SeeleseekCore
import SwiftUI

/// Visual state for the search-row download control — mirrors `SearchResultRow`'s
/// `actionIcon` / `actionColor` / `actionHelp` / `isQueued`.
struct SearchResultAppKitDownloadAppearance {
    var image: NSImage
    var tint: NSColor
    var toolTip: String
    var accessibilityLabel: String
    var isEnabled: Bool

    static func make(
        status: Transfer.TransferStatus?,
        isIgnored: Bool
    ) -> SearchResultAppKitDownloadAppearance {
        SearchResultSymbolCache.warmIfNeeded()

        if isIgnored {
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.download,
                tint: NSColor(SeeleColors.textTertiary),
                toolTip: "User is ignored",
                accessibilityLabel: "User is ignored",
                isEnabled: false
            )
        }

        switch status {
        case .completed:
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.downloadComplete,
                tint: NSColor(SeeleColors.success),
                toolTip: "Already downloaded",
                accessibilityLabel: "Already downloaded",
                isEnabled: false
            )
        case .transferring:
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.downloadFilled,
                tint: NSColor(SeeleColors.accent),
                toolTip: "Downloading…",
                accessibilityLabel: "Downloading",
                isEnabled: false
            )
        case .queued, .waiting, .connecting:
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.downloadFilled,
                tint: NSColor(SeeleColors.accent),
                toolTip: "In queue",
                accessibilityLabel: "In queue",
                isEnabled: false
            )
        case .failed, .cancelled:
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.downloadRetry,
                tint: NSColor(SeeleColors.warning),
                toolTip: "Retry download",
                accessibilityLabel: "Retry download",
                isEnabled: true
            )
        case nil:
            return SearchResultAppKitDownloadAppearance(
                image: SearchResultSymbolCache.download,
                tint: NSColor(SeeleColors.textSecondary),
                toolTip: "Download",
                accessibilityLabel: "Download",
                isEnabled: true
            )
        }
    }
}
