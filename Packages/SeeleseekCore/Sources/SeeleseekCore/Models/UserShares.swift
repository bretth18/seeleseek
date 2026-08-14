import Foundation


public struct UserShares: Identifiable, Sendable {
    public let id: UUID
    public let username: String
    public var folders: [SharedFile]
    public var isLoading: Bool
    public var error: String?

    // Cached stats - computed once when tree is built
    private(set) var cachedTotalFiles: Int?
    private(set) var cachedTotalSize: UInt64?

    public nonisolated init(
        id: UUID = UUID(),
        username: String,
        folders: [SharedFile] = [],
        isLoading: Bool = true,
        error: String? = nil,
        totalFiles: Int? = nil,
        totalSize: UInt64? = nil
    ) {
        self.id = id
        self.username = username
        self.folders = folders
        self.isLoading = isLoading
        self.error = error
        self.cachedTotalFiles = totalFiles
        self.cachedTotalSize = totalSize
    }

    // These getters run inside UI bodies (tab labels, browse headers) on
    // every render, so they must never walk the tree: profiling caught the
    // old recursive fallback spending seconds per render on a 2M-node share.
    // Root nodes carry aggregates from tree building, making the fallback
    // O(roots).

    public var totalFiles: Int {
        cachedTotalFiles ?? Self.rootFileCount(of: folders)
    }

    public var totalSize: UInt64 {
        cachedTotalSize ?? Self.rootSize(of: folders)
    }

    /// Cache the aggregates so even O(roots) is paid once.
    public nonisolated mutating func computeStats() {
        cachedTotalFiles = Self.rootFileCount(of: folders)
        cachedTotalSize = Self.rootSize(of: folders)
    }

    private nonisolated static func rootFileCount(of folders: [SharedFile]) -> Int {
        folders.reduce(0) { $0 + ($1.isDirectory ? $1.fileCount : 1) }
    }

    private nonisolated static func rootSize(of folders: [SharedFile]) -> UInt64 {
        folders.reduce(0) { $0 + $1.size }
    }
}
