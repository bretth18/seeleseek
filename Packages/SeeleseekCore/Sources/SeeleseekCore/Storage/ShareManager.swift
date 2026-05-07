import Foundation
import os

/// Manages shared folders and file index for the SoulSeek client
@Observable
@MainActor
public final class ShareManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ShareManager")

    // MARK: - State

    public private(set) var sharedFolders: [SharedFolder] = []
    public private(set) var fileIndex: [IndexedFile] = []
    public private(set) var isScanning = false
    public private(set) var scanProgress: Double = 0
    public private(set) var lastScanDate: Date?

    // Computed stats
    public var totalFiles: Int { fileIndex.count }
    public var totalFolders: Int { sharedFolders.count }
    public var totalSize: UInt64 { fileIndex.reduce(0) { $0 + $1.size } }

    /// Per-subscriber `AsyncStream` continuations. Each call to
    /// `countsChangesStream()` allocates a fresh stream and registers its
    /// continuation here; `notifyCountsChanged()` fans out to all of them.
    /// Vanilla `AsyncStream` is single-consumer, so we maintain the
    /// fan-out ourselves rather than handing every subscriber the same
    /// stream (where they'd race for events).
    ///
    /// Why `AsyncStream` instead of a closure dict: the continuation
    /// buffers yields fired before the consumer's `for await` loop has
    /// actually started executing. That eliminates the previous
    /// subscribe-before-publish ordering invariant — `NetworkClient` can
    /// register its consumer in `init`, and any rescan completion that
    /// fires before the consumer Task is scheduled is replayed when the
    /// loop drains the buffer. The previous closure-dict required strict
    /// MainActor-serial ordering between subscriber registration and
    /// publisher fire to avoid silently dropping the first event.
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    /// Coalescing task: bulk operations (a 10-folder add, a removeFolder
    /// loop) would otherwise produce N broadcasts. We delay 200 ms after
    /// the *last* count-changing event and yield once. 200 ms is short
    /// enough that the server-visible state lags imperceptibly while
    /// still folding programmatic batches into a single update.
    private var countsChangedDebounce: Task<Void, Never>?

    /// Subscribe to share-count change events. Each call returns a fresh
    /// stream — concurrent consumers all receive every yield. Cancelling
    /// the consuming Task (or letting it go out of scope) tears down the
    /// continuation via `onTermination` and removes it from `continuations`.
    public func countsChangesStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            // Continuation registration must happen on MainActor (the
            // dict is MainActor-isolated). The AsyncStream initializer's
            // closure runs synchronously in the caller's context — and
            // every call site is MainActor since the type itself is
            // @MainActor — so the direct mutation is safe.
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                // `onTermination` runs on the AsyncStream's internal
                // queue, not MainActor. Hop back to remove our entry.
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Schedule a coalesced yield to every registered continuation.
    /// Cheap to call repeatedly in a tight loop — only the trailing edge
    /// actually wakes subscribers.
    private func notifyCountsChanged() {
        countsChangedDebounce?.cancel()
        countsChangedDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            // Snapshot before iterating — a subscriber's `onTermination`
            // hopping back to remove its entry shouldn't mutate the dict
            // we're traversing.
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

        public var displayName: String {
            URL(fileURLWithPath: path).lastPathComponent
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

    // MARK: - Initialization

    /// Side-effect-free. Construction does NOT decode persisted folders or
    /// kick off a rescan — the app must call `loadPersistedFolders()` then
    /// `rescanAll()` explicitly, AFTER any `countsChangesStream()`
    /// consumers have been wired. Pre-refactor `init` did both implicitly,
    /// which meant the `rescanAll` Task could fire `notifyCountsChanged`
    /// before any subscriber existed; the only thing keeping it correct
    /// was MainActor's serial execution of synchronous `init` chains.
    /// Decoupling here lets `NetworkClient.init` register its
    /// `countsChangesStream` consumer first, and any subsequent rescan
    /// completion is reliably observed.
    public init() {}

    // MARK: - Folder Management

    public func addFolder(_ url: URL) {
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped resource: \(url.path)")
            return
        }

        // Store bookmark for persistence
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark-\(url.path)")
        } catch {
            logger.error("Failed to create bookmark: \(error.localizedDescription)")
        }

        let folder = SharedFolder(path: url.path)

        // Avoid duplicates
        guard !sharedFolders.contains(where: { $0.path == folder.path }) else {
            logger.info("Folder already shared: \(url.path)")
            return
        }

        sharedFolders.append(folder)
        save()

        // Scan the new folder, then notify so the server learns about the
        // new file count. Notifying before the scan would push a broadcast
        // with an inflated folder count and zero new files, which we'd
        // immediately replace seconds later when the scan finishes — and
        // the (folders, files) pair is broadcast atomically, so an
        // intermediate (folders=N+1, files=oldCount) state is wrong on its
        // face.
        Task {
            await scanFolder(folder)
            notifyCountsChanged()
        }
    }

    public func removeFolder(_ folder: SharedFolder) {
        sharedFolders.removeAll { $0.id == folder.id }

        // Remove indexed files from this folder. Match by folderID so
        // removing `/Music` doesn't also drop files under a sibling
        // `/Music_archive` (same hazard that bit `setVisibility`).
        fileIndex.removeAll { $0.folderID == folder.id }

        // Stop accessing security-scoped resource
        URL(fileURLWithPath: folder.path).stopAccessingSecurityScopedResource()

        // Remove bookmark
        UserDefaults.standard.removeObject(forKey: "bookmark-\(folder.path)")

        save()
        notifyCountsChanged()
    }

    // MARK: - Scanning

    public func rescanAll() async {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        fileIndex.removeAll()

        for (index, folder) in sharedFolders.enumerated() {
            await scanFolder(folder)
            scanProgress = Double(index + 1) / Double(sharedFolders.count)
        }

        lastScanDate = Date()
        isScanning = false
        save()

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

    private func scanFolder(_ folder: SharedFolder) async {
        let folderURL = URL(fileURLWithPath: folder.path)

        // Restore bookmark access on the main actor before handing the URL
        // to a detached task — security-scoped resource access is per-URL
        // and must be balanced, but the access call itself is cheap.
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark-\(folder.path)") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
            }
        }

        // Copy the Sendable bits the worker needs. Folder identity is a
        // UUID and the visibility/path are value types — no main-actor
        // references escape.
        let folderID = folder.id
        let folderVisibility = folder.visibility
        let folderDisplayName = folder.displayName

        let result: ScanResult? = await Task.detached(priority: .utility) {
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

        guard let result else {
            logger.error("Failed to enumerate folder: \(folder.path)")
            return
        }

        // Single publish step back on main: append the scanned batch and
        // update folder stats in one @MainActor hop.
        fileIndex.append(contentsOf: result.indexed)
        if let index = sharedFolders.firstIndex(where: { $0.id == result.folderID }) {
            sharedFolders[index].fileCount = result.fileCount
            sharedFolders[index].totalSize = result.totalSize
            sharedFolders[index].lastScanned = Date()
        }

        logger.info("Scanned \(folder.displayName): \(result.fileCount) files")
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

    /// Search local files for a query (used when peers search us).
    ///
    /// Offloaded to `Task.detached` so the scan never runs on the main
    /// actor. On a busy distributed-search relay this handler fires many
    /// times per second, and the scan is O(files × terms) — keeping it
    /// on main meant the UI stalled while peer traffic flowed. The
    /// `fileIndex` snapshot is a value-type array and IndexedFile is
    /// Sendable, so the detached task gets a safe copy-on-write view.
    ///
    /// `includeBuddyOnly` controls whether folders marked `.buddies` are
    /// visible to the requester. Callers resolve that flag from their
    /// knowledge of the requester (buddy-list membership) before calling.
    public func search(query: String, includeBuddyOnly: Bool) async -> [IndexedFile] {
        let snapshot = fileIndex
        return await Task.detached(priority: .utility) {
            let terms = query.lowercased().split(separator: " ").map(String.init)
            guard !terms.isEmpty else { return [] }
            return snapshot.filter { file in
                if !includeBuddyOnly && file.visibility == .buddies { return false }
                // `searchableText` is precomputed at index time — no
                // per-query allocation here.
                return terms.allSatisfy { file.searchableText.contains($0) }
            }
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
        // IndexedFile fields are `let`, so we replace entries in place.
        for i in fileIndex.indices where fileIndex[i].folderID == id {
            let f = fileIndex[i]
            fileIndex[i] = IndexedFile(
                localPath: f.localPath,
                sharedPath: f.sharedPath,
                size: f.size,
                bitrate: f.bitrate,
                duration: f.duration,
                visibility: visibility,
                folderID: f.folderID
            )
        }
        save()
        // Deliberately does NOT call `notifyCountsChanged`. The
        // SharedFoldersFiles message broadcast by `NetworkClient` carries
        // `totalFiles` (every indexed file regardless of visibility), and
        // toggling public ↔ buddies doesn't change that total. If we ever
        // change the broadcast semantics to "publicly visible files only,"
        // this site needs to fire too.
    }

    /// Convert indexed files to SharedFile format for responses
    public func toSharedFiles() -> [SharedFile] {
        // Group by folder
        var folders: [String: [IndexedFile]] = [:]

        for file in fileIndex {
            let components = file.sharedPath.split(separator: "\\")
            if components.count > 1 {
                let folderPath = components.dropLast().joined(separator: "\\")
                folders[folderPath, default: []].append(file)
            }
        }

        // Build folder tree
        return sharedFolders.map { folder in
            SharedFile(
                filename: folder.displayName,
                isDirectory: true,
                children: buildChildren(for: folder.displayName, from: folders)
            )
        }
    }

    private func buildChildren(for prefix: String, from folders: [String: [IndexedFile]]) -> [SharedFile] {
        var result: [SharedFile] = []

        // Find direct children (files and subfolders)
        let directFiles = fileIndex.filter { file in
            let components = file.sharedPath.split(separator: "\\")
            return components.count == 2 && file.sharedPath.hasPrefix(prefix)
        }

        for file in directFiles {
            result.append(SharedFile(
                filename: file.sharedPath,
                size: file.size,
                bitrate: file.bitrate,
                duration: file.duration
            ))
        }

        // Find subfolders
        let subfolders = Set(folders.keys.filter { $0.hasPrefix(prefix + "\\") }
            .compactMap { path -> String? in
                let remaining = path.dropFirst(prefix.count + 1)
                if let nextSeparator = remaining.firstIndex(of: "\\") {
                    return prefix + "\\" + remaining[..<nextSeparator]
                }
                return path
            })

        for subfolder in subfolders {
            result.append(SharedFile(
                filename: subfolder,
                isDirectory: true,
                children: buildChildren(for: subfolder, from: folders)
            ))
        }

        return result
    }

    // MARK: - Test seams

    /// Inject a synthetic file index without going through `addFolder` /
    /// `rescanAll`. Used by upload retry tests so they don't have to spin
    /// up the disk-walk code path.
    internal func _seedFileIndexForTest(_ files: [IndexedFile]) {
        fileIndex = files
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(sharedFolders)
            UserDefaults.standard.set(data, forKey: sharedFoldersKey)
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
        guard let data = UserDefaults.standard.data(forKey: sharedFoldersKey) else { return }

        do {
            sharedFolders = try JSONDecoder().decode([SharedFolder].self, from: data)
        } catch {
            logger.error("Failed to load shared folders: \(error.localizedDescription)")
        }
    }
}
