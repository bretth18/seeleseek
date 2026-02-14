import SwiftUI

/// Consistent list row with hover support
struct StandardListRow<Content: View>: View {
    let content: Content
    let onHoverChanged: ((Bool) -> Void)?
    @State private var isHovered = false

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
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hovering
                }
                onHoverChanged?(hovering)
            }
    }
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
