import Foundation
import Testing
@testable import SeeleseekCore

@MainActor
@Suite("Download folder placement")
struct DownloadFolderPlacementTests {
    private let user = "alice"
    private let folder = #"@@music\Milton\1988 - Eu Sou O Rio"#
    private let tagged = AudioFileMetadata(artist: "Milton Nascimento", album: "Eu Sou O Rio")

    private func makeTempRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seeleseek-placement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The placement work runs in detached tasks; poll rather than sleep a
    /// fixed amount so the suite stays fast when it converges immediately.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func write(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// Issue #75: completed files must land under the configured download
    /// location, not a hardcoded `~/Downloads/SeeleSeek`.
    @Test("Destination honors the configured download location")
    func destinationUsesConfiguredLocation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DownloadManager()
        let settings = MockDownloadSettings(downloadDirectory: root, template: "{folder}/{filename}")
        manager._setSettingsForTest(settings)

        let dest = manager._destinationForTest(soulseekPath: #"\#(folder)\01 track.mp3"#, username: user)
        #expect(dest == root.appendingPathComponent("1988 - Eu Sou O Rio/01 track.mp3"))
    }

    /// Issue #76: a file whose tags are missing must not strand itself in a
    /// folder-name-derived directory while its tagged siblings go elsewhere.
    @Test("Untagged siblings are pulled into the album folder claimed by a tagged file")
    func untaggedFilesFollowTaggedSibling() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DownloadManager()
        let settings = MockDownloadSettings(downloadDirectory: root, template: "{artist} - {album}/{filename}")
        manager._setSettingsForTest(settings)
        let reader = MockMetadataReader()
        manager._setMetadataReaderForTest(reader)
        let tracking = MockTransferTracking()
        manager._setTransferStateForTest(tracking)

        // Folder-derived directory: what every file resolves to without tags.
        let fallbackDir = root.appendingPathComponent("Milton - 1988 - Eu Sou O Rio")
        let albumDir = root.appendingPathComponent("Milton Nascimento - Eu Sou O Rio")

        let untagged = fallbackDir.appendingPathComponent("10 track.mp3")
        let cover = fallbackDir.appendingPathComponent("cover.jpg")
        let taggedFile = fallbackDir.appendingPathComponent("01 track.mp3")
        try write(untagged)
        try write(cover)
        try write(taggedFile)
        reader.metadata[taggedFile] = tagged

        let ids = [untagged: UUID(), cover: UUID(), taggedFile: UUID()]
        for (path, id) in ids {
            let soulseek = #"\#(folder)\\#(path.lastPathComponent)"#
            tracking.downloads.append(Transfer(id: id, username: user, filename: soulseek, size: 1, direction: .download, status: .completed))
        }
        func complete(_ path: URL) {
            manager.organizeCompletedDownload(
                currentPath: path,
                soulseekFilename: #"\#(folder)\\#(path.lastPathComponent)"#,
                username: user,
                transferId: ids[path]!
            )
        }

        // The two untagged files complete first — the ordering that produced
        // the split in the issue.
        complete(untagged)
        complete(cover)
        #expect(await waitUntil { manager._pendingFolderJoinCount == 2 })

        complete(taggedFile)

