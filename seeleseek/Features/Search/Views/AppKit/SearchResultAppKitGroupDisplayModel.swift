import AppKit
import SeeleseekCore
import SwiftUI

/// Precomputed strings and colors for an AppKit group header row.
struct SearchResultAppKitGroupDisplayModel: Equatable {
    let groupID: String
    let displayName: String
    let username: String
    let fileCountText: String
    let formattedTotalSize: String
    let qualityLabel: String?
    let qualityColor: NSColor

    static func make(from group: SearchResultGroup) -> SearchResultAppKitGroupDisplayModel {
        SearchResultAppKitGroupDisplayModel(
            groupID: group.id,
            displayName: group.displayName,
            username: group.username,
            fileCountText: "\(group.fileCount) files · \(group.formattedTotalSize)",
            formattedTotalSize: group.formattedTotalSize,
            qualityLabel: group.commonQuality,
            qualityColor: NSColor(SeeleColors.success)
        )
    }
}
