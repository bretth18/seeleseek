import Testing
import SwiftUI
import AppKit
@testable import seeleseek

/// The leading badge is what makes rows line up across Search, Transfers,
/// History and grouped results. `RowGlyph` was extracted from three
/// independent hand-rolled copies, so these pin the size it must keep.
@Suite("Row glyph sizing")
@MainActor
struct RowGlyphTests {

    private func size<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test("RowGlyph is a 32pt square")
    func glyphSize() {
        let s = size(RowGlyph(systemName: "folder.fill", tint: .orange))
        #expect(s.width == SeeleSpacing.iconSizeXL)
        #expect(s.height == SeeleSpacing.iconSizeXL)
    }

    @Test("RowDirectionGlyph matches RowGlyph in both states")
    func directionGlyphMatches() {
        let expected = CGSize(width: RowGlyph.size, height: RowGlyph.size)
        #expect(size(RowDirectionGlyph(direction: .download, tint: .blue)) == expected)
        #expect(size(RowDirectionGlyph(direction: .upload, tint: .green)) == expected)
        // The connecting spinner must not resize the column.
        #expect(size(RowDirectionGlyph(direction: .download, tint: .blue, isConnecting: true)) == expected)
    }

    @Test("A corner ornament does not grow the glyph's footprint")
    func ornamentDoesNotResize() {
        let plain = size(RowGlyph(systemName: "waveform", tint: .green))
        let ornamented = size(
            RowGlyph(systemName: "waveform", tint: .green)
                .overlay(alignment: .bottomTrailing) {
                    RowGlyphOrnament(systemName: "lock.fill")
                }
        )
        #expect(plain == ornamented)
    }
}
