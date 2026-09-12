import Foundation
import Testing
@testable import seeleseek

@Suite("Release notes markdown")
struct ReleaseNotesMarkdownTests {
    typealias Block = ReleaseNotesMarkdown.Block

    @Test("A GitHub release body splits into headings, bullets and paragraphs")
    func blocks() {
        let body = """
        ## What's Changed
        * add bulk cancel by @bretth18 in https://github.com/bretth18/seeleseek/pull/100
        - second item

        Some words
        continued here.

        **Full Changelog**: https://github.com/bretth18/seeleseek/compare/v1.4.0...v1.5.0
        """
        #expect(ReleaseNotesMarkdown.blocks(body) == [
            .heading("What's Changed"),
            .bullet("add bulk cancel by @bretth18 in https://github.com/bretth18/seeleseek/pull/100"),
            .bullet("second item"),
            .paragraph("Some words continued here."),
            .paragraph("**Full Changelog**: https://github.com/bretth18/seeleseek/compare/v1.4.0...v1.5.0"),
        ])
    }

    @Test("Marker runs without a trailing space are plain text")
    func markersNeedSpace() {
        #expect(ReleaseNotesMarkdown.blocks("**bold** start\n---\n#hashtag") == [.paragraph("**bold** start --- #hashtag")])
        #expect(ReleaseNotesMarkdown.blocks("####### seven") == [.paragraph("####### seven")])
    }

    @Test("Bare URLs become links and GitHub PR links read as #n")
    func bareLinks() {
        let inline = ReleaseNotesMarkdown.inline("fix by @x in https://github.com/o/r/pull/96 and https://example.com/a")
        #expect(String(inline.characters) == "fix by @x in #96 and https://example.com/a")
        let links = inline.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://github.com/o/r/pull/96")!, URL(string: "https://example.com/a")!])
    }

    @Test("Markdown links keep their own text")
    func markdownLinks() {
        let inline = ReleaseNotesMarkdown.inline("see [the PR](https://github.com/o/r/pull/7)")
        #expect(String(inline.characters) == "see the PR")
        #expect(inline.runs.compactMap(\.link) == [URL(string: "https://github.com/o/r/pull/7")!])
    }

    @Test("Short labels only apply to GitHub PR and issue URLs")
    func shortLabel() {
        #expect(ReleaseNotesMarkdown.shortLabel(for: URL(string: "https://github.com/o/r/issues/12")!) == "#12")
        #expect(ReleaseNotesMarkdown.shortLabel(for: URL(string: "https://github.com/o/r/compare/v1...v2")!) == nil)
        #expect(ReleaseNotesMarkdown.shortLabel(for: URL(string: "https://gitlab.com/o/r/pull/12")!) == nil)
    }
}
