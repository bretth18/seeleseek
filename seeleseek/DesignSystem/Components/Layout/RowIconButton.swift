import SwiftUI

/// Small square icon button sized for hover-revealed list-row action clusters.
/// Uses `buttonHeight` × `buttonHeight` hit target with an `iconSizeSmall`
/// glyph — the common shape for secondary actions across SearchResultRow,
/// TransferRow and HistoryRow.
struct RowIconButton: View {
    let systemName: String
    let help: String
    var tint: Color = SeeleColors.textSecondary
    var weight: Font.Weight = .regular
    /// Larger glyph + hit target for a row's PRIMARY action
    /// (download / resume / cancel), distinct from the secondary cluster.
    var isProminent: Bool = false
    let action: () -> Void

    private var glyphSize: CGFloat {
        isProminent ? SeeleSpacing.iconSizeMedium : SeeleSpacing.iconSizeSmall
    }

    private var hitTarget: CGFloat {
        isProminent ? SeeleSpacing.iconSizeXL : SeeleSpacing.buttonHeight
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: weight))
                .foregroundStyle(tint)
                .frame(width: hitTarget, height: hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
