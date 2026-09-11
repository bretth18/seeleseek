import AppKit
import SwiftUI

/// A color with a value per appearance, resolved when drawn.
struct ThemedColor {
    enum Theme {
        case light
        case lightHighContrast
        case dark
        case darkHighContrast

        init(_ appearance: NSAppearance) {
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
            ]) {
            case .aqua: self = .light
            case .accessibilityHighContrastAqua: self = .lightHighContrast
            case .accessibilityHighContrastDarkAqua: self = .darkHighContrast
            default: self = .dark
            }
        }
    }

    let light: UInt
    let dark: UInt
    let lightHighContrast: UInt
    let darkHighContrast: UInt
    let lightAlpha: CGFloat
    let darkAlpha: CGFloat

    init(
        light: UInt,
        dark: UInt,
        lightHighContrast: UInt? = nil,
        darkHighContrast: UInt? = nil,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) {
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast ?? light
        self.darkHighContrast = darkHighContrast ?? dark
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
    }

    func hex(for theme: Theme) -> UInt {
        switch theme {
        case .light: light
        case .lightHighContrast: lightHighContrast
        case .dark: dark
        case .darkHighContrast: darkHighContrast
        }
    }

    func alpha(for theme: Theme) -> CGFloat {
        switch theme {
        case .light, .lightHighContrast: lightAlpha
        case .dark, .darkHighContrast: darkAlpha
        }
    }

    var color: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let theme = Theme(appearance)
            return NSColor(hex: hex(for: theme), alpha: alpha(for: theme))
        })
    }
}

extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
