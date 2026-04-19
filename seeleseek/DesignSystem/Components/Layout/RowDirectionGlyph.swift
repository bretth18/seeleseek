import SwiftUI

/// 32pt direction badge used at the leading edge of transfer and history
/// rows. Fill uses the caller's tint at `alphaMedium`; the glyph is a bold
/// up/down arrow tinted the same hue, or a progress spinner when the row
/// is mid-connection.
struct RowDirectionGlyph: View {
    enum Direction { case download, upload }

    let direction: Direction
    let tint: Color
    var isConnecting: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle.badgeShape
                .fill(tint.opacity(SeeleColors.alphaMedium))
                .frame(
                    width: SeeleSpacing.iconSizeXL,
                    height: SeeleSpacing.iconSizeXL
                )

            if isConnecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(SeeleSpacing.scaleSmall)
                    .tint(tint)
            } else {
                Image(systemName: direction == .download ? "arrow.down" : "arrow.up")
                    .font(.system(size: SeeleSpacing.iconSize, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
    }
}
