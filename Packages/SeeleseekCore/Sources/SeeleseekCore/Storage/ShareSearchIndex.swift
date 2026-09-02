import Foundation

/// Immutable snapshot of the share index used to answer peer search
/// queries. `ShareManager` republishes it after every index mutation;
/// `ShareManager.search` reads it through a `Mutex`, so query evaluation
/// can run on any executor without touching main-actor state. The copy is
/// cheap: both stored collections share storage with the manager's live
/// index via COW.
public struct ShareSearchSnapshot: Sendable {
    /// Inverted word index: lowercased token -> positions in `files`.
    let wordIndex: [String: [Int]]
    let files: [ShareManager.IndexedFile]

    static let empty = ShareSearchSnapshot(wordIndex: [:], files: [])

    /// Split into lowercased tokens on non-alphanumeric boundaries.
    /// Shared by index building (`ShareManager`) and query parsing so
    /// both sides agree.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// Inverted-index lookup: tokenize the query, fetch each term's
    /// posting list, and intersect starting from the smallest list.
    /// Matching is whole-word (canonical SoulSeek / Nicotine+ behavior),
    /// not substring-contains.
    ///
    /// `includeBuddyOnly` controls whether folders marked `.buddies` are
    /// visible to the requester. Callers resolve that flag from their
    /// knowledge of the requester (buddy-list membership) before calling.
    public func search(query: String, includeBuddyOnly: Bool) -> [ShareManager.IndexedFile] {
        let terms = Set(Self.tokenize(query))
        guard !terms.isEmpty else { return [] }

        // Every term must have a posting list, else no file can match.
        var lists: [[Int]] = []
        lists.reserveCapacity(terms.count)
        for term in terms {
            guard let list = wordIndex[term] else { return [] }
            lists.append(list)
        }
        lists.sort { $0.count < $1.count }

        var candidates = Set(lists[0])
        for list in lists.dropFirst() {
            candidates.formIntersection(list)
            if candidates.isEmpty { return [] }
        }

        return candidates.sorted().compactMap { position in
            let file = files[position]
            if !includeBuddyOnly && file.visibility == .buddies { return nil }
            return file
        }
    }
}
