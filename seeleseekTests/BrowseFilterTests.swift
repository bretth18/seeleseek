import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

@Suite("Browse filter (debounced)")
struct BrowseFilterTests {

    private func makeState() -> BrowseState {
        let tree = SharedFile.buildTree(from: [
            SharedFile(filename: "@@music\\Milton\\Eu Sou O Rio\\01 needle.mp3", size: 1),
            SharedFile(filename: "@@music\\Milton\\Eu Sou O Rio\\02 other.mp3", size: 1),
            SharedFile(filename: "@@music\\Beatles\\Abbey Road\\03 track.mp3", size: 1),
        ])
        let state = BrowseState()
        state.browses = [UserShares(id: UUID(), username: "alice", folders: tree, isLoading: false)]
        state.selectedBrowseIndex = 0
        return state
    }

    /// The walk is debounced (250ms) and runs off-main; poll for results.
    private func waitForResults(_ state: BrowseState, timeout: Duration = .seconds(5)) async -> [FlatTreeItem] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while state.isFiltering, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return state.filteredFlatTree
    }

    @Test("Matches inside collapsed folders surface with their ancestor chain")
    func matchesIncludeAncestors() async {
        let state = makeState()
        state.filterQuery = "needle"

        let rows = await waitForResults(state)
        let names = rows.map(\.file.displayName)
        #expect(names == ["@@music", "Milton", "Eu Sou O Rio", "01 needle.mp3"],
                "match plus full ancestor chain, nothing else")
        let directoriesExpanded = rows.filter(\.file.isDirectory).allSatisfy(\.isExpanded)
        #expect(directoriesExpanded, "filter results render every ancestor directory expanded")
        #expect(state.isFiltering == false)
    }

    @Test("Visible rows carry expansion state as a plain value")
    func expansionCarriedOnFlatItems() {
        let state = makeState()
        let root = state.browses[0].folders[0]
        #expect(state.filteredFlatTree.map(\.isExpanded) == [false])

        state.toggleFolder(root.id)
        let rows = state.filteredFlatTree
        #expect(rows.map(\.file.displayName) == ["@@music", "Beatles", "Milton"])
        #expect(rows.map(\.isExpanded) == [true, false, false])
    }

    @Test("Clearing the query returns the visible tree immediately")
    func clearRestoresVisibleTree() async {
        let state = makeState()
        state.filterQuery = "needle"
        _ = await waitForResults(state)

        state.filterQuery = ""
        // Synchronous: no debounce wait on the clear path.
        let names = state.filteredFlatTree.map(\.file.displayName)
        #expect(names == ["@@music"], "collapsed root only — no filter active")
        #expect(state.isFiltering == false)
    }

    @Test("A superseded query never publishes over its replacement")
    func supersededQueryDoesNotPublish() async {
        let state = makeState()
        state.filterQuery = "milton"
        state.filterQuery = "abbey"

        let rows = await waitForResults(state)
        let names = rows.map(\.file.displayName)
        #expect(names.contains("Abbey Road"))
        #expect(!names.contains("Milton"), "results must reflect the latest query only")
    }

    @Test("No matches yields an empty list, not the full tree")
    func noMatchesIsEmpty() async {
        let state = makeState()
        state.filterQuery = "zzz-not-there"

        let rows = await waitForResults(state)
        #expect(rows.isEmpty)
    }
}

@Suite("Browse cache aggregates")
struct BrowseCacheAggregateTests {

    /// Aggregates must survive the cache round-trip; without them, totals
    /// walk the full tree inside UI bodies.
    @Test("Cache round-trip preserves aggregates without tree walks")
    func cacheRoundTripPreservesAggregates() {
        let tree = SharedFile.buildTree(from: [
            SharedFile(filename: "@@music\\A\\B\\1.mp3", size: 10),
            SharedFile(filename: "@@music\\A\\B\\2.mp3", size: 20),
            SharedFile(filename: "@@music\\C\\3.mp3", size: 5),
        ])
        #expect(tree[0].fileCount == 3, "precondition: buildTree aggregates")

        let records = SharedFileRecord.from(tree, userSharesId: UUID())
        let rebuilt = SharedFileRecord.toSharedFiles(from: records)
        #expect(rebuilt[0].fileCount == 3, "fileCount must survive the cache round-trip")

        let record = UserSharesRecord(
            id: UUID().uuidString, username: "alice",
            cachedAt: 0, totalFiles: 3, totalSize: 35
        )
        let shares = record.toUserShares(folders: rebuilt)
        #expect(shares.totalFiles == 3)
        #expect(shares.totalSize == 35)
    }

    @Test("Totals without cached stats come from root aggregates, not walks")
    func totalsFromRootAggregates() {
        let tree = SharedFile.buildTree(from: [
            SharedFile(filename: "a\\x.mp3", size: 7),
            SharedFile(filename: "b\\y.mp3", size: 9),
        ])
        let shares = UserShares(username: "u", folders: tree, isLoading: false)
        #expect(shares.totalFiles == 2)
        #expect(shares.totalSize == 16)
    }
}

@Suite("Shares visualization summaries")
struct SharesVisualizationSummaryTests {

    /// Pins summarize's nonisolated contract: the app target defaults to
    /// MainActor, and inferred @MainActor crashes the detached stats task.
    @Test("Summaries compute off the main actor")
    func summariesComputeOffMain() async {
        let files = [
            SharedFile(filename: "a\\b\\t.mp3", size: 10, bitrate: 320),
            SharedFile(filename: "a\\b\\u.flac", size: 30, bitrate: 900),
            SharedFile(filename: "a\\b\\v.jpg", size: 5),
        ]

        let (entries, total) = await Task.detached {
            FileTypeDistribution.summarize(files: files)
        }.value
        #expect(total == 45)
        #expect(entries.first?.type == "flac", "largest type by size sorts first")
        #expect(entries.count == 3)

        let buckets = await Task.detached {
            BitrateDistribution.summarize(files: files)
        }.value
        #expect(buckets.first(where: { $0.range == "320" })?.count == 1)
        #expect(buckets.first(where: { $0.range == "> 320" })?.count == 1)
        #expect(buckets.map(\.count).reduce(0, +) == 2, "file without bitrate lands in no bucket")
    }
}
