import AppKit
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
    /// Dim gray for metadata text. The standard value is below the
    /// WCAG 4.5:1 contrast minimum. This is intentional. When
    /// "Increase contrast" is on in System Settings, AppKit resolves
    /// the high-contrast appearance and a brighter gray applies. That
    /// value has a contrast of more than 4.5:1 on all app surfaces.
    static let textTertiary = Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
            .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua
        ])
        let hex: UInt = match == .accessibilityHighContrastDarkAqua ? 0x909090 : 0x5C5C5C
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    })
    static let textOnAccent = Color.white

    // MARK: - Status (Harmonized with accent)
    static let success = Color(hex: 0x22C55E)  // Green
    static let warning = Color(hex: 0xF59E0B)  // Amber
    static let error = Color(hex: 0xEF4444)    // Red (distinct from accent)
    static let info = Color(hex: 0x3B82F6)     // Blue

    // MARK: - Adaptive Status
    /// Status colors for the status-bar `NSMenu`, which always follows the
    /// *system* appearance and cannot be pinned the way the main window is
    /// (`.preferredColorScheme(.dark)`), so the hardcoded palette above does
    /// not apply there.
    ///
    /// Contrast is measured against the *effective* menu background, not an
    /// opaque one. A menu is vibrant: its surface is the material blended with
    /// whatever is behind it, so a light menu over dark wallpaper settles far
    /// below white, and a dark menu over light wallpaper rises well above its
    /// nominal gray. These pairs clear WCAG AA (4.5:1) across that whole
    /// blended range — roughly #C6C6C6 at the worst light end and #4A4A4A at
    /// the worst dark end.
    ///
    /// The light values are deliberately *not* pushed to the darkest shade that
    /// would pass. An earlier set chased headroom (success was #073B19, 7.5:1)
    /// and read as near-black: the status dot stopped looking green, so the
    /// color carried no meaning at a glance and only the text did. These sit at
    /// ~5.5:1 against the worst blended background instead — comfortably past
    /// AA with margin to spare, while keeping enough chroma to be identifiable
    /// as green/amber/red/blue. Hue matches each dark-mode counterpart so the
    /// two appearances read as the same palette at different lightness.
    ///
    /// If you retune these, check against #C6C6C6 rather than white. Verifying
    /// against opaque white is what produced the washed-out set before this
    /// one: it measured 7:1 on paper and failed in a real translucent menu.
    ///
    /// These are dynamic `NSColor`s rather than a `Color` picked from a
    /// `ColorScheme` sampled ahead of time. AppKit resolves them against
    /// whatever appearance is current when they are *drawn*, which is what the
    /// menu needs: the menu bar button can be dark (it tints to the wallpaper)
    /// while the menu dropping out of it is light, so inspecting the button's
    /// appearance picks the wrong side. Letting AppKit resolve also means a
    /// theme switch is picked up with no invalidation on our part.
    enum Adaptive {
        static let successNS = dynamic(light: 0x00521B, dark: 0x6EE7A0)
        static let warningNS = dynamic(light: 0x663C00, dark: 0xFCD34D)
        static let errorNS = dynamic(light: 0x8F0000, dark: 0xFCA5A5)
        static let infoNS = dynamic(light: 0x0B3BB5, dark: 0x93C5FD)

        /// Opaque stand-in for `NSColor.labelColor` in menu rows.
        ///
        /// `labelColor` is ~85% alpha, so anything that dilutes it further —
        /// AppKit's disabled-item dimming, a vibrant backdrop — compounds
        /// against an already-translucent ink. At full strength it measures
        /// 9.8:1 (light) and 7.0:1 (dark); halved it collapses to 2.8:1 and
        /// 3.0:1, well under AA. These values match how `labelColor` actually
        /// renders but cannot be thinned any further.
        static let labelPrimaryNS = dynamic(light: 0x1E1E1E, dark: 0xEDEDED)
        static let textTertiaryNS = dynamic(light: 0x3D3D3D, dark: 0xC8C8C8)

        /// A menu draws in a *vibrant* appearance, not a plain one. Matching
        /// against `[.aqua, .darkAqua]` alone makes `vibrantDark` fall through
        /// to the first entry — i.e. a dark menu would be painted with the
        /// light-mode ink. The vibrant and high-contrast names have to be in
        /// the candidate list for `bestMatch` to land on the right side; the
        /// same omission is what `textTertiary` above had to fix.
        private static func dynamic(light: UInt, dark: UInt) -> NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua,
                    .vibrantLight,
                    .accessibilityHighContrastAqua,
                    .accessibilityHighContrastVibrantLight,
                    .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark,
                ])
                let isDark = match == .darkAqua
                    || match == .vibrantDark
                    || match == .accessibilityHighContrastDarkAqua
                    || match == .accessibilityHighContrastVibrantDark
                return NSColor(hex: isDark ? dark : light)
            }
        }
    }

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

/// Only the adaptive `NSColor`s in this file need a hex initializer; the rest
/// of the app builds colors through SwiftUI's `Color(hex:)` above. Kept
/// `fileprivate` so it does not become a second, competing entry point on a
/// system type.
private extension NSColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
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
