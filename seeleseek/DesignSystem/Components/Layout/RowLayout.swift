import SwiftUI

/// Column anchors shared by every peer-bearing list row (SearchResultRow,
/// TransferRow, HistoryRow). These are deliberately one set of constants
/// rather than per-feature copies: the whole point is that a user scanning
/// from Search to Transfers to History sees the username, the folder, and
/// the speed land at the same X. Three separate copies drifted apart once
/// already (the speed column was 82pt in one row and 84pt in another).
///
/// Feature-specific widths stay in the feature's own `*RowLayout` enum.
nonisolated enum RowLayout {
    /// Username sub-cell. Longer names tail-truncate; the fixed width is
    /// what keeps everything rendered *after* the username aligned.
    static let peerUsernameWidth: CGFloat = 96

    /// Outer peer cell — username sub-cell plus whatever the row puts
    /// beside it (peer speed, retry count) plus slack.
    static let peerCellWidth: CGFloat = 168

    /// Transfer-rate column. Sized for the longest value, "999.9 KB/s".
    static let speedColumnWidth: CGFloat = 84
}
