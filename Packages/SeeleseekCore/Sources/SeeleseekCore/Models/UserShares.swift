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

    // Run inside UI bodies on every render — must stay O(roots), never walk
    // the tree.

    public var totalFiles: Int {
        cachedTotalFiles ?? SharedFile.aggregateFileCount(of: folders)
    }

    public var totalSize: UInt64 {
        cachedTotalSize ?? SharedFile.aggregateSize(of: folders)
    }

    public nonisolated mutating func computeStats() {
        cachedTotalFiles = SharedFile.aggregateFileCount(of: folders)
        cachedTotalSize = SharedFile.aggregateSize(of: folders)
    }
}
