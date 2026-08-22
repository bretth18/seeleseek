import Foundation
import SeeleseekCore

/// One peer's offering of a single folder — the unit people actually
/// download, which is why the group's primary action is "download folder".
///
/// Every aggregate is computed once, at construction, by
/// `SearchState.recomputeFilteredResults()`. Nothing here is derived in a
/// view body: results stream in continuously, and a 500-result search
/// regrouped per body evaluation is the exact shape of the render storms
/// this codebase has had to fix before.
struct SearchResultGroup: Identifiable, Hashable {
    /// Stable across result arrivals so groups never reshuffle or lose
    /// expansion state as more results land.
    let id: String
    let username: String
    let folderPath: String
    /// Already filtered and ordered by filename — the header's count is
    /// therefore always the count of what is actually shown.
    let results: [SearchResult]
    let totalSize: UInt64
    /// Shared format (and bitrate, when uniform) across every file, or nil
    /// when the folder is mixed.
    let commonQuality: String?

    var fileCount: Int { results.count }

    var isSingleFile: Bool { results.count == 1 }

    /// Last path component of `folderPath`.
    let displayName: String
    /// Precomputed: the header renders this every frame, and `formattedBytes`
    /// goes through a `FormatStyle` that costs ~19us warm per call.
    let formattedTotalSize: String

    /// The grouping key. Owned here so `SearchState.group(_:)` cannot derive
    /// it differently from `id` — if those two ever disagree, expansion state
    /// silently stops matching its group.
    static func key(username: String, folderPath: String) -> String {
        "\(username)\\\(folderPath)"
    }

    init(username: String, folderPath: String, results: [SearchResult]) {
        let sorted = results.sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
        self.init(username: username, folderPath: folderPath, presortedResults: sorted)
    }

    /// For incremental merges where `results` is already in natural filename order.
    init(username: String, folderPath: String, presortedResults: [SearchResult]) {
        self.id = Self.key(username: username, folderPath: folderPath)
        self.displayName = folderPath.split(separator: "\\").last.map(String.init) ?? folderPath
        self.username = username
        self.folderPath = folderPath
        self.results = presortedResults
        var total: UInt64 = 0
        for result in presortedResults { total += result.size }
        self.totalSize = total
        self.formattedTotalSize = total.formattedBytes
        self.commonQuality = Self.commonQuality(of: presortedResults)
    }

    /// Merges one streaming result without re-sorting the whole bucket.
    func appending(_ result: SearchResult) -> SearchResultGroup {
        var merged = results
        let insertIndex = merged.firstIndex {
            result.filename.localizedStandardCompare($0.filename) == .orderedAscending
        } ?? merged.count
        merged.insert(result, at: insertIndex)
        return SearchResultGroup(username: username, folderPath: folderPath, presortedResults: merged)
    }

    private static func commonQuality(of results: [SearchResult]) -> String? {
        guard let first = results.first else { return nil }

        // `fileExtension` re-splits `filename` on every access, so hold it.
        let ext = first.fileExtension
        guard !ext.isEmpty, results.allSatisfy({ $0.fileExtension == ext }) else { return nil }
        let format = ext.uppercased()

        // Bitrate qualifies a lossy format ("MP3 320" means something). For
        // lossless it varies per track and carries no quality signal, so
        // "FLAC 1000" is just noise.
        guard !first.isLossless else { return format }

        let bitrate = first.bitrate
        guard let bitrate, results.allSatisfy({ $0.bitrate == bitrate }) else { return format }
        return "\(format) \(bitrate)"
    }
}
