import SwiftUI
import SeeleseekCore

/// Consistent list row with hover support.
///
/// Hover is published to `content` via `\.isRowHovered`. Read it in the
/// smallest leaf that needs it: a `@State` flipped through `onHoverChanged`
/// re-evaluates the entire row on every enter/leave.
struct StandardListRow<Content: View>: View {
    let content: Content
    let onHoverChanged: ((Bool) -> Void)?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: () -> Content) {
        self.onHoverChanged = nil
        self.content = content()
    }

    init(onHoverChanged: ((Bool) -> Void)?, @ViewBuilder content: () -> Content) {
        self.onHoverChanged = onHoverChanged
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.md)
            .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
            .environment(\.isRowHovered, isHovered)
            .onHover { hovering in
                let animation: Animation? = reduceMotion
                    ? nil
                    : .easeInOut(duration: SeeleSpacing.animationFast)
                withAnimation(animation) {
                    isHovered = hovering
                }
                onHoverChanged?(hovering)
            }
    }
}

extension EnvironmentValues {
    /// True while the pointer is over the enclosing `StandardListRow`.
    @Entry var isRowHovered = false
}

#Preview {
    VStack(spacing: 0) {
        StandardListRow {
            HStack {
                Text("Row 1")
                Spacer()
                Text("Detail")
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
        StandardListRow {
            HStack {
                Text("Row 2")
                Spacer()
                Text("Detail")
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
    }
    .background(SeeleColors.background)
}

/// `help()` installs an AppKit tracking area per call, and live rows carry
/// several each. Only the hovered row can show a tooltip; only it pays for one.
private struct RowHelp: ViewModifier {
    @Environment(\.isRowHovered) private var isRowHovered
    let text: String

    func body(content: Content) -> some View {
        // Never branch around `content` itself: switching branches on hover
        // gives the control a new identity and tears it down under the cursor.
        content.background {
            if isRowHovered {
                Color.clear.help(text)
            }
        }
    }
}

extension View {
    /// `help()` that exists only while the enclosing `StandardListRow` is hovered.
    func rowHelp(_ text: String) -> some View {
        modifier(RowHelp(text: text))
    }
}
