import SwiftUI
import SeeleseekCore

/// Consistent list row with hover support.
///
/// Hover is published to `content` via `\.isRowHovered`. Read it in the
/// smallest leaf view that needs it, not in the row's own `body`: a
/// `@State` flipped through `onHoverChanged` re-evaluates the entire row
/// on every enter/leave, and with the cursor over a 500-row search list
/// that was the dominant hitch source in Instruments.
struct StandardListRow<Content: View>: View {
    let content: Content
    let onHoverChanged: ((Bool) -> Void)?
    @State private var isHovered = false
    /// Where the pointer actually is, including enters dropped during
    /// suppression. A reference box so per-row enter/exit churn during
    /// scroll never invalidates the row.
    @State private var pointer = PointerBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rowHoverSuppressed) private var hoverSuppressed

    private final class PointerBox { var inside = false }

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
                // While the list scrolls, rows stream under a stationary
                // cursor and AppKit fires enter/exit per row. Engaging
                // hover for each one re-animated and re-evaluated every
                // passing row — the dominant fast-scroll jank source.
                // Enters are dropped during scroll; exits always land so
                // no row is left stuck highlighted.
                pointer.inside = hovering
                if hovering && hoverSuppressed { return }
                setHovered(hovering)
            }
            .onChange(of: hoverSuppressed) { _, suppressed in
                // Replay an enter dropped during suppression: AppKit does
                // not re-send one for the row already under the cursor
                // when the scroll settles, so without this the row stays
                // visually cold (no highlight, hidden action cluster)
                // until the mouse physically moves.
                if !suppressed && pointer.inside != isHovered {
                    setHovered(pointer.inside)
                }
            }
    }

    private func setHovered(_ hovering: Bool) {
        let animation: Animation? = reduceMotion
            ? nil
            : .easeInOut(duration: SeeleSpacing.animationFast)
        withAnimation(animation) {
            isHovered = hovering
        }
        onHoverChanged?(hovering)
    }
}

extension EnvironmentValues {
    /// True while the pointer is over the enclosing `StandardListRow`.
    @Entry var isRowHovered = false

    /// Set by a scrolling container to stop rows from ENGAGING hover
    /// while content is in motion (exits still process). See the
    /// `onHover` note in `StandardListRow`.
    @Entry var rowHoverSuppressed = false
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

/// `help()` installs an AppKit tracking area per call. Rows carry several
/// tooltips each, and hundreds of rows stay live in a lazy stack, so the
/// tooltips alone were a measurable share of scroll layout cost. Only the
/// hovered row can show a tooltip; only it pays for one.
private struct RowHelp: ViewModifier {
    @Environment(\.isRowHovered) private var isRowHovered
    let text: String

    func body(content: Content) -> some View {
        // The conditional must never wrap `content` itself: an if/else
        // branch switch on hover gives the wrapped control a new
        // structural identity, tearing down the live button under the
        // cursor (lost clicks, cold hover state). The tooltip rides a
        // background so only that passive subtree changes on hover.
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
