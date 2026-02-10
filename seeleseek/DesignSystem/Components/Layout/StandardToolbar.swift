import SwiftUI

/// Consistent toolbar for view headers
struct StandardToolbar<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder center: () -> Center = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            leading
            Spacer()
            center
            Spacer()
            trailing
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface.opacity(0.5))
    }
}

#Preview {
    StandardToolbar {
        Text("Leading")
    } center: {
        Text("Title")
            .font(SeeleTypography.headline)
    } trailing: {
        Button("Action") {}
    }
    .background(SeeleColors.background)
}
