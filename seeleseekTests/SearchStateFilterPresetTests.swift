import Testing
import Foundation
@testable import seeleseek
@testable import SeeleseekCore

@Suite("SearchState filter presets")
@MainActor
struct SearchStateFilterPresetTests {

    private func makeState(files: [String]) -> SearchState {
        let state = SearchState()
        state.searchQuery = "q"
        state.startSearch(token: 1)
        state.addResults(files.map { SearchResult(username: "u", filename: "f\\\($0)", size: 1) }, forToken: 1)
        state.markSearchComplete(token: 1)
        return state
    }

    @Test("A custom preset keeps only its extensions")
    func customPreset() {
        // Uppercase extension: Windows peers share "COVER.JPG" routinely.
        let state = makeState(files: ["01.mp3", "cover.jpg", "back.jpeg", "Folder.PNG", "notes.txt"])
        let artwork = SearchFilterPreset(name: "Artwork", extensions: FileTypes.image)
        state.filterMinBitrate = 320
        state.applyPreset(artwork)
        #expect(state.isPresetActive(artwork))
        #expect(state.filterMinBitrate == nil, "a preset replaces the audio-only constraints")
        #expect(Set(state.filteredResults.map(\.fileExtension)) == ["jpg", "jpeg", "png"])

        state.applyPreset(artwork)
        #expect(!state.hasActiveFilters)
        #expect(state.filteredResults.count == 5)
    }

    @Test("Stock presets stand in until settings are wired")
    func stockFallback() {
        let state = SearchState()
        #expect(state.filterPresets == SearchFilterPreset.defaults)
        #expect(state.isPresetActive(SearchFilterPreset(name: "Empty")), "an empty preset matches cleared filters, which is why the bar hides it")
    }

    @Test("A grouped chip toggles every spelling together")
    func groupedChip() {
        let state = makeState(files: ["cover.jpg", "back.jpeg", "folder.png"])
        state.toggleExtensions(["jpg", "jpeg"])
        #expect(state.filterExtensions == ["jpg", "jpeg"])
        #expect(state.filteredResults.count == 2)

        state.toggleExtensions(["png"])
        #expect(state.filteredResults.count == 3)

        state.toggleExtensions(["jpg", "jpeg"])
        #expect(state.filterExtensions == ["png"])
        #expect(state.filteredResults.map(\.fileExtension) == ["png"])
    }
}
