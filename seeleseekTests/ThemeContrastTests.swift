import Testing
import AppKit
import SwiftUI
@testable import seeleseek

/// Every palette token is dynamic, so a light-mode regression can hide
/// behind a dark-mode screenshot. Resolve each token under both
/// appearances and hold the text/surface pairs to WCAG ratios.
@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {

    private static let surfaces: [(String, Color)] = [
        ("background", SeeleColors.background),
        ("surface", SeeleColors.surface),
        ("surfaceSecondary", SeeleColors.surfaceSecondary),
        ("surfaceElevated", SeeleColors.surfaceElevated),
    ]

    private static let appearances: [NSAppearance.Name] = [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
    ]

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

    private func contrast(_ a: Color, on b: Color, _ name: NSAppearance.Name) -> Double {
        let la = luminance(resolve(a, name)), lb = luminance(resolve(b, name))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func contrast(hex: UInt, on b: Color, _ name: NSAppearance.Name) -> Double {
        let la = luminance(NSColor(hex: hex)), lb = luminance(resolve(b, name))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func hex(_ c: NSColor) -> String {
        String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
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
        #expect(hex(resolve(SeeleColors.accent, .aqua)) == hex(resolve(SeeleColors.accent, .darkAqua)), "brand accent is fixed")
    }

    @Test("Primary and secondary text meet 4.5:1 on every surface in every appearance")
    func bodyText() {
        for name in Self.appearances {
            for (surface, bg) in Self.surfaces {
                #expect(contrast(SeeleColors.textPrimary, on: bg, name) >= 7,
                        "textPrimary on \(surface) in \(name.rawValue)")
                #expect(contrast(SeeleColors.textSecondary, on: bg, name) >= 4.5,
                        "textSecondary on \(surface) in \(name.rawValue)")
            }
        }
    }

    /// The high-contrast appearance names resolve to plain Aqua / Dark
    /// Aqua unless Increase Contrast is on system-wide, so those two
    /// values are checked from the spec against the resolved surfaces.
    @Test("Tertiary text is dim by default and passes 4.5:1 under Increase Contrast")
    func tertiaryText() {
        let spec = SeeleColors.textTertiarySpec
        for (surface, bg) in Self.surfaces {
            #expect(contrast(SeeleColors.textTertiary, on: bg, .aqua) >= 2.2, "tertiary on \(surface), light")
            #expect(contrast(SeeleColors.textTertiary, on: bg, .darkAqua) >= 2.2, "tertiary on \(surface), dark")
            #expect(contrast(hex: spec.lightHighContrast, on: bg, .aqua) >= 4.5,
                    "tertiary on \(surface), light high contrast")
            #expect(contrast(hex: spec.darkHighContrast, on: bg, .darkAqua) >= 4.5,
                    "tertiary on \(surface), dark high contrast")
        }
        #expect(Set([spec.light, spec.dark, spec.lightHighContrast, spec.darkHighContrast]).count == 4)
    }

    /// Status colors are small text ("Complete", "Failed") on rows, which
    /// sit on background/surface: 4.5:1. On the chip surfaces they are
    /// icons and badge fills, where the 3:1 component minimum applies.
    @Test("Status colors are readable as labels on every surface")
    func statusLabels() {
        let statuses: [(String, Color)] = [
            ("success", SeeleColors.success), ("warning", SeeleColors.warning),
            ("error", SeeleColors.error), ("info", SeeleColors.info),
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
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
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let border = contrast(SeeleColors.border, on: SeeleColors.surface, name)
            let divider = contrast(SeeleColors.divider, on: SeeleColors.surface, name)
            #expect(border >= 1.15 && border <= 2.5, "border on surface in \(name.rawValue): \(border)")
            #expect(divider >= 1.1 && divider <= 2.0, "divider on surface in \(name.rawValue): \(divider)")
        }
    }
}
