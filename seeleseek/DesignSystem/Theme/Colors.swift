import SwiftUI
import SeeleseekCore

enum SeeleColors {
    // MARK: - Backgrounds
    static let background = Color(hex: 0x0D0D0D)
    static let surface = Color(hex: 0x161616)
    static let surfaceSecondary = Color(hex: 0x1E1E1E)
    static let surfaceElevated = Color(hex: 0x262626)

    // MARK: - Accent (Pink/Magenta brand color)
    static let accent = Color(hex: 0xFF0B55)

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

    // MARK: - Shadows
    static let shadowColor = Color.black.opacity(0.15)
    static let shadowColorStrong = Color.black.opacity(0.3)

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
