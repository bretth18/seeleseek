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
    public nonisolated static func buildTree(from flatFiles: [SharedFile]) -> [SharedFile] {
        // Use a dictionary to track folders by their full path
        var folderMap: [String: (id: UUID, children: [SharedFile])] = [:]
        var rootFolders: [String] = []

        for file in flatFiles {
            let pathComponents = file.filename.split(separator: "\\").map(String.init)
            guard !pathComponents.isEmpty else { continue }

            // Build folder hierarchy
            var currentPath = ""
            for (index, component) in pathComponents.dropLast().enumerated() {
                _ = currentPath
                currentPath = currentPath.isEmpty ? component : "\(currentPath)\\\(component)"

                if folderMap[currentPath] == nil {
                    folderMap[currentPath] = (id: UUID(), children: [])

                    // Track root folders
                    if index == 0 && !rootFolders.contains(currentPath) {
                        rootFolders.append(currentPath)
                    }
                }
            }

            // Add file to its parent folder
            if pathComponents.count > 1 {
                let parentPath = pathComponents.dropLast().joined(separator: "\\")
                folderMap[parentPath]?.children.append(file)
            } else {
                // File at root level (unusual but handle it)
                if !rootFolders.contains(file.filename) {
                    rootFolders.append(file.filename)
                    folderMap[file.filename] = (id: UUID(), children: [])
                }
            }
        }

        // Build the tree recursively
        func buildFolder(path: String, name: String) -> SharedFile {
            guard let folderData = folderMap[path] else {
                return SharedFile(filename: path, isDirectory: true)
            }

            // Find child folders
            var children: [SharedFile] = []

            // Add subfolders
            for (childPath, _) in folderMap {
                // Check if childPath is a direct child of path
                if childPath.hasPrefix(path + "\\") {
                    let remaining = String(childPath.dropFirst(path.count + 1))
                    if !remaining.contains("\\") {
                        // Direct child folder
                        let childName = remaining
                        children.append(buildFolder(path: childPath, name: childName))
                    }
                }
            }

            // Add files (already in folderData.children)
            children.append(contentsOf: folderData.children)

            // Sort: folders first, then files, alphabetically
            children.sort { a, b in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }

            // Calculate total size and file count for folder
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
                id: folderData.id,
                filename: path,
                size: totalSize,
                isDirectory: true,
                isPrivate: isFolderPrivate,
                children: children,
                fileCount: totalFiles
            )
        }

        // Build root folders
        var result: [SharedFile] = []
        for rootPath in rootFolders.sorted() {
            let name = rootPath.split(separator: "\\").last.map(String.init) ?? rootPath
            result.append(buildFolder(path: rootPath, name: name))
        }

        return result
    }
}