        let fm = FileManager.default
        #expect(await waitUntil {
            fm.fileExists(atPath: albumDir.appendingPathComponent("10 track.mp3").path)
                && fm.fileExists(atPath: albumDir.appendingPathComponent("cover.jpg").path)
                && fm.fileExists(atPath: albumDir.appendingPathComponent("01 track.mp3").path)
        }, "all three files belong in the album folder claimed by the tagged track")
        #expect(await waitUntil { !fm.fileExists(atPath: fallbackDir.path) },
                "the emptied fallback directory should be pruned")

        // The whole group moves in one batched task; every transfer in it must
        // still be repointed at its own new location.
        for (path, id) in ids {
            #expect(tracking.getTransfer(id: id)?.localPath == albumDir.appendingPathComponent(path.lastPathComponent))
        }

        // A later arrival from the same folder goes straight to the claimed
        // directory, without another move.
        let laterDest = manager._destinationForTest(soulseekPath: #"\#(folder)\11 track.mp3"#, username: user)
        #expect(laterDest == albumDir.appendingPathComponent("11 track.mp3"))
    }

    /// The prune walk deletes empty directories by depth; it must refuse to
    /// start when the vacated directory is not inside the download root, which
    /// happens if the download location changes mid-transfer.
    @Test("Files vacated outside the download root are not pruned")
    func pruneStaysInsideDownloadRoot() async throws {
        let root = try makeTempRoot()
        let elsewhere = try makeTempRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }

        let manager = DownloadManager()
        let settings = MockDownloadSettings(downloadDirectory: root, template: "{artist} - {album}/{filename}")
        manager._setSettingsForTest(settings)
        let reader = MockMetadataReader()
        manager._setMetadataReaderForTest(reader)

        // The file sits under the *old* root, two levels deep, so a depth-only
        // walk would climb out of it.
        let strandedDir = elsewhere.appendingPathComponent("Old Root/Milton - 1988 - Eu Sou O Rio")
        let stranded = strandedDir.appendingPathComponent("01 track.mp3")
        try write(stranded)
        reader.metadata[stranded] = tagged

        manager.organizeCompletedDownload(currentPath: stranded, soulseekFilename: #"\#(folder)\01 track.mp3"#, username: user, transferId: UUID())

        let albumDir = root.appendingPathComponent("Milton Nascimento - Eu Sou O Rio")
        let fm = FileManager.default
        #expect(await waitUntil { fm.fileExists(atPath: albumDir.appendingPathComponent("01 track.mp3").path) })
        #expect(fm.fileExists(atPath: elsewhere.appendingPathComponent("Old Root").path),
                "directories outside the download root must survive the move")
    }

    /// Tags that don't fill the tokens the template uses must not claim the
    /// folder — otherwise a title-only file wins over properly tagged tracks.
    @Test("Partial tags do not claim the folder destination")
    func partialTagsDoNotClaim() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DownloadManager()
        let settings = MockDownloadSettings(downloadDirectory: root, template: "{artist} - {album}/{filename}")
        manager._setSettingsForTest(settings)
        let reader = MockMetadataReader()
        manager._setMetadataReaderForTest(reader)

        let soulseek = #"\#(folder)\10 track.mp3"#
        let file = root.appendingPathComponent("Milton - 1988 - Eu Sou O Rio/10 track.mp3")
        try write(file)
        reader.metadata[file] = AudioFileMetadata(artist: nil, album: nil, title: "Track Ten")

        manager.organizeCompletedDownload(currentPath: file, soulseekFilename: soulseek, username: user, transferId: UUID())

        #expect(await waitUntil { manager._pendingFolderJoinCount == 1 })
        #expect(FileManager.default.fileExists(atPath: file.path), "it stays put until a tagged sibling arrives")
    }

    /// Grouping only exists to reconcile tag-derived paths; path-based
    /// templates already agree across a folder and must stay untouched.
    @Test("Path-based templates skip placement entirely")
    func pathTemplatesSkipPlacement() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = DownloadManager()
        let settings = MockDownloadSettings(downloadDirectory: root, template: "{folder}/{filename}")
        manager._setSettingsForTest(settings)

        let soulseek = #"\#(folder)\01 track.mp3"#
        let file = root.appendingPathComponent("1988 - Eu Sou O Rio/01 track.mp3")
        try write(file)

        // Returns at the `isTagBased` guard without scheduling anything, so
        // there is nothing to wait for.
        manager.organizeCompletedDownload(currentPath: file, soulseekFilename: soulseek, username: user, transferId: UUID())

        #expect(manager._pendingFolderJoinCount == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
