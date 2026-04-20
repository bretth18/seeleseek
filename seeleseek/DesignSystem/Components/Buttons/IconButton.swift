import SwiftUI
import SeeleseekCore


struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        size: CGFloat = SeeleSpacing.iconSize,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(SeeleColors.textSecondary)
                .frame(width: size + SeeleSpacing.lg, height: size + SeeleSpacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Icon Buttons") {
    VStack(spacing: SeeleSpacing.lg) {
        HStack {
            IconButton(icon: "gear") {}
            IconButton(icon: "magnifyingglass") {}
            IconButton(icon: "arrow.down.circle") {}
        }
    }
    .padding()
    .background(SeeleColors.background)
}
