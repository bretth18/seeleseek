import Testing
import AppKit
import SwiftUI
@testable import seeleseek

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
