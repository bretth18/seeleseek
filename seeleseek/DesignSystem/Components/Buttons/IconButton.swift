import SwiftUI
import SeeleseekCore


struct IconButton: View {
    let icon: String
    /// Spoken name for the button. An icon-only button has no
    /// text, so the label is required.
    let label: String
    let size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        label: String,
        size: CGFloat = SeeleSpacing.iconSize,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
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
        .accessibilityLabel(label)
        .help(label)
    }
}

#Preview("Icon Buttons") {
    VStack(spacing: SeeleSpacing.lg) {
        HStack {
            IconButton(icon: "gear", label: "Settings") {}
            IconButton(icon: "magnifyingglass", label: "Search") {}
            IconButton(icon: "arrow.down.circle", label: "Download") {}
        }
    }
    .padding()
    .background(SeeleColors.background)
}
