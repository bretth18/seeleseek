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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: SeeleSpacing.iconSizeSmall, weight: weight))
                .foregroundStyle(tint)
                .frame(
                    width: SeeleSpacing.buttonHeight,
                    height: SeeleSpacing.buttonHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
