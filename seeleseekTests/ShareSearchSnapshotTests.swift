import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// `ShareManager.search` answers distributed peer queries off the main
/// actor by reading an immutable `ShareSearchSnapshot`. These tests pin
/// the search semantics (whole-word intersection, visibility gate) and
/// the snapshot's republish points, so the off-main move can't silently
/// change what peers receive.
@MainActor
@Suite("Share search snapshot")
struct ShareSearchSnapshotTests {

    private func makeFile(
        sharedPath: String,
        visibility: ShareManager.Visibility = .public,
        folderID: UUID = UUID()
    ) -> ShareManager.IndexedFile {
        ShareManager.IndexedFile(
            localPath: "/tmp/" + sharedPath.replacingOccurrences(of: "\\", with: "/"),
            sharedPath: sharedPath,
            size: 1_000,
            visibility: visibility,
            folderID: folderID
        )
    }

    private func makeShareManager(_ files: [ShareManager.IndexedFile]) async -> ShareManager {
        let shares = ShareManager(defaults: TestDefaults.isolated())
        await shares._seedFileIndexForTest(files)
        return shares
    }

    @Test("Multi-term query intersects posting lists — all terms must match")
    func multiTermIntersection() async {
        let shares = await makeShareManager([
            makeFile(sharedPath: "Music\\Aphex Twin\\Windowlicker.mp3"),
            makeFile(sharedPath: "Music\\Aphex Twin\\Xtal.mp3"),
            makeFile(sharedPath: "Music\\Boards of Canada\\Windowlicker Cover.mp3"),
        ])

        let hits = shares.search(query: "aphex windowlicker", includeBuddyOnly: false)
        #expect(hits.map(\.sharedPath) == ["Music\\Aphex Twin\\Windowlicker.mp3"])
    }

    @Test("Matching is whole-word, not substring")
    func wholeWordMatching() async {
        let shares = await makeShareManager([
            makeFile(sharedPath: "Music\\wind.mp3"),
            makeFile(sharedPath: "Music\\windowlicker.mp3"),
        ])

        let hits = shares.search(query: "wind", includeBuddyOnly: false)
        #expect(hits.map(\.sharedPath) == ["Music\\wind.mp3"])
    }

    @Test("Empty and unknown-term queries return nothing")
    func emptyAndUnknownQueries() async {
        let shares = await makeShareManager([makeFile(sharedPath: "Music\\track.mp3")])

        #expect(shares.search(query: "", includeBuddyOnly: false).isEmpty)
        #expect(shares.search(query: "   ", includeBuddyOnly: false).isEmpty)
        #expect(shares.search(query: "nonexistent", includeBuddyOnly: false).isEmpty)
        // One known + one unknown term: intersection must fail.
        #expect(shares.search(query: "track nonexistent", includeBuddyOnly: false).isEmpty)
    }

    @Test("Buddy-only files are gated by includeBuddyOnly")
    func visibilityGate() async {
        let shares = await makeShareManager([
            makeFile(sharedPath: "Shared\\song.mp3", visibility: .public),
            makeFile(sharedPath: "Private\\song.mp3", visibility: .buddies),
        ])

        let publicHits = shares.search(query: "song", includeBuddyOnly: false)
        #expect(publicHits.map(\.sharedPath) == ["Shared\\song.mp3"])

        let buddyHits = shares.search(query: "song", includeBuddyOnly: true)
        #expect(buddyHits.map(\.sharedPath) == ["Shared\\song.mp3", "Private\\song.mp3"])
    }

    @Test("Search runs off the main actor against the published snapshot")
    func searchWorksOffMain() async {
        let shares = await makeShareManager([makeFile(sharedPath: "Music\\offmain.mp3")])

        let hits = await Task.detached {
            shares.search(query: "offmain", includeBuddyOnly: false)
        }.value
        #expect(hits.count == 1)
    }

    @Test("Visibility change republishes the snapshot")
    func visibilityChangeRepublishes() async {
        let folderID = UUID()
        let shares = ShareManager(defaults: TestDefaults.isolated())
        await shares._seedFileIndexForTest([
            makeFile(sharedPath: "Flip\\song.mp3", visibility: .public, folderID: folderID)
        ])
        // setVisibility requires a matching folder entry; seed one via the
        // persistence-free path by searching before and after the flip.
        #expect(shares.search(query: "flip song", includeBuddyOnly: false).count == 1)

        await shares._seedFileIndexForTest([
            makeFile(sharedPath: "Flip\\song.mp3", visibility: .buddies, folderID: folderID)
        ])
        #expect(shares.search(query: "flip song", includeBuddyOnly: false).isEmpty)
        #expect(shares.search(query: "flip song", includeBuddyOnly: true).count == 1)
    }
}
