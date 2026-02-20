import Testing
import Foundation
@testable import seeleseek

@Suite("Download Path Resolution Tests")
struct DownloadPathTests {

    // MARK: - Template Substitution

    @Test("Username and path template")
    func testUsernameAndPath() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{username}/{folders}/{filename}"
        )
        #expect(result == "cooldj/Daft Punk/Discovery/01 One More Time.mp3")
    }

    @Test("Path only template")
    func testPathOnly() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{folders}/{filename}"
        )
        #expect(result == "Daft Punk/Discovery/01 One More Time.mp3")
    }

    @Test("Artist - Album template from folder structure")
    func testArtistAlbumFromFolders() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{artist} - {album}/{filename}"
        )
        #expect(result == "Daft Punk - Discovery/01 One More Time.mp3")
    }

    @Test("Flat template (filename only)")
    func testFlat() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{filename}"
        )
        #expect(result == "01 One More Time.mp3")
    }

    // MARK: - Metadata Override

    @Test("Metadata artist and album override folder-derived values")
    func testMetadataOverride() {
        let metadata = AudioFileMetadata(artist: "Daft Punk", album: "Discovery", title: nil)
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Electronic\\DP stuff\\01 track.mp3",
            username: "cooldj",
            template: "{artist} - {album}/{filename}",
            metadata: metadata
        )
        #expect(result == "Daft Punk - Discovery/01 track.mp3")
    }

    @Test("Partial metadata: only artist from metadata, album from folder")
    func testPartialMetadataArtistOnly() {
        let metadata = AudioFileMetadata(artist: "Daft Punk", album: nil, title: nil)
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Wrong Artist\\Discovery\\01 track.mp3",
            username: "cooldj",
            template: "{artist} - {album}/{filename}",
            metadata: metadata
        )
        #expect(result == "Daft Punk - Discovery/01 track.mp3")
    }

    @Test("Partial metadata: only album from metadata, artist from folder")
    func testPartialMetadataAlbumOnly() {
        let metadata = AudioFileMetadata(artist: nil, album: "Discovery", title: nil)
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Wrong Album\\01 track.mp3",
            username: "cooldj",
            template: "{artist} - {album}/{filename}",
            metadata: metadata
        )
        #expect(result == "Daft Punk - Discovery/01 track.mp3")
    }

    @Test("No metadata falls back to folder-derived values")
    func testNoMetadata() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{artist} - {album}/{filename}",
            metadata: nil
        )
        #expect(result == "Daft Punk - Discovery/01 One More Time.mp3")
    }

    // MARK: - Share Marker Stripping

    @Test("@@music share marker stripped")
    func testShareMarkerMusic() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Artist\\Album\\file.mp3",
            username: "user",
            template: "{folders}/{filename}"
        )
        #expect(result == "Artist/Album/file.mp3")
    }

    @Test("@@downloads share marker stripped")
    func testShareMarkerDownloads() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@downloads\\stuff\\file.mp3",
            username: "user",
            template: "{folders}/{filename}"
        )
        #expect(result == "stuff/file.mp3")
    }

    @Test("Path without share marker works")
    func testNoShareMarker() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "Music\\Artist\\Album\\file.mp3",
            username: "user",
            template: "{folders}/{filename}"
        )
        #expect(result == "Music/Artist/Album/file.mp3")
    }

    // MARK: - Edge Cases

    @Test("Single folder component: artist is empty, album is the folder")
    func testSingleFolderComponent() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Album\\file.mp3",
            username: "user",
            template: "{artist} - {album}/{filename}"
        )
        // artist is empty, so " - Album" after double-slash cleanup
        #expect(result == " - Album/file.mp3")
    }

    @Test("No folders: just a filename")
    func testNoFolders() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\file.mp3",
            username: "user",
            template: "{folders}/{filename}"
        )
        #expect(result == "file.mp3")
    }

    @Test("No folders with artist-album template")
    func testNoFoldersArtistAlbum() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\file.mp3",
            username: "user",
            template: "{artist} - {album}/{filename}"
        )
        // Both artist and album are empty: " - " gets cleaned, leaves just filename
        #expect(result == " - /file.mp3".replacingOccurrences(of: "//", with: "/"))
        // Actually let's verify the exact output
        #expect(result == " - /file.mp3")
    }

    @Test("Deep folder hierarchy: artist and album from last two folders")
    func testDeepHierarchy() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Electronic\\House\\Daft Punk\\Discovery\\01 track.mp3",
            username: "user",
            template: "{artist} - {album}/{filename}"
        )
        #expect(result == "Daft Punk - Discovery/01 track.mp3")
    }

    @Test("Unicode characters preserved")
    func testUnicode() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Björk\\Homogenic\\01 Hunter.mp3",
            username: "user",
            template: "{artist} - {album}/{filename}"
        )
        #expect(result == "Björk - Homogenic/01 Hunter.mp3")
    }

    @Test("Empty soulseek path produces fallback")
    func testEmptyPath() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "",
            username: "user",
            template: "{filename}"
        )
        #expect(result == "unknown")
    }

    // MARK: - Double-Slash Cleanup

    @Test("Empty folders token doesn't produce double slashes")
    func testEmptyFoldersNoDoubleSlash() {
        // Path with no folders (just share marker + filename)
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\file.mp3",
            username: "user",
            template: "{username}/{folders}/{filename}"
        )
        // folders is empty, would produce "user//file.mp3" without cleanup
        #expect(result == "user/file.mp3")
        #expect(!result.contains("//"))
    }

    @Test("Multiple empty tokens cleaned up")
    func testMultipleEmptyTokens() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\file.mp3",
            username: "user",
            template: "{username}/{artist}/{album}/{filename}"
        )
        // artist and album both empty with no folders
        #expect(!result.contains("//"))
        #expect(result == "user/file.mp3")
    }

    // MARK: - Custom Templates

    @Test("Custom template with all tokens")
    func testCustomTemplate() {
        let result = DownloadManager.resolveDownloadPath(
            soulseekPath: "@@music\\Electronic\\Daft Punk\\Discovery\\01 One More Time.mp3",
            username: "cooldj",
            template: "{username}/{artist}/{album}/{filename}"
        )
        #expect(result == "cooldj/Daft Punk/Discovery/01 One More Time.mp3")
    }
}
