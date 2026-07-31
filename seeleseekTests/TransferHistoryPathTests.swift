import Testing
import Foundation
@testable import seeleseek

/// Verifies `TransferHistoryItem.resolvedLocalPath` never fabricates a
/// downloads-directory path for an upload. Uploads source from anywhere on
/// disk, so the infer fallback produced "file missing" on nearly every
/// upload history row (v1.1.21 bug 3).
@Suite("TransferHistoryItem path resolution")
struct TransferHistoryPathTests {

    private func item(isDownload: Bool, localPath: URL?) -> TransferHistoryItem {
        TransferHistoryItem(
            id: UUID().uuidString,
            timestamp: Date(),
            filename: "@@share\\Music\\Artist\\song.flac",
            username: "alice",
            size: 1_000,
            duration: 2,
            averageSpeed: 500,
            isDownload: isDownload,
            localPath: localPath
        )
    }

    @Test("Upload with no stored path resolves to nil, never an inferred download path")
    func uploadWithoutPathResolvesNil() {
        let upload = item(isDownload: false, localPath: nil)
        #expect(upload.resolvedLocalPath == nil)
        #expect(upload.fileExists == false)
    }

    @Test("Upload with a stored path that exists on disk resolves to it")
    func uploadWithLivePathResolves() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-path-test-\(UUID().uuidString).flac")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let upload = item(isDownload: false, localPath: file)
        #expect(upload.resolvedLocalPath == file)
        #expect(upload.fileExists == true)
    }

    @Test("Upload with a stored path that no longer exists resolves to nil")
    func uploadWithDeadPathResolvesNil() {
        let dead = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).flac")
        let upload = item(isDownload: false, localPath: dead)
        #expect(upload.resolvedLocalPath == nil)
    }

    @Test("Download with no stored path may still infer, but never crashes")
    func downloadWithoutPathInfers() {
        let download = item(isDownload: true, localPath: nil)
        // The inferred path only resolves when the file exists on disk;
        // with a fabricated filename it must be nil, not a bogus URL.
        #expect(download.resolvedLocalPath == nil)
    }
}
