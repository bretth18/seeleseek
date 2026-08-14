import Foundation

public struct SharedFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let filename: String
    public let size: UInt64
    public let bitrate: UInt32?
    public let duration: UInt32?
    public let isDirectory: Bool
    public let isPrivate: Bool  // Buddy-only / locked file
    public var children: [SharedFile]?
    public var fileCount: Int = 0  // Cached count of files (recursive) — set during tree building

    public nonisolated init(
        id: UUID = UUID(),
        filename: String,
        size: UInt64 = 0,
        bitrate: UInt32? = nil,
        duration: UInt32? = nil,
        isDirectory: Bool = false,
        isPrivate: Bool = false,
        children: [SharedFile]? = nil,
        fileCount: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.isDirectory = isDirectory
        self.isPrivate = isPrivate
        self.children = children
        self.fileCount = fileCount
    }

    public nonisolated var displayName: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    public var formattedSize: String {
        size.formattedBytes
    }

    public nonisolated var fileExtension: String {
        let components = displayName.split(separator: ".")
        if components.count > 1, let ext = components.last {
            return String(ext).lowercased()
        }
        return ""
    }

    public nonisolated var displayFilename: String {
        displayName
    }

    public nonisolated var isAudioFile: Bool { FileTypes.isAudio(fileExtension) }
    public var isImageFile: Bool { FileTypes.isImage(fileExtension) }
    public var isVideoFile: Bool { FileTypes.isVideo(fileExtension) }
    public var isArchiveFile: Bool { FileTypes.isArchive(fileExtension) }
    public var isLossless: Bool { FileTypes.isLossless(fileExtension) }

    /// Recursively collect all non-directory files from a tree
    public static func collectAllFiles(in files: [SharedFile]) -> [SharedFile] {
        var result: [SharedFile] = []
        for f in files {
            if f.isDirectory {
                if let children = f.children {
                    result.append(contentsOf: collectAllFiles(in: children))
                }
            } else {
                result.append(f)
            }
        }
        return result
    }

    // MARK: - Tree Building

    /// Build a hierarchical tree from flat file paths
    /// Input: Flat array of files with paths like "@@share\Folder\Subfolder\file.mp3"
    /// Output: Tree structure with directories containing children
    ///
    /// Adjacency is precomputed in the discovery pass. Mega-shares are real
    /// (250k+ folders, 2M+ files seen in the field), so anything that scans
    /// all folders per folder is minutes of CPU, not a constant factor.
    public nonisolated static func buildTree(from flatFiles: [SharedFile]) -> [SharedFile] {
        var folderIDs: [String: UUID] = [:]
        var filesByFolder: [String: [SharedFile]] = [:]
        var subfolders: [String: [String]] = [:]
        var rootFolders: [String] = []

        for file in flatFiles {
            let pathComponents = file.filename.split(separator: "\\").map(String.init)
            guard !pathComponents.isEmpty else { continue }

            guard pathComponents.count > 1 else {
                // File at root level (unusual but handle it): keep the
                // longstanding behavior of surfacing it as an empty folder.
                if folderIDs[file.filename] == nil {
                    folderIDs[file.filename] = UUID()
                    rootFolders.append(file.filename)
                }
                continue
            }

            // Register any not-yet-seen folders along the path
            var currentPath = ""
            for (index, component) in pathComponents.dropLast().enumerated() {
                let parentPath = currentPath
                currentPath = currentPath.isEmpty ? component : "\(currentPath)\\\(component)"

                if folderIDs[currentPath] == nil {
                    folderIDs[currentPath] = UUID()
                    if index == 0 {
                        rootFolders.append(currentPath)
                    } else {
                        subfolders[parentPath, default: []].append(currentPath)
                    }
                }
            }
            filesByFolder[currentPath, default: []].append(file)
        }

        func buildFolder(path: String) -> SharedFile {
            var children = (subfolders[path] ?? []).map(buildFolder)
            children.append(contentsOf: filesByFolder[path] ?? [])

            // Sort: folders first, then files, alphabetically. Keys are
            // cached — displayName re-splits the path per call, which the
            // comparator would otherwise do millions of times.
            children = children
                .map { (file: $0, key: $0.displayName) }
                .sorted { a, b in
                    if a.file.isDirectory != b.file.isDirectory {
                        return a.file.isDirectory
                    }
                    return a.key.localizedCaseInsensitiveCompare(b.key) == .orderedAscending
                }
                .map(\.file)

            let totalSize = children.reduce(0) { $0 + $1.size }
            let totalFiles = children.reduce(0) { $0 + ($1.isDirectory ? $1.fileCount : 1) }

            // A folder is considered private when every descendant is
            // private — i.e. the peer marked the whole folder buddy-only
            // on their end. We propagate that so the browse view can
            // show a single lock badge on the folder instead of forcing
            // the user to expand and see a lock on every child. Empty
            // folders default to non-private (nothing to hide).
            let isFolderPrivate = !children.isEmpty && children.allSatisfy { $0.isPrivate }

            return SharedFile(
                id: folderIDs[path] ?? UUID(),
                filename: path,
                size: totalSize,
                isDirectory: true,
                isPrivate: isFolderPrivate,
                children: children,
                fileCount: totalFiles
            )
        }

        return rootFolders.sorted().map(buildFolder)
    }
}
