import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Bulk cancel must reach every live row it targets and nothing else, and
/// must fan out to the same two callbacks the per-row cancel uses — those
/// are what actually stop the network work and any sleeping retry.
@Suite("TransferState bulk cancel")
@MainActor
struct TransferStateBulkCancelTests {

    private func download(_ user: String, _ path: String, status: Transfer.TransferStatus = .queued) -> Transfer {
        Transfer(username: user, filename: path, size: 1, direction: .download, status: status)
    }

    /// Records every callback so a test can assert the exact fan-out.
    private final class Spy {
        var cancelRequested: [UUID] = []
        var terminated: [UUID] = []
        init(_ state: TransferState) {
            state.onCancelRequested = { [self] id, isDownload in
                #expect(isDownload, "bulk cancel is downloads-only")
                cancelRequested.append(id)
            }
            state.onDownloadTerminated = { [self] id in terminated.append(id) }
        }
    }

    @Test("cancelFolder stops the peer's folder and nothing else")
    func cancelFolderIsScoped() {
        let state = TransferState()
        let target = download("alice", "@@music\\Artist\\Album\\01.mp3", status: .transferring)
        state.downloads = [
            target,
            download("alice", "@@music\\Artist\\Album\\02.mp3", status: .queued),
            download("alice", "@@music\\Artist\\Album\\03.mp3", status: .waiting),
            download("alice", "@@music\\Artist\\Album\\04.mp3", status: .connecting),
            download("alice", "@@music\\Artist\\Album\\cover.jpg", status: .completed),
            download("alice", "@@music\\Artist\\Album\\05.mp3", status: .failed),
            download("alice", "@@music\\Artist\\Other\\01.mp3"),
            download("bob", "@@music\\Artist\\Album\\01.mp3"),
        ]
        let spy = Spy(state)

        state.cancelFolder(of: target)

        #expect(state.downloads.map(\.status) == [
            .cancelled, .cancelled, .cancelled, .cancelled, .completed, .failed, .queued, .queued
        ])
        let expected = Set(state.downloads.prefix(4).map(\.id))
        #expect(Set(spy.cancelRequested) == expected)
        #expect(Set(spy.terminated) == expected)
        #expect(spy.cancelRequested.count == 4, "one request per row, no duplicates")
    }

    @Test("cancelFolder with a flat share path matches only that peer's other flat files")
    func cancelFolderWithoutFolder() {
        let state = TransferState()
        let target = download("alice", "song.mp3")
        state.downloads = [
            target,
            download("alice", "other.mp3"),
            download("alice", "@@music\\Album\\01.mp3"),
            download("bob", "song.mp3"),
        ]
        #expect(target.folderPath == nil)

        state.cancelFolder(of: target)

        #expect(state.downloads.map(\.status) == [.cancelled, .cancelled, .queued, .queued])
    }

    @Test("cancelFolder from a finished row still cancels its live siblings")
    func cancelFolderFromFinishedRow() {
        let state = TransferState()
        let done = download("alice", "@@music\\Album\\01.mp3", status: .completed)
        state.downloads = [done, download("alice", "@@music\\Album\\02.mp3")]

        state.cancelFolder(of: done)

        #expect(state.downloads.map(\.status) == [.completed, .cancelled])
    }

    @Test("cancelAllDownloads leaves finished rows and uploads alone")
    func cancelAllScope() {
        let state = TransferState()
        state.downloads = [
            download("alice", "a.mp3", status: .queued),
            download("bob", "b.mp3", status: .waiting),
            download("carol", "c.mp3", status: .connecting),
            download("alice", "d.mp3", status: .transferring),
            download("alice", "e.mp3", status: .failed),
            download("alice", "f.mp3", status: .cancelled),
            download("alice", "g.mp3", status: .completed),
        ]
        let upload = Transfer(username: "bob", filename: "u.mp3", size: 1, direction: .upload, status: .transferring)
        state.uploads = [upload]
        let spy = Spy(state)
        #expect(state.hasCancellableDownloads)

        state.cancelAllDownloads()

        #expect(state.downloads.map(\.status) == [
            .cancelled, .cancelled, .cancelled, .cancelled, .failed, .cancelled, .completed
        ])
        #expect(state.uploads == [upload])
        #expect(Set(spy.cancelRequested) == Set(state.downloads.prefix(4).map(\.id)))
        #expect(Set(spy.terminated) == Set(state.downloads.prefix(4).map(\.id)))
        #expect(!state.hasCancellableDownloads)
    }

    @Test("Bulk cancel with nothing live is a no-op")
    func cancelAllNoop() {
        let state = TransferState()
        state.downloads = [download("alice", "a.mp3", status: .completed)]
        let spy = Spy(state)

        state.cancelAllDownloads()
        state.cancelFolder(of: state.downloads[0])

        #expect(state.downloads.map(\.status) == [.completed])
        #expect(spy.cancelRequested.isEmpty)
        #expect(spy.terminated.isEmpty)
    }
}
