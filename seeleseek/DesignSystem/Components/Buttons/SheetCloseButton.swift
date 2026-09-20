import SwiftUI

/// The xmark in a sheet's header. Escape triggers it.
struct SheetCloseButton: View {
    var label = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: SeeleSpacing.iconSizeMedium))
                .foregroundStyle(SeeleColors.textSecondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(label)
    }
}
