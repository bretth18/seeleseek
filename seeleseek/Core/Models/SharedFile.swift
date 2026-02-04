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
