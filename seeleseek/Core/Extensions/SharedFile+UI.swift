import SeeleseekCore

extension SharedFile {
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
}
