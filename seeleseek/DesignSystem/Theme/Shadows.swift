import SwiftUI
import SeeleseekCore

enum SeeleShadows {
    static let card = Shadow(
        color: ThemedColor(light: 0x000000, dark: 0x000000, lightAlpha: 0.16, darkAlpha: 0.3).color,
        radius: 8,
        x: 0,
        y: 4
    )

    static let elevated = Shadow(
        color: ThemedColor(light: 0x000000, dark: 0x000000, lightAlpha: 0.2, darkAlpha: 0.4).color,
        radius: 16,
        x: 0,
        y: 8
    )

    static let subtle = Shadow(
        color: ThemedColor(light: 0x000000, dark: 0x000000, lightAlpha: 0.1, darkAlpha: 0.2).color,
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
