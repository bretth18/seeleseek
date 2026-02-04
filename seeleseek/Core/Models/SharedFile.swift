import Foundation

struct SharedFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let size: UInt64
    let bitrate: UInt32?
    let duration: UInt32?
    let isDirectory: Bool
    var children: [SharedFile]?

    nonisolated init(
        id: UUID = UUID(),
        filename: String,
        size: UInt64 = 0,
        bitrate: UInt32? = nil,
        duration: UInt32? = nil,
        isDirectory: Bool = false,
        children: [SharedFile]? = nil
    ) {
        self.id = id
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.isDirectory = isDirectory
        self.children = children
    }

    var displayName: String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    var formattedSize: String {
        ByteFormatter.format(Int64(size))
    }

    var fileExtension: String {
        let components = displayName.split(separator: ".")
        if components.count > 1, let ext = components.last {
            return String(ext).lowercased()
        }
        return ""
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }

        if isAudioFile {
            return "music.note"
        } else if isImageFile {
            return "photo"
        } else if isVideoFile {
            return "film"
        } else if isArchiveFile {
            return "archivebox"
        }
        return "doc"
    }

    var displayFilename: String {
        displayName
    }

    var isAudioFile: Bool {
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "alac", "wma", "ape"]
        return audioExtensions.contains(fileExtension)
    }

    var isImageFile: Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
        return imageExtensions.contains(fileExtension)
    }

    var isVideoFile: Bool {
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv"]
        return videoExtensions.contains(fileExtension)
    }

    var isArchiveFile: Bool {
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz"]
        return archiveExtensions.contains(fileExtension)
    }

    var isLossless: Bool {
        let losslessExtensions = ["flac", "wav", "aiff", "alac", "ape"]
        return losslessExtensions.contains(fileExtension)
    }

    // MARK: - Tree Building

    /// Build a hierarchical tree from flat file paths
    /// Input: Flat array of files with paths like "@@share\Folder\Subfolder\file.mp3"
    /// Output: Tree structure with directories containing children
    static func buildTree(from flatFiles: [SharedFile]) -> [SharedFile] {
        // Use a dictionary to track folders by their full path
        var folderMap: [String: (id: UUID, children: [SharedFile])] = [:]
        var rootFolders: [String] = []

        for file in flatFiles {
            let pathComponents = file.filename.split(separator: "\\").map(String.init)
            guard !pathComponents.isEmpty else { continue }

            // Build folder hierarchy
            var currentPath = ""
            for (index, component) in pathComponents.dropLast().enumerated() {
                let parentPath = currentPath
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

            // Calculate total size of folder
            let totalSize = children.reduce(0) { $0 + $1.size }

            return SharedFile(
                id: folderData.id,
                filename: path,
                size: totalSize,
                isDirectory: true,
                children: children
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

struct UserShares: Identifiable, Sendable {
    let id: UUID
    let username: String
    var folders: [SharedFile]
    var isLoading: Bool
    var error: String?

    init(
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

    var totalFiles: Int {
        countFiles(in: folders)
    }

    var totalSize: UInt64 {
        sumSize(in: folders)
    }

    private func countFiles(in files: [SharedFile]) -> Int {
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

    private func sumSize(in files: [SharedFile]) -> UInt64 {
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
