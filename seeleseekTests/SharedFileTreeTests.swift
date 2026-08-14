import Testing
import Foundation
@testable import SeeleseekCore

@Suite("SharedFile tree building")
struct SharedFileTreeTests {

    private func file(_ path: String, size: UInt64 = 1, isPrivate: Bool = false) -> SharedFile {
        SharedFile(filename: path, size: size, isPrivate: isPrivate)
    }

    @Test("Nested paths build the expected hierarchy with aggregated stats")
    func nestedHierarchy() {
        let tree = SharedFile.buildTree(from: [
            file("@@music\\Artist\\Album\\01.mp3", size: 10),
            file("@@music\\Artist\\Album\\02.mp3", size: 20),
            file("@@music\\Artist\\cover.jpg", size: 5),
            file("@@video\\clip.mp4", size: 40),
        ])

        #expect(tree.map(\.filename) == ["@@music", "@@video"], "roots sort alphabetically")
        let music = tree[0]
        #expect(music.isDirectory)
        #expect(music.fileCount == 3)
        #expect(music.size == 35)

        let artist = music.children?.first
        #expect(artist?.filename == "@@music\\Artist")
        // Folders sort before files within a directory.
        #expect(artist?.children?.map(\.displayName) == ["Album", "cover.jpg"])
        let album = artist?.children?.first
        #expect(album?.fileCount == 2)
        #expect(album?.size == 30)
        #expect(album?.children?.map(\.displayName) == ["01.mp3", "02.mp3"])
    }

    @Test("Folder is private only when every descendant is")
    func privatePropagation() {
        let tree = SharedFile.buildTree(from: [
            file("root\\locked\\a.mp3", isPrivate: true),
            file("root\\locked\\b.mp3", isPrivate: true),
            file("root\\open.mp3"),
        ])
        #expect(tree[0].isPrivate == false)
        #expect(tree[0].children?.first?.isPrivate == true)
    }

    @Test("Root-level file surfaces as an empty folder (legacy behavior)")
    func rootLevelFile() {
        let tree = SharedFile.buildTree(from: [file("loose.mp3")])
        #expect(tree.count == 1)
        #expect(tree[0].isDirectory)
        #expect(tree[0].children?.isEmpty == true)
    }

    /// buildTree must stay linear: O(folders²) child scans burn minutes of
    /// CPU on real 250k-folder shares.
    @Test("Mega-share tree builds within the time limit", .timeLimit(.minutes(1)))
    func megaShareScales() {
        var flat: [SharedFile] = []
        flat.reserveCapacity(120_000)
        for artist in 0..<20_000 {
            for album in 0..<2 {
                for track in 0..<3 {
                    flat.append(file("@@music\\artist \(artist)\\album \(album)\\\(track).mp3"))
                }
            }
        }

        let tree = SharedFile.buildTree(from: flat)
        #expect(tree.count == 1)
        #expect(tree[0].fileCount == 120_000)
    }
}
