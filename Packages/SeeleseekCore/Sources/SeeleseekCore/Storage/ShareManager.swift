import Foundation
import os

/// Manages shared folders and file index for the SoulSeek client
@Observable
@MainActor
public final class ShareManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ShareManager")

    // MARK: - State

    public private(set) var sharedFolders: [SharedFolder] = []
    /// UI / upload-facing mirror of `searchTables.files`. Always replaced
    /// wholesale via `publishSearchTables` — never mutated in place — so
    /// concurrent searches holding an older `searchTables` generation do
    /// not force copy-on-write of the live index on the main actor.
    public private(set) var fileIndex: [IndexedFile] = []
    /// Immutable inverted-index + file table pair. Searches retain this
    /// value (a pointer to the arrays) across the detached intersection;
    /// rescans / appends publish a new pair instead of mutating the live
    /// buffers underneath in-flight queries.
    @ObservationIgnored private var searchTables = SearchIndexTables.empty
    public private(set) var isScanning = false
    public private(set) var scanProgress: Double = 0
    public private(set) var lastScanDate: Date?

    /// Caps concurrent detached search workers. Under heavy distributed
    /// relay traffic, one `Task.detached` per query can otherwise pile up
    /// unbounded utility work.
    private static let maxConcurrentSearches = 8
    private var searchInFlight = 0
    private var searchWaiters: [CheckedContinuation<Void, Never>] = []

    // Computed stats
    public var totalFiles: Int { fileIndex.count }
    public var totalFolders: Int { sharedFolders.count }
    /// Cached — recomputed whenever `fileIndex` changes. As a computed
    /// property this was an O(n) reduce on every access from an
    /// @Observable, re-run on each observation invalidation.
    public private(set) var totalSize: UInt64 = 0

    private func recomputeTotalSize() {
        totalSize = fileIndex.reduce(0) { $0 + $1.size }
    }

    /// Publish a new immutable generation of the search tables and mirror
    /// `files` into the observable `fileIndex` in one step.
    private func publishSearchTables(files: [IndexedFile], wordIndex: [String: [Int]]) {
        searchTables = SearchIndexTables(files: files, wordIndex: wordIndex)
        fileIndex = files
    }

    /// Edit `fileIndex` through a local copy so observers are notified once,
    /// not once per element. Writing `fileIndex[i]` in a loop fires the
    /// `@Observable` accessor on every iteration, and each notification
    /// invalidates every view reading the array — flipping visibility on a
    /// 10k-file share meant 10k invalidations. Same rule as
    /// `applyFolderStats(_:)`: one write per logical change.
    ///
    /// Word postings are unchanged for visibility rewrites (same paths /
    /// positions), so the prior generation's `wordIndex` is reused.
    private func mutateFileIndex(_ body: (inout [IndexedFile]) -> Void) {
        var updated = searchTables.files
        body(&updated)
        publishSearchTables(files: updated, wordIndex: searchTables.wordIndex)
    }

    private func acquireSearchSlot() async {
        if searchInFlight < Self.maxConcurrentSearches {
            searchInFlight += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            searchWaiters.append(continuation)
        }
    }

    private func releaseSearchSlot() {
        if searchWaiters.isEmpty {
            searchInFlight -= 1
        } else {
            // Hand the slot to the next waiter without changing inFlight.
            searchWaiters.removeFirst().resume()
        }
    }

    /// Share-folder paths whose security-scoped access has already been
    /// started this app run. Access must OUTLIVE any scan — uploads serve
    /// files from these folders at arbitrary later times — so it is never
    /// stopped after a scan; but re-starting on every rescan accumulated
    /// unbalanced access counts. One start per folder per run.
    private var securityScopedPaths: Set<String> = []

    /// Per-subscriber continuations. Vanilla `AsyncStream` is
    /// single-consumer, so we fan out yields ourselves.
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var countsChangedDebounce: Task<Void, Never>?

    /// Subscribe to share-count change events. Each call returns a fresh
    /// stream; cancelling the consuming Task tears down the continuation.
    public func countsChangesStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Coalesce rapid changes into a single trailing-edge yield (200 ms
    /// after the last change). Bulk operations like a 10-folder add would
    /// otherwise produce N broadcasts.
    private func notifyCountsChanged() {
        countsChangedDebounce?.cancel()
        countsChangedDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            // Snapshot — subscriber teardown can mutate the dict.
            let snapshot = Array(self.continuations.values)
            for continuation in snapshot {
                continuation.yield()
            }
        }
    }

    // MARK: - Types

    /// Who is allowed to see a shared folder when peers browse or search
    /// our shares. Enforced client-side — the Soulseek protocol carries
    /// "private" entries on the wire (see `SharedFileListResponse` and
    /// `FileSearchResponse`) but has no auth, so this is an honor-system
    /// affordance, same contract as Nicotine+.
    public enum Visibility: String, Codable, Sendable, Hashable {
        case `public`
        case buddies
    }

    public struct SharedFolder: Identifiable, Codable, Hashable {
        public let id: UUID
        public let path: String
        public var fileCount: Int
        public var totalSize: UInt64
        public var lastScanned: Date?
        public var visibility: Visibility

        public init(
            id: UUID = UUID(),
            path: String,
            fileCount: Int = 0,
            totalSize: UInt64 = 0,
            lastScanned: Date? = nil,
            visibility: Visibility = .public
        ) {
            self.id = id
            self.path = path
            self.fileCount = fileCount
            self.totalSize = totalSize
            self.lastScanned = lastScanned
            self.visibility = visibility
        }

        // Custom decoder so existing persisted JSON (no `visibility` key)
        // decodes with a `.public` default — Swift's synthesized Codable
        // does NOT apply property defaults on missing keys, it throws
        // `.keyNotFound`. Without this shim, every user would lose their
        // saved shared folders on first launch after this change.
        private enum CodingKeys: String, CodingKey {
            case id, path, fileCount, totalSize, lastScanned, visibility
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.path = try c.decode(String.self, forKey: .path)
            self.fileCount = try c.decode(Int.self, forKey: .fileCount)
            self.totalSize = try c.decode(UInt64.self, forKey: .totalSize)
            self.lastScanned = try c.decodeIfPresent(Date.self, forKey: .lastScanned)
            self.visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .public
        }

        /// `isDirectory` is supplied deliberately: without it,
        /// `URL(fileURLWithPath:)` stats the path to decide on a trailing
        /// slash, and this is read several times per row per render.
        public var displayName: String {
            URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        }
    }

    public struct IndexedFile: Identifiable, Sendable {
        public let id: UUID
        public let localPath: String      // Full local path
        public let sharedPath: String     // SoulSeek-style path (backslash separated)
        public let filename: String
        public let size: UInt64
        public let bitrate: UInt32?
        public let duration: UInt32?
        public let fileExtension: String
        /// Lowercased form of `sharedPath`, precomputed at index time. The
        /// distributed-search handler (`search(query:)`) runs on every
        /// peer search message — on a busy relay that's tens per second —
        /// and used to call `sharedPath.lowercased()` inside the per-file
        /// loop. With ~10k indexed files that burned the main actor
        /// allocating throwaway lowercased Strings; profiling on macOS 15
        /// showed 91% of main-thread time in `StringProtocol.contains`
        /// driven from that loop. Precomputing the lowercased form once
        /// turns the hot path into a pure substring compare.
        public let searchableText: String
        /// Copied from the parent `SharedFolder.visibility` at index time
        /// so the search / browse filters don't need a folder lookup on
        /// every hit.
        public let visibility: Visibility
        /// Back-pointer to the owning `SharedFolder.id`. Used by
        /// `setVisibility` (and can be used by `removeFolder`) to match
        /// indexed files by folder identity rather than by
        /// `localPath.hasPrefix(folder.path)` — the latter silently
        /// matches sibling folders whose names share a prefix
        /// (e.g. `/Music` vs `/Music_archive`), which previously caused
        /// visibility toggles to leak across siblings.
        public let folderID: UUID

        public init(localPath: String, sharedPath: String, size: UInt64, bitrate: UInt32? = nil, duration: UInt32? = nil, visibility: Visibility = .public, folderID: UUID) {
            self.id = UUID()
            self.localPath = localPath
            self.sharedPath = sharedPath
            self.filename = URL(fileURLWithPath: localPath).lastPathComponent
            self.size = size
            self.bitrate = bitrate
            self.duration = duration
            self.fileExtension = URL(fileURLWithPath: localPath).pathExtension.lowercased()
            self.searchableText = sharedPath.lowercased()
            self.visibility = visibility
            self.folderID = folderID
        }
    }

    // MARK: - Persistence Keys

    private let sharedFoldersKey = "SeeleSeek.SharedFolders"
    /// Backing store for shared-folder list and per-path security-scoped
    /// bookmarks. Injectable so tests can hand in a fresh suite and not
    /// race other tests over `UserDefaults.standard`.
    private let defaults: UserDefaults

    // MARK: - Initialization

    /// Side-effect-free. Caller must invoke `loadPersistedFolders()` and
    /// `rescanAll()` explicitly after wiring `countsChangesStream()`
    /// consumers.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Folder Management

    public func addFolder(_ url: URL) {
        // NSOpenPanel URLs have security scope. Plain file URLs (for
        // example, from settings import) do not. A non-sandboxed process
        // can read them without it. Thus scope is optional, not a gate.
        let hasScope = url.startAccessingSecurityScopedResource()

        if hasScope {
            // Store bookmark for persistence
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(bookmarkData, forKey: "bookmark-\(url.path)")
            } catch {
                logger.error("Failed to create bookmark: \(error.localizedDescription)")
            }
        }

        let folder = SharedFolder(path: url.path)

        // Avoid duplicates. Security-scoped resource access is reference-
        // counted: the redundant `start` we just did needs a matching
        // `stop` here, otherwise repeated add-the-same-folder clicks
        // accumulate access counts that are never balanced (the matching
        // `stop` in `removeFolder` only fires once).
        guard !sharedFolders.contains(where: { $0.path == folder.path }) else {
            if hasScope {
                url.stopAccessingSecurityScopedResource()
            }
            logger.info("Folder already shared: \(url.path)")
            return
        }

        sharedFolders.append(folder)
        // The direct `start` above already grants access for this run;
        // record it so `scanFolderResult` doesn't stack a bookmark start.
        if hasScope {
            securityScopedPaths.insert(url.path)
        }
        save()

        // Notify after the scan so the (folders, files) broadcast pair
        // is atomic — never folders=N+1 with the old file count. The scan
        // rides the serialized chain: if a rescan is mid-flight, this runs
        // after its index swap so the new folder's files can't be dropped.
        enqueueScan { [weak self] in
            guard let self else { return }
            self.isScanning = true
            await self.scanFolder(folder)
            self.isScanning = false
            self.notifyCountsChanged()
        }
    }

    public func removeFolder(_ folder: SharedFolder) {
        sharedFolders.removeAll { $0.id == folder.id }

        // Remove indexed files from this folder. Match by folderID so
        // removing `/Music` doesn't also drop files under a sibling
        // `/Music_archive` (same hazard that bit `setVisibility`).
        var files = searchTables.files
        files.removeAll { $0.folderID == folder.id }
        publishSearchTables(files: files, wordIndex: Self.buildWordIndex(from: files))
        recomputeTotalSize()

        // Stop accessing security-scoped resource
        URL(fileURLWithPath: folder.path).stopAccessingSecurityScopedResource()
        securityScopedPaths.remove(folder.path)

        // Remove bookmark
        defaults.removeObject(forKey: "bookmark-\(folder.path)")

        save()
        notifyCountsChanged()
    }

    // MARK: - Scanning

    /// Serializes every scan — `addFolder`'s single-folder scan and
    /// `rescanAll` — so they can never interleave. Without this, addFolder
    /// kicked an unguarded Task that appended to `fileIndex` while a
    /// running `rescanAll` built `newIndex` from an older folder snapshot
    /// and swapped it in at the end, clobbering the just-added folder's
    /// files (and racing the word-index append).
    private var scanChain: Task<Void, Never>?
    /// True while a rescan is running or queued on the chain; folds
    /// concurrent `rescanAll` requests into one (the old `!isScanning`
    /// dedupe, adapted to the serialized chain).
    private var rescanPending = false

    @discardableResult
    private func enqueueScan(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = scanChain
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        scanChain = task
        return task
    }

    public func rescanAll() async {
        guard !rescanPending else { return }
        rescanPending = true
        await enqueueScan { [weak self] in
            guard let self else { return }
            await self.performRescanAll()
            self.rescanPending = false
        }.value
    }

    private func performRescanAll() async {
        isScanning = true
        scanProgress = 0

        // Build the new index aside and swap at the end. Clearing
        // `fileIndex` up front left a minutes-wide window where every
        // peer lookup missed and got a terminal "File not shared."
        var newIndex: [IndexedFile] = []
        // Collected, then applied in one write after the loop — see
        // `mutateFileIndex` for why per-iteration writes are avoided.
        var pendingStats: [ScanResult] = []
        for (index, folder) in sharedFolders.enumerated() {
            if let result = await scanFolderResult(folder) {
                newIndex.append(contentsOf: result.indexed)
                pendingStats.append(result)
                logger.info("Scanned \(folder.displayName): \(result.fileCount) files")
            } else {
                logger.error("Failed to enumerate folder: \(folder.path)")
            }
            scanProgress = Double(index + 1) / Double(sharedFolders.count)
        }
        applyFolderStats(pendingStats)

        // Atomic swap — old `searchTables` generation keeps serving
        // detached searches during the scan. Filter by live folder IDs so
        // a folder removed mid-scan isn't resurrected by the swap
        // (removeFolder publishes its own generation, but this loop
        // scanned from a folder-list snapshot).
        let liveFolderIDs = Set(sharedFolders.map(\.id))
        let files = newIndex.filter { liveFolderIDs.contains($0.folderID) }
        publishSearchTables(files: files, wordIndex: Self.buildWordIndex(from: files))
        recomputeTotalSize()

        lastScanDate = Date()
        isScanning = false
        // Only persist if the for-loop actually ran. With an empty
        // sharedFolders, save() would JSON-encode `[]` and overwrite the
        // user's persisted folder list — so a rescan triggered before
        // (or instead of) loadPersistedFolders silently wipes their
        // shares. addFolder/removeFolder save() their own changes; the
        // rescan-time save is only here to persist refreshed
        // per-folder counts updated by scanFolder.
        if !sharedFolders.isEmpty {
            save()
        }

        logger.info("Scan complete: \(self.totalFiles) files in \(self.totalFolders) folders")
        notifyCountsChanged()
    }

    /// Bundle of per-folder scan outputs produced on a background task and
    /// published back to the main actor in one atomic step. Splitting the
    /// disk walk from the state mutation keeps large rescans off the main
    /// thread — previously the per-file loop called `fileIndex.append`
    /// directly under @MainActor, which on ~10k-file libraries stalled the
    /// UI and starved other main-actor networking orchestration.
    private struct ScanResult: Sendable {
        let folderID: UUID
        let indexed: [IndexedFile]
        let fileCount: Int
        let totalSize: UInt64
    }

    /// Single-folder scan that mutates state directly (addFolder path).
    /// `rescanAll` uses `scanFolderResult` + a deferred index swap instead.
    private func scanFolder(_ folder: SharedFolder) async {
        guard let result = await scanFolderResult(folder) else {
            logger.error("Failed to enumerate folder: \(folder.path)")
            return
        }
        // Build the next generation from the prior immutable tables.
        // Mutating copies here is fine: in-flight searches still hold the
        // previous `searchTables` buffers and are not forced to COW.
        let prior = searchTables
        var files = prior.files
        let start = files.count
        files.append(contentsOf: result.indexed)
        var wordIndex = prior.wordIndex
        for position in start..<files.count {
            for token in Set(Self.tokenize(files[position].searchableText)) {
                wordIndex[token, default: []].append(position)
            }
        }
        publishSearchTables(files: files, wordIndex: wordIndex)
        recomputeTotalSize()
        applyFolderStats([result])
        logger.info("Scanned \(folder.displayName): \(result.fileCount) files")
    }

    /// Update the per-folder counters from completed scans. Takes an array
    /// so a full rescan writes `sharedFolders` once; see `mutateFileIndex`.
    private func applyFolderStats(_ results: [ScanResult]) {
        guard !results.isEmpty else { return }
        var updated = sharedFolders
        let scannedAt = Date()
        for result in results {
            guard let index = updated.firstIndex(where: { $0.id == result.folderID }) else { continue }
            updated[index].fileCount = result.fileCount
            updated[index].totalSize = result.totalSize
            updated[index].lastScanned = scannedAt
        }
        sharedFolders = updated
    }

    /// Disambiguate duplicate share-root display names so sharedPaths
    /// stay unique across roots (e.g. two folders both named "Music"
    /// become "Music" and "Music (2)").
    private func uniqueDisplayName(for folder: SharedFolder) -> String {
        let base = folder.displayName
        let sameName = sharedFolders.filter { $0.displayName == base }
        guard sameName.count > 1,
              let position = sameName.firstIndex(where: { $0.id == folder.id }),
              position > 0 else {
            return base
        }
        let unique = "\(base) (\(position + 1))"
        logger.warning("Share root name collision for \(base) — using \(unique)")
        return unique
    }

    /// Walk a folder on a background task and return the indexed files
    /// plus stats, without touching published state.
    private func scanFolderResult(_ folder: SharedFolder) async -> ScanResult? {
        let folderURL = URL(fileURLWithPath: folder.path)

        // Restore bookmark access on the main actor before handing the URL
        // to a detached task. Started at most once per folder per app run
        // (see `securityScopedPaths`) — the access must persist for
        // serving uploads, so it is deliberately never stopped here, and
        // re-starting on every rescan would pile up unbalanced counts.
        if !securityScopedPaths.contains(folder.path),
           let bookmarkData = defaults.data(forKey: "bookmark-\(folder.path)") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                securityScopedPaths.insert(folder.path)
            }
        }

        // Copy the Sendable bits the worker needs. Folder identity is a
        // UUID and the visibility/path are value types — no main-actor
        // references escape.
        let folderID = folder.id
        let folderVisibility = folder.visibility
        // Suffix duplicate root names so sharedPaths are unique.
        let folderDisplayName = uniqueDisplayName(for: folder)

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            var files: [IndexedFile] = []
            var count = 0
            var total: UInt64 = 0
            let basePath = folderURL.path

            while let fileURL = enumerator.nextObject() as? URL {
                do {
                    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    guard values.isDirectory != true else { continue }

                    let size = UInt64(values.fileSize ?? 0)
                    let relativePath = String(fileURL.path.dropFirst(basePath.count))
                    let sharedPath = folderDisplayName + relativePath.replacingOccurrences(of: "/", with: "\\")

                    files.append(IndexedFile(
                        localPath: fileURL.path,
                        sharedPath: sharedPath,
                        size: size,
                        bitrate: Self.extractBitrate(from: fileURL),
                        visibility: folderVisibility,
                        folderID: folderID
                    ))
                    count += 1
                    total += size
                } catch {
                    // Per-file failures are silent — one unreadable file
                    // shouldn't abort the whole rescan.
                }
            }

            return ScanResult(folderID: folderID, indexed: files, fileCount: count, totalSize: total)
        }.value
    }

    // Static so the detached scan task can call it without a main-actor hop.
    // `nonisolated` is required even on a static on a @MainActor type.
    nonisolated private static func extractBitrate(from url: URL) -> UInt32? {
        // Simple bitrate extraction - in a real app, use AVFoundation
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav"]
        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }

        // For now, estimate based on file size and typical song length (~4 min)
        // Real implementation would use AVAsset
        return nil
    }

    // MARK: - Search

    /// Immutable file table + inverted word index. Generations are swapped
    /// atomically via `publishSearchTables`; searches retain a generation
    /// by value (shared array buffers) so rescans never COW underneath them.
    private struct SearchIndexTables: Sendable {
        let files: [IndexedFile]
        let wordIndex: [String: [Int]]

        static let empty = SearchIndexTables(files: [], wordIndex: [:])

        func search(query: String, includeBuddyOnly: Bool) -> [IndexedFile] {
            let terms = Set(ShareManager.tokenize(query))
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

            // Materialize in index order; apply the visibility gate here,
            // same semantics as the old linear filter. Positions are always
            // valid for this generation — files and wordIndex were built
            // together and never mutated afterward.
            return candidates.sorted().compactMap { position -> IndexedFile? in
                let file = files[position]
                if !includeBuddyOnly && file.visibility == .buddies { return nil }
                return file
            }
        }
    }

    /// Split into lowercased tokens on non-alphanumeric boundaries.
    /// Shared by index building and query parsing so both sides agree.
    nonisolated private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// Build a fresh inverted index for an immutable file table.
    nonisolated private static func buildWordIndex(from files: [IndexedFile]) -> [String: [Int]] {
        var index: [String: [Int]] = [:]
        for (position, file) in files.enumerated() {
            for token in Set(tokenize(file.searchableText)) {
                index[token, default: []].append(position)
            }
        }
        return index
    }

    /// Search local files for a query (used when peers search us).
    ///
    /// Inverted-index lookup: tokenize the query, fetch each term's
    /// posting list, and intersect starting from the smallest list. This
    /// replaced a per-packet linear scan (O(files × terms) substring
    /// checks) that kept the CPU busy all day on a 5-50 queries/sec
    /// distributed relay. Matching is whole-word (canonical SoulSeek /
    /// Nicotine+ behavior), no longer substring-contains.
    ///
    /// Retains the current immutable `searchTables` generation (pointer
    /// to the arrays) and runs the intersection on a detached utility
    /// task so a busy relay cannot steal main-actor frames. Concurrent
    /// workers are capped — see `maxConcurrentSearches`.
    ///
    /// `includeBuddyOnly` controls whether folders marked `.buddies` are
    /// visible to the requester. Callers resolve that flag from their
    /// knowledge of the requester (buddy-list membership) before calling.
    public func search(query: String, includeBuddyOnly: Bool) async -> [IndexedFile] {
        let tables = searchTables
        let buddyOnly = includeBuddyOnly
        await acquireSearchSlot()
        defer { releaseSearchSlot() }
        return await Task.detached(priority: .utility) {
            tables.search(query: query, includeBuddyOnly: buddyOnly)
        }.value
    }

    /// Snapshot of all indexed files visible to a given requester. Used
    /// by the shares-browse handler to partition the reply into public
    /// and private sections.
    public func indexedFiles(includeBuddyOnly: Bool) -> [IndexedFile] {
        if includeBuddyOnly { return fileIndex }
        return fileIndex.filter { $0.visibility == .public }
    }

    /// Change a folder's visibility and propagate the new flag to every
    /// `IndexedFile` already scanned from that folder (avoids a rescan).
    ///
    /// Matching is by `folderID`, not by `localPath` prefix. A path
    /// prefix check would also rewrite entries from sibling folders
    /// whose names share the target's prefix (e.g. flipping `/Music`
    /// would also rewrite files under `/Music_archive`), silently
    /// desyncing the UI from what peers see on the wire.
    public func setVisibility(_ visibility: Visibility, forFolderWithID id: UUID) {
        guard let idx = sharedFolders.firstIndex(where: { $0.id == id }) else { return }
        guard sharedFolders[idx].visibility != visibility else { return }
        sharedFolders[idx].visibility = visibility
        // Rewrite the subset of fileIndex that came from this folder.
        // IndexedFile fields are `let`, so entries are replaced wholesale.
        mutateFileIndex { index in
            for i in index.indices where index[i].folderID == id {
                let f = index[i]
                index[i] = IndexedFile(
                    localPath: f.localPath,
                    sharedPath: f.sharedPath,
                    size: f.size,
                    bitrate: f.bitrate,
                    duration: f.duration,
                    visibility: visibility,
                    folderID: f.folderID
                )
            }
        }
        save()
        // No notify — `SharedFoldersFiles` broadcasts `totalFiles` (all
        // visibilities), which doesn't change here. Revisit if we switch
        // broadcast semantics to public-only.
    }

    // The old `toSharedFiles()` / `buildChildren(for:from:)` tree builder
    // lived here. It had no callers anywhere in the repo (the shares-browse
    // reply is built from the database via `SharedFileRecord.toSharedFiles`
    // in the app layer) and its child-matching logic was buggy — removed.

    // MARK: - Test seams

    /// Inject a synthetic file index without going through `addFolder` /
    /// `rescanAll`. Used by upload retry tests so they don't have to spin
    /// up the disk-walk code path.
    internal func _seedFileIndexForTest(_ files: [IndexedFile]) {
        publishSearchTables(files: files, wordIndex: Self.buildWordIndex(from: files))
        recomputeTotalSize()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(sharedFolders)
            defaults.set(data, forKey: sharedFoldersKey)
        } catch {
            logger.error("Failed to save shared folders: \(error.localizedDescription)")
        }
    }

    /// Decode persisted shared-folder list from `UserDefaults`. Synchronous
    /// — does NOT trigger a rescan. Call `rescanAll()` after this to
    /// repopulate `fileIndex`. The two steps are split so the caller can
    /// register `countsChangesStream` subscribers between them; the
    /// rescan-completion yield is then guaranteed to be observed.
    public func loadPersistedFolders() {
        guard let data = defaults.data(forKey: sharedFoldersKey) else { return }

        do {
            sharedFolders = try JSONDecoder().decode([SharedFolder].self, from: data)
        } catch {
            logger.error("Failed to load shared folders: \(error.localizedDescription)")
        }
    }
}
