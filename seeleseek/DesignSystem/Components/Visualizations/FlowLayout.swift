import SwiftUI

/// Flow layout for tag-style content that wraps to next line
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > (proposal.width ?? .infinity) {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (positions, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

#Preview {
    FlowLayout(spacing: 8) {
        ForEach(["Rock", "Jazz", "Electronic", "Classical", "Blues", "Hip-Hop", "Metal"], id: \.self) { tag in
            Text(tag)
                .font(SeeleTypography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SeeleColors.surfaceSecondary, in: Capsule())
        }
    }
    .frame(width: 300)
    .padding()
    .background(SeeleColors.background)
}
