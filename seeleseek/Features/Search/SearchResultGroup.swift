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

    /// Single-file groups render as a plain row with no wrapper chrome, so
    /// a lone loose result looks exactly as it did before grouping existed.
    var isSingleFile: Bool { results.count == 1 }

    /// Last path component — full Soulseek paths are far too long for a header.
    var displayName: String {
        folderPath.split(separator: "\\").last.map(String.init) ?? folderPath
    }

    init(username: String, folderPath: String, results: [SearchResult]) {
        self.id = "\(username)\\\(folderPath)"
        self.username = username
        self.folderPath = folderPath
        // Natural ordering, so "02" sorts before "10" rather than after it.
        self.results = results.sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
        self.totalSize = results.reduce(0) { $0 + $1.size }
        self.commonQuality = Self.commonQuality(of: results)
    }

    private static func commonQuality(of results: [SearchResult]) -> String? {
        guard let first = results.first else { return nil }

        let ext = first.fileExtension
        guard results.allSatisfy({ $0.fileExtension == ext }), !ext.isEmpty else { return nil }
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
