import AppKit
import SwiftUI
import SeeleseekCore

/// Every token resolves per appearance, so one name serves the dark and
/// light themes. Which appearance applies is decided once, by the
/// `preferredColorScheme` at each scene root (`AppAppearance`).
enum SeeleColors {
    // MARK: - Backgrounds
    static let background = dynamic(light: 0xF4F4F5, dark: 0x0D0D0D)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x161616)
    static let surfaceSecondary = dynamic(light: 0xECECEE, dark: 0x1E1E1E)
    static let surfaceElevated = dynamic(light: 0xE1E1E4, dark: 0x262626)

    // MARK: - Accent (Pink/Magenta brand color)
    /// Same in both themes: it is the brand. On white it sits below the
    /// 4.5:1 text minimum, so it carries icons and fills, not body text.
    static let accent = Color(hex: 0xFF0B55)

    // MARK: - Text
    static let textPrimary = dynamic(light: 0x111111, dark: 0xF5F5F5)
    static let textSecondary = dynamic(light: 0x5C5C60, dark: 0x9A9A9A)
    /// Dim gray for metadata text. The standard values are below the
    /// WCAG 4.5:1 contrast minimum. This is intentional. When
    /// "Increase contrast" is on in System Settings, AppKit resolves
    /// the high-contrast appearance and a stronger gray applies. Those
    /// values have a contrast of more than 4.5:1 on all app surfaces.
    static let textTertiarySpec = ThemeSpec(
        light: 0x8A8A8E, dark: 0x5C5C5C,
        lightHighContrast: 0x58585C, darkHighContrast: 0x909090
    )
    static let textTertiary = textTertiarySpec.color
    static let textOnAccent = Color.white

    // MARK: - Status (Harmonized with accent)
    /// Used as label text ("Complete", "Failed"), so the light values are
    /// the darker steps of each hue to clear 4.5:1 on white.
    static let success = dynamic(light: 0x166534, dark: 0x22C55E)  // Green
    static let warning = dynamic(light: 0x92400E, dark: 0xF59E0B)  // Amber
    static let error = dynamic(light: 0xB91C1C, dark: 0xEF4444)    // Red (distinct from accent)
    static let info = dynamic(light: 0x1D4ED8, dark: 0x3B82F6)     // Blue

    // MARK: - Selection (Lower contrast for better readability)
    static let selectionBackground = Color(hex: 0xFF0B55).opacity(0.08)
    static let selectionBorder = Color(hex: 0xFF0B55).opacity(0.25)

    // MARK: - Borders & Dividers
    static let border = dynamic(light: 0xD9D9DD, dark: 0x2A2A2A)
    static let divider = dynamic(light: 0xE4E4E7, dark: 0x222222)

    // MARK: - Shadows
    /// Lighter in the light theme: a 0.3 black shadow on white reads as
    /// a smudge.
    static let shadowColor = shadow(lightAlpha: 0.08, darkAlpha: 0.15)
    static let shadowColorStrong = shadow(lightAlpha: 0.16, darkAlpha: 0.3)

    // MARK: - Opacity Levels
    /// Opacity presets for consistent styling. Usage: color.opacity(SeeleColors.alphaSubtle)
    static let alphaSubtle: Double = 0.05
    static let alphaLight: Double = 0.1
    static let alphaMedium: Double = 0.15
    static let alphaStrong: Double = 0.3
    static let alphaHalf: Double = 0.5

    // MARK: - File Type Palette
    /// Per-format palette used by file-type visualizations (e.g. the
    /// shares distribution chart + legend). Lifted out of
    /// `FileTypeDistribution.swift` so the brand-adjacent colors all
    /// live in one reviewable place. Use `fileType(for:)` for the
    /// dispatch rather than duplicating the switch elsewhere.
    /// Saturated mid-tones that hold up on both themes.
    enum FileType {
        static let audioMP3 = Color(hex: 0xE53935)
        static let audioFLAC = Color(hex: 0x8E24AA)
        static let audioOGG = Color(hex: 0x5E35B1)
        static let audioAAC = Color(hex: 0x3949AB)  // m4a, aac
        static let audioWAV = Color(hex: 0x1E88E5)
        static let video = Color(hex: 0x00ACC1)     // mp4, mkv
        static let image = Color(hex: 0x43A047)     // jpg, png
        static let archive = Color(hex: 0xFDD835)   // zip, rar
        static let unknown = Color(hex: 0x757575)
    }

    /// Palette dispatch for a file extension (lowercase). Falls back to
    /// `FileType.unknown` for anything unrecognized.
    static func fileType(for ext: String) -> Color {
        switch ext {
        case "mp3": return FileType.audioMP3
        case "flac": return FileType.audioFLAC
        case "ogg": return FileType.audioOGG
        case "m4a", "aac": return FileType.audioAAC
        case "wav": return FileType.audioWAV
        case "mp4", "mkv": return FileType.video
        case "jpg", "png": return FileType.image
        case "zip", "rar": return FileType.archive
        default: return FileType.unknown
        }
    }

    // MARK: - Dynamic resolution

    /// A color that picks its value when drawn, from the appearance of
    /// the view drawing it.
    static func dynamic(light: UInt, dark: UInt) -> Color {
        ThemeSpec(light: light, dark: dark).color
    }

    /// One token's value per appearance. High-contrast variants default
    /// to the standard value of the same theme. Kept as data so a test
    /// can read the high-contrast hexes: AppKit hands back the plain
    /// appearance for the high-contrast names unless Increase Contrast
    /// is on system-wide.
    struct ThemeSpec {
        let light: UInt
        let dark: UInt
        let lightHighContrast: UInt
        let darkHighContrast: UInt

        init(light: UInt, dark: UInt, lightHighContrast: UInt? = nil, darkHighContrast: UInt? = nil) {
            self.light = light
            self.dark = dark
            self.lightHighContrast = lightHighContrast ?? light
            self.darkHighContrast = darkHighContrast ?? dark
        }

        func hex(for theme: ResolvedTheme) -> UInt {
            switch theme {
            case .light: light
            case .lightHighContrast: lightHighContrast
            case .dark: dark
            case .darkHighContrast: darkHighContrast
            }
        }

        var color: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(hex: hex(for: SeeleColors.resolvedTheme(appearance)))
            })
        }
    }

    private static func shadow(lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch Self.resolvedTheme(appearance) {
            case .light, .lightHighContrast: NSColor.black.withAlphaComponent(lightAlpha)
            case .dark, .darkHighContrast: NSColor.black.withAlphaComponent(darkAlpha)
            }
        })
    }

    enum ResolvedTheme { case light, lightHighContrast, dark, darkHighContrast }

    static func resolvedTheme(_ appearance: NSAppearance) -> ResolvedTheme {
        switch appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
        ]) {
        case .aqua: .light
        case .accessibilityHighContrastAqua: .lightHighContrast
        case .accessibilityHighContrastDarkAqua: .darkHighContrast
        default: .dark
        }
    }
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

extension NSColor {
    convenience init(hex: UInt) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
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
