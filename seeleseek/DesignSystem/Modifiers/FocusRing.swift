import SwiftUI

extension View {
    /// Keyboard focus ring for a selected tab.
    ///
    /// One definition for every tab strip in the app — the tab bars each drew
    /// their own copy, and they had already drifted apart on corner radius and
    /// corner style before this was extracted.
    ///
    /// The ring is drawn by the *selected* tab rather than by the focusable
    /// container, so callers pass `isVisible: isSelected && isFocused`.
    func seeleTabFocusRing(
        _ isVisible: Bool,
        cornerRadius: CGFloat = SeeleSpacing.radiusMD
    ) -> some View {
        overlay {
            if isVisible {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 1)
            }
        }
    }
}
