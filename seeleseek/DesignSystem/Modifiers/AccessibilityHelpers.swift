import SwiftUI

// Shared accessibility helpers for the design system.
// Combined elements on macOS expose no AX role, so each helper
// sets an explicit role trait.

extension View {
    /// Exposes a chart or graphic as one VoiceOver element.
    /// The modifier hides the visual children and speaks a name
    /// plus a data summary. A blind user gets the headline numbers
    /// without the visual.
    func accessibleChart(label: String, value: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }

    /// Marks a tab-style control for VoiceOver. Adds the button
    /// role and, when the tab is active, the selected state.
    /// Visual selection styles (tint, background) are not audible,
    /// so the trait is the only way a blind user can find the
    /// current tab.
    func accessibilityTab(isSelected: Bool) -> some View {
        self.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
