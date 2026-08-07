import SwiftUI

/// Direction badge at the leading edge of transfer and history rows:
/// a bold up/down arrow, or a progress spinner while the row is
/// mid-connection.
struct RowDirectionGlyph: View {
    enum Direction { case download, upload }

    let direction: Direction
    let tint: Color
    var isConnecting: Bool = false

    var body: some View {
        if isConnecting {
            RowGlyphBadge(tint: tint) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(SeeleSpacing.scaleSmall)
                    .tint(tint)
            }
        } else {
            RowGlyph(
                systemName: direction == .download ? "arrow.down" : "arrow.up",
                tint: tint,
                weight: .bold
            )
        }
    }
}
