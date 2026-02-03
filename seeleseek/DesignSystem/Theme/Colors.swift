import SwiftUI

enum SeeleColors {
    // MARK: - Backgrounds
    static let background = Color(hex: 0x0D0D0D)
    static let surface = Color(hex: 0x1A1A1A)
    static let surfaceSecondary = Color(hex: 0x242424)

    // MARK: - Accent
    static let accent = Color(hex: 0xE53935)
    static let accentMuted = Color(hex: 0xC62828)
    static let accentSubtle = Color(hex: 0xE53935).opacity(0.15)

    // MARK: - Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xA0A0A0)
    static let textTertiary = Color(hex: 0x666666)

    // MARK: - Status
    static let success = Color(hex: 0x4CAF50)
    static let warning = Color(hex: 0xFF9800)
    static let error = Color(hex: 0xF44336)
    static let info = Color(hex: 0x2196F3)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

extension ShapeStyle where Self == Color {
    static var seeleBackground: Color { SeeleColors.background }
    static var seeleSurface: Color { SeeleColors.surface }
    static var seeleSurfaceSecondary: Color { SeeleColors.surfaceSecondary }
    static var seeleAccent: Color { SeeleColors.accent }
    static var seeleTextPrimary: Color { SeeleColors.textPrimary }
    static var seeleTextSecondary: Color { SeeleColors.textSecondary }
    static var seeleTextTertiary: Color { SeeleColors.textTertiary }
}
