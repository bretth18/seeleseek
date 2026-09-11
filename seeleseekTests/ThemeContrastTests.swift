import Testing
import AppKit
import SwiftUI
@testable import seeleseek

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {

    private static let surfaces: [(String, Color)] = [
        ("background", SeeleColors.background),
        ("surface", SeeleColors.surface),
        ("surfaceSecondary", SeeleColors.surfaceSecondary),
        ("surfaceElevated", SeeleColors.surfaceElevated),
    ]

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func resolve(_ color: Color, _ name: NSAppearance.Name) -> NSColor {
        var out = NSColor.black
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB)!
        }
        return out
    }

    private func luminance(_ c: NSColor) -> Double {
        func lin(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func contrast(_ a: Color, on b: Color, _ name: NSAppearance.Name) -> Double {
        contrast(resolve(a, name), resolve(b, name))
    }

    private func hex(_ c: NSColor) -> String {
        String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    /// The pre-light-mode palette, verbatim. Dark mode must not drift.
    @Test("Dark values are unchanged from the dark-only palette")
    func darkValuesUnchanged() {
        let expected: [(String, Color, String, CGFloat)] = [
            ("background", SeeleColors.background, "0D0D0D", 1),
            ("surface", SeeleColors.surface, "161616", 1),
            ("surfaceSecondary", SeeleColors.surfaceSecondary, "1E1E1E", 1),
            ("surfaceElevated", SeeleColors.surfaceElevated, "262626", 1),
            ("accent", SeeleColors.accent, "FF0B55", 1),
            ("textPrimary", SeeleColors.textPrimary, "F5F5F5", 1),
            ("textSecondary", SeeleColors.textSecondary, "9A9A9A", 1),
            ("textTertiary", SeeleColors.textTertiary, "5C5C5C", 1),
            ("textOnAccent", SeeleColors.textOnAccent, "FFFFFF", 1),
            ("success", SeeleColors.success, "22C55E", 1),
            ("warning", SeeleColors.warning, "F59E0B", 1),
            ("error", SeeleColors.error, "EF4444", 1),
            ("info", SeeleColors.info, "3B82F6", 1),
            ("selectionBackground", SeeleColors.selectionBackground, "FF0B55", 0.08),
            ("selectionBorder", SeeleColors.selectionBorder, "FF0B55", 0.25),
            ("border", SeeleColors.border, "2A2A2A", 1),
            ("divider", SeeleColors.divider, "222222", 1),
            ("shadowColor", SeeleColors.shadowColor, "000000", 0.15),
            ("shadowColorStrong", SeeleColors.shadowColorStrong, "000000", 0.3),
            ("shadow.card", SeeleShadows.card.color, "000000", 0.3),
            ("shadow.elevated", SeeleShadows.elevated.color, "000000", 0.4),
            ("shadow.subtle", SeeleShadows.subtle.color, "000000", 0.2),
        ]
        for (name, color, hexValue, alpha) in expected {
            let resolved = resolve(color, .darkAqua)
            #expect(hex(resolved) == hexValue, "\(name) hex")
            #expect(abs(resolved.alphaComponent - alpha) < 0.005, "\(name) alpha \(resolved.alphaComponent)")
        }
        #expect(SeeleColors.textTertiaryTheme.darkHighContrast == 0x909090)
    }

    @Test("Themed tokens resolve to different values per appearance")
    func tokensAreDynamic() {
        let themed: [(String, Color)] = Self.surfaces + [
            ("textPrimary", SeeleColors.textPrimary),
            ("textSecondary", SeeleColors.textSecondary),
            ("textTertiary", SeeleColors.textTertiary),
            ("success", SeeleColors.success),
            ("warning", SeeleColors.warning),
            ("error", SeeleColors.error),
            ("info", SeeleColors.info),
            ("border", SeeleColors.border),
            ("divider", SeeleColors.divider),
        ]
        for (name, color) in themed {
            #expect(hex(resolve(color, .aqua)) != hex(resolve(color, .darkAqua)), "\(name) is not dynamic")
        }
        #expect(hex(resolve(SeeleColors.accent, .aqua)) == hex(resolve(SeeleColors.accent, .darkAqua)))
    }

    @Test("Primary and secondary text meet WCAG on every surface")
    func bodyText() {
        for name in Self.appearances {
            for (surface, bg) in Self.surfaces {
                #expect(contrast(SeeleColors.textPrimary, on: bg, name) >= 7, "textPrimary on \(surface) in \(name.rawValue)")
                #expect(contrast(SeeleColors.textSecondary, on: bg, name) >= 4.5, "textSecondary on \(surface) in \(name.rawValue)")
            }
        }
    }

    // The high-contrast appearance names resolve to plain Aqua / Dark Aqua
    // unless Increase Contrast is on system-wide, so those values are read
    // from the theme definition rather than through NSAppearance.
    @Test("Tertiary text is dim by default and passes 4.5:1 under Increase Contrast")
    func tertiaryText() {
        let theme = SeeleColors.textTertiaryTheme
        for (surface, bg) in Self.surfaces {
            #expect(contrast(SeeleColors.textTertiary, on: bg, .aqua) >= 2.2, "tertiary on \(surface), light")
            #expect(contrast(SeeleColors.textTertiary, on: bg, .darkAqua) >= 2.2, "tertiary on \(surface), dark")
            #expect(contrast(NSColor(hex: theme.lightHighContrast), resolve(bg, .aqua)) >= 4.5,
                    "tertiary on \(surface), light high contrast")
            #expect(contrast(NSColor(hex: theme.darkHighContrast), resolve(bg, .darkAqua)) >= 4.5,
                    "tertiary on \(surface), dark high contrast")
        }
    }

    // Status colors are small label text on background/surface (4.5:1) and
    // icons or badge fills on the chip surfaces (3:1).
    @Test("Status colors are readable on every surface")
    func statusColors() {
        let statuses: [(String, Color)] = [
            ("success", SeeleColors.success), ("warning", SeeleColors.warning),
            ("error", SeeleColors.error), ("info", SeeleColors.info),
        ]
        for name in Self.appearances {
            for (surface, bg) in Self.surfaces {
                let minimum = ["background", "surface"].contains(surface) ? 4.5 : 3.0
                for (status, color) in statuses {
                    #expect(contrast(color, on: bg, name) >= minimum, "\(status) on \(surface) in \(name.rawValue)")
                }
            }
        }
    }

    @Test("Borders and dividers are visible but quiet against their surfaces")
    func borders() {
        for name in Self.appearances {
            let border = contrast(SeeleColors.border, on: SeeleColors.surface, name)
            let divider = contrast(SeeleColors.divider, on: SeeleColors.surface, name)
            #expect(border >= 1.15 && border <= 2.5, "border on surface in \(name.rawValue): \(border)")
            #expect(divider >= 1.1 && divider <= 2.0, "divider on surface in \(name.rawValue): \(divider)")
        }
    }
}
