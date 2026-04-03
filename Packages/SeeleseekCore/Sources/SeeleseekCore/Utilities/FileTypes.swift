import Foundation

/// Canonical file type classifications for SoulSeek file sharing.
public enum FileTypes {
    public static let audio: Set<String> = [
        "mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "aif", "alac", "wma", "ape"
    ]

    public static let lossless: Set<String> = [
        "flac", "wav", "aiff", "aif", "alac", "ape"
    ]

    public static let image: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp"
    ]

    public static let video: Set<String> = [
        "mp4", "mkv", "avi", "mov", "wmv"
    ]

    public static let archive: Set<String> = [
        "zip", "rar", "7z", "tar", "gz"
    ]

    public static func isAudio(_ ext: String) -> Bool { audio.contains(ext) }
    public static func isLossless(_ ext: String) -> Bool { lossless.contains(ext) }
    public static func isImage(_ ext: String) -> Bool { image.contains(ext) }
    public static func isVideo(_ ext: String) -> Bool { video.contains(ext) }
    public static func isArchive(_ ext: String) -> Bool { archive.contains(ext) }
}
