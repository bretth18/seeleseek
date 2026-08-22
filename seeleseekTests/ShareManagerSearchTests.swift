import Testing
import Foundation
@testable import SeeleseekCore

/// Pins `ShareManager.search` semantics and its off-main contract: the
/// intersection runs on a detached utility task against an immutable
/// `SearchIndexTables` generation (same pattern as
/// `BrowseFilterTests.summariesComputeOffMain`).
@MainActor
@Suite("ShareManager search")
struct ShareManagerSearchTests {

    private func seed(_ files: [(path: String, visibility: ShareManager.Visibility)]) -> ShareManager {
        let shares = ShareManager(defaults: TestDefaults.isolated())
        let folderID = UUID()
        shares._seedFileIndexForTest(files.map { entry in
            ShareManager.IndexedFile(
                localPath: "/tmp/\(entry.path.replacingOccurrences(of: "\\", with: "/"))",
                sharedPath: entry.path,
                size: 1_000,
                visibility: entry.visibility,
                folderID: folderID
            )
        })
        return shares
    }

    @Test("Whole-word intersection matches indexed paths")
    func wholeWordMatch() async {
        let shares = seed([
            ("Music\\Pink Floyd\\Time.flac", .public),
            ("Music\\Radiohead\\Creep.mp3", .public),
        ])

        let hits = await shares.search(query: "pink floyd", includeBuddyOnly: false)
        #expect(hits.map(\.sharedPath) == ["Music\\Pink Floyd\\Time.flac"])
    }

    @Test("Buddy-only files stay hidden unless includeBuddyOnly")
    func buddyVisibilityGate() async {
        let shares = seed([
            ("Public\\Track.flac", .public),
            ("Private\\Secret.flac", .buddies),
        ])

        let publicOnly = await shares.search(query: "flac", includeBuddyOnly: false)
        #expect(publicOnly.map(\.sharedPath) == ["Public\\Track.flac"])

        let withBuddies = await shares.search(query: "flac", includeBuddyOnly: true)
        #expect(Set(withBuddies.map(\.sharedPath)) == [
            "Public\\Track.flac",
            "Private\\Secret.flac",
        ])
    }

    @Test("Empty / unknown terms return no hits")
    func emptyAndUnknown() async {
        let shares = seed([("Music\\Song.flac", .public)])
        #expect(await shares.search(query: "   ", includeBuddyOnly: false).isEmpty)
        #expect(await shares.search(query: "zzznomatch", includeBuddyOnly: false).isEmpty)
    }
}
