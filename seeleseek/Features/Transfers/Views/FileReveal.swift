import Foundation
#if os(macOS)
import AppKit
#endif

/// Shared "show this file in Finder" helper. Used by TransferRow and
/// HistoryRow so the reveal call site stays one line and the `#if os(macOS)`
/// guard lives in one place.
enum FileReveal {
    static func inFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(
            url.path,
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
        #endif
    }
}
