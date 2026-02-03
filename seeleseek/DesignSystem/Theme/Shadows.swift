import SwiftUI

enum SeeleShadows {
    static let card = Shadow(
        color: .black.opacity(0.3),
        radius: 8,
        x: 0,
        y: 4
    )

    static let elevated = Shadow(
        color: .black.opacity(0.4),
        radius: 16,
        x: 0,
        y: 8
    )

    static let subtle = Shadow(
        color: .black.opacity(0.2),
        radius: 4,
        x: 0,
        y: 2
    )
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func seeleShadow(_ shadow: Shadow) -> some View {
        self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }

    func cardShadow() -> some View {
        seeleShadow(SeeleShadows.card)
    }

    func elevatedShadow() -> some View {
        seeleShadow(SeeleShadows.elevated)
    }
}
