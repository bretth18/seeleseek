import Foundation

struct SharedFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let filename: String
    let size: UInt64
    let bitrate: UInt32?
    let duration: UInt32?
    let isDirectory: Bool
    var children: [SharedFile]?

    init(
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

        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "alac", "wma", "ape"]
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv"]
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz"]

        if audioExtensions.contains(fileExtension) {
            return "music.note"
        } else if imageExtensions.contains(fileExtension) {
            return "photo"
        } else if videoExtensions.contains(fileExtension) {
            return "film"
        } else if archiveExtensions.contains(fileExtension) {
            return "archivebox"
        }
        return "doc"
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
}
