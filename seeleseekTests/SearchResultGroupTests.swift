import Testing
@testable import seeleseek
@testable import SeeleseekCore

@Suite("Search result grouping")
@MainActor
struct SearchResultGroupTests {

    private func result(
        _ user: String,
        _ path: String,
        size: UInt64 = 1_000,
        bitrate: UInt32? = nil,
        speed: UInt32 = 0
    ) -> SearchResult {
        SearchResult(
            username: user,
            filename: path,
            size: size,
            bitrate: bitrate,
            duration: nil,
            sampleRate: nil,
            bitDepth: nil,
            isVBR: false,
            freeSlots: true,
            uploadSpeed: speed,
            queueLength: 0,
            isPrivate: false
        )
    }

    @Test("Files from the same user and folder collapse into one group")
    func groupsByUserAndFolder() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [
                result("alice", "music\\Album\\02.flac", size: 200),
                result("alice", "music\\Album\\01.flac", size: 100)
            ]
        )
        #expect(group.fileCount == 2)
        #expect(group.totalSize == 300)
        #expect(group.displayName == "Album")
        #expect(!group.isSingleFile)
    }

    @Test("Group id is stable and distinguishes user from folder")
    func stableIdentity() {
        let a = SearchResultGroup(username: "alice", folderPath: "m\\A", results: [result("alice", "m\\A\\1.flac")])
        let b = SearchResultGroup(username: "bob", folderPath: "m\\A", results: [result("bob", "m\\A\\1.flac")])
        let c = SearchResultGroup(username: "alice", folderPath: "m\\B", results: [result("alice", "m\\B\\1.flac")])
        #expect(a.id != b.id)
        #expect(a.id != c.id)
        // Same inputs must produce the same id so expansion state survives
        // new results arriving.
        let again = SearchResultGroup(username: "alice", folderPath: "m\\A", results: [result("alice", "m\\A\\1.flac")])
        #expect(a.id == again.id)
    }

    @Test("Files sort naturally, so 02 precedes 10")
    func naturalOrdering() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "m\\A",
            results: [
                result("alice", "m\\A\\10 - Ten.flac"),
                result("alice", "m\\A\\02 - Two.flac"),
                result("alice", "m\\A\\01 - One.flac")
            ]
        )
        #expect(group.results.map(\.displayFilename) == ["01 - One.flac", "02 - Two.flac", "10 - Ten.flac"])
    }

    @Test("Common quality is the shared format, with bitrate only when uniform")
    func commonQuality() {
        let uniform = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.mp3", bitrate: 320),
            result("a", "f\\2.mp3", bitrate: 320)
        ])
        #expect(uniform.commonQuality == "MP3 320")

        // Lossless never shows a bitrate — it varies per track and "FLAC 1000"
        // reads as noise rather than quality.
        let uniformLossless = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.flac", bitrate: 1000),
            result("a", "f\\2.flac", bitrate: 1000)
        ])
        #expect(uniformLossless.commonQuality == "FLAC")

        let mixedBitrate = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.flac", bitrate: 900),
            result("a", "f\\2.flac", bitrate: 1000)
        ])
        #expect(mixedBitrate.commonQuality == "FLAC")

        let mixedLossyBitrate = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.mp3", bitrate: 192),
            result("a", "f\\2.mp3", bitrate: 320)
        ])
        #expect(mixedLossyBitrate.commonQuality == "MP3")

        let mixedFormat = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.flac"),
            result("a", "f\\2.mp3")
        ])
        #expect(mixedFormat.commonQuality == nil)
    }

    @Test("Single-file groups are flagged so they render without header chrome")
    func singleFile() {
        let group = SearchResultGroup(username: "a", folderPath: "f", results: [result("a", "f\\1.flac")])
        #expect(group.isSingleFile)
    }

    @Test("Expansion: multi-file groups start collapsed, single-file always open")
    func expansion() {
        let state = SearchState()
        let multi = SearchResultGroup(username: "a", folderPath: "f", results: [
            result("a", "f\\1.flac"), result("a", "f\\2.flac")
        ])
        let single = SearchResultGroup(username: "a", folderPath: "g", results: [result("a", "g\\1.flac")])

        #expect(!state.isExpanded(multi))
        #expect(state.isExpanded(single))

        state.toggleExpansion(multi)
        #expect(state.isExpanded(multi))
        state.toggleExpansion(multi)
        #expect(!state.isExpanded(multi))

        // Single-file groups have no header to toggle.
        state.toggleExpansion(single)
        #expect(state.isExpanded(single))
    }

    @Test("Group selection is tri-state and completes a partial selection")
    func groupSelection() {
        let state = SearchState()
        let a = result("a", "f\\1.flac")
        let b = result("a", "f\\2.flac")
        let group = SearchResultGroup(username: "a", folderPath: "f", results: [a, b])

        #expect(state.selectionState(of: group) == .none)

        state.toggleSelection(a.id)
        #expect(state.selectionState(of: group) == .partial)

        // Partial -> all, rather than clearing.
        state.toggleSelection(of: group)
        #expect(state.selectionState(of: group) == .all)

        state.toggleSelection(of: group)
        #expect(state.selectionState(of: group) == .none)
    }
}
