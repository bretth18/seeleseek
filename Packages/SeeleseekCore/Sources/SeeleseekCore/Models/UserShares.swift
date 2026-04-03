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
        error: String? = nil
    ) {
        self.id = id
        self.username = username
        self.folders = folders
        self.isLoading = isLoading
        self.error = error
    }

    public var totalFiles: Int {
        cachedTotalFiles ?? countFiles(in: folders)
    }

    public var totalSize: UInt64 {
        cachedTotalSize ?? sumSize(in: folders)
    }

    /// Compute and cache stats (call this after building tree, off main thread)
    public nonisolated mutating func computeStats() {
        cachedTotalFiles = countFiles(in: folders)
        cachedTotalSize = sumSize(in: folders)
    }

    private nonisolated func countFiles(in files: [SharedFile]) -> Int {
        var count = 0
        for file in files {
            if file.isDirectory, let children = file.children {
                count += countFiles(in: children)
            } else if !file.isDirectory {
                count += 1
            }
        }
        return count
    }

    private nonisolated func sumSize(in files: [SharedFile]) -> UInt64 {
        var total: UInt64 = 0
        for file in files {
            if file.isDirectory, let children = file.children {
                total += sumSize(in: children)
            } else {
                total += file.size
            }
        }
        return total
    }
}
