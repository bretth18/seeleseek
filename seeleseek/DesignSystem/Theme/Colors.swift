import SwiftUI

enum SeeleColors {
    // MARK: - Backgrounds
    static let background = Color(hex: 0x0D0D0D)
    static let surface = Color(hex: 0x161616)
    static let surfaceSecondary = Color(hex: 0x1E1E1E)
    static let surfaceElevated = Color(hex: 0x262626)

    // MARK: - Accent (Pink/Magenta brand color)
    static let accent = Color(hex: 0xFF0B55)
    static let accentMuted = Color(hex: 0xD90A48)
    static let accentSubtle = Color(hex: 0xFF0B55).opacity(0.12)

    // MARK: - Text
    static let textPrimary = Color(hex: 0xF5F5F5)
    static let textSecondary = Color(hex: 0x9A9A9A)
    static let textTertiary = Color(hex: 0x5C5C5C)
    static let textOnAccent = Color.white

    // MARK: - Status (Harmonized with accent)
    static let success = Color(hex: 0x22C55E)  // Green
    static let warning = Color(hex: 0xF59E0B)  // Amber
    static let error = Color(hex: 0xEF4444)    // Red (distinct from accent)
    static let info = Color(hex: 0x3B82F6)     // Blue

    // MARK: - Selection (Lower contrast for better readability)
    static let selectionBackground = Color(hex: 0xFF0B55).opacity(0.08)
    static let selectionBorder = Color(hex: 0xFF0B55).opacity(0.25)

    // MARK: - Borders & Dividers
    static let border = Color(hex: 0x2A2A2A)
    static let divider = Color(hex: 0x222222)
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
    static var seeleSurfaceElevated: Color { SeeleColors.surfaceElevated }
    static var seeleAccent: Color { SeeleColors.accent }
    static var seeleTextPrimary: Color { SeeleColors.textPrimary }
    static var seeleTextSecondary: Color { SeeleColors.textSecondary }
    static var seeleTextTertiary: Color { SeeleColors.textTertiary }
    static var seeleBorder: Color { SeeleColors.border }
    static var seeleDivider: Color { SeeleColors.divider }
}
