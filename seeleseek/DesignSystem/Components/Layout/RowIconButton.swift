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

    // Not a SwiftUI `Button`: one per live row cost ~160 dropped frames
    // per 5s at 120Hz vs ~30 for a tap-gesture glyph, and `.focusable(false)`
    // / `.focusEffectDisabled()` do not help. Cost: no Tab focus on row actions.
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: glyphSize, weight: weight))
            .foregroundStyle(tint)
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .rowHelp(help)
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
