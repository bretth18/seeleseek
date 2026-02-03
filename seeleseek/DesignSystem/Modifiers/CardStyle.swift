import SwiftUI

struct CardStyle: ViewModifier {
    let padding: EdgeInsets
    let cornerRadius: CGFloat

    init(
        padding: EdgeInsets = .seeleCard,
        cornerRadius: CGFloat = SeeleSpacing.cornerRadius
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .cardShadow()
    }
}

struct HoverStyle: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? SeeleColors.surfaceSecondary : .clear)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func cardStyle(
        padding: EdgeInsets = .seeleCard,
        cornerRadius: CGFloat = SeeleSpacing.cornerRadius
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }

    func hoverStyle() -> some View {
        modifier(HoverStyle())
    }
}

#Preview("Card Styles") {
    VStack(spacing: SeeleSpacing.lg) {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Card Title")
                .seeleHeadline()
            Text("Some secondary content goes here")
                .seeleSecondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()

        VStack(spacing: 0) {
            ForEach(0..<3) { index in
                HStack {
                    Text("List Item \(index + 1)")
                        .seeleBody()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .padding(.seeleListRow)
                .hoverStyle()

                if index < 2 {
                    Divider()
                        .background(SeeleColors.surfaceSecondary)
                }
            }
        }
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
    .padding()
    .background(SeeleColors.background)
}
