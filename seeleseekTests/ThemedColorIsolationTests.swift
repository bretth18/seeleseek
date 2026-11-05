import Testing
import AppKit
import SwiftUI
@testable import seeleseek

/// #117: SwiftUI resolves dynamic NSColors on its display-link queue. A
/// MainActor-isolated provider traps there, taking the whole test process down.
@Suite("ThemedColor isolation")
struct ThemedColorIsolationTests {

    @Test("dynamic provider resolves off the main thread")
    func resolvesOffMain() async {
        let color = NSColor(ThemedColor(light: 0x112233, dark: 0x445566).color)
        let resolved = await Task.detached {
            dispatchPrecondition(condition: .notOnQueue(.main))
            var out: NSColor?
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                out = color.usingColorSpace(.sRGB)
            }
            return out.map { Int(($0.redComponent * 255).rounded()) }
        }.value
        #expect(resolved == 0x44)
    }
}
