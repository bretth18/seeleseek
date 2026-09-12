import Foundation
import Testing
@testable import seeleseek

@Suite("Search filter presets")
struct SearchFilterPresetTests {

    @Test("Extension text tolerates commas, dots, case and stray spaces")
    func parseExtensions() {
        #expect(SearchFilterPreset.parseExtensions("JPG, .jpeg  png,") == ["jpg", "jpeg", "png"])
        #expect(SearchFilterPreset.parseExtensions("  ").isEmpty)
    }

    @Test("Only a named preset with a constraint shows in the bar")
    func isComplete() {
        #expect(!SearchFilterPreset(name: "").isComplete)
        #expect(!SearchFilterPreset(name: "Nothing").isComplete)
        #expect(!SearchFilterPreset(name: "", extensions: ["mp3"]).isComplete)
        #expect(SearchFilterPreset(name: "Fonts", extensions: ["ttf", "otf"]).isComplete)
        #expect(SearchFilterPreset(name: "Hi bitrate", minBitrate: 320).isComplete)
    }

    @Test("Round-trips through JSON with identity intact")
    func roundTrip() throws {
        let presets = [
            SearchFilterPreset(name: "Video", extensions: ["mp4", "mkv"]),
            SearchFilterPreset(name: "Hi-Res", extensions: ["flac"], minSampleRate: 96_000, minBitDepth: 24),
        ]
        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([SearchFilterPreset].self, from: data)
        #expect(decoded == presets)
    }

    @Test("Stock presets are all complete")
    func defaultsComplete() {
        let names = SearchFilterPreset.defaults.map(\.name)
        let complete = SearchFilterPreset.defaults.allSatisfy(\.isComplete)
        #expect(names == ["MP3 320", "FLAC", "Lossless", "Hi-Res"])
        #expect(complete)
    }
}
