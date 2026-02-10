import SwiftUI

/// Consistent list row with hover support
struct StandardListRow<Content: View>: View {
    let content: Content
    @State private var isHovered = false

    init(@ViewBuilder content: () -> Content) {
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
