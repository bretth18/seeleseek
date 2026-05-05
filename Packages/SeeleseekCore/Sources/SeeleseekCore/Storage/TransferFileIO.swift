import Foundation

/// Owns a `FileHandle` for the duration of one in-flight transfer and
/// runs read/write/seek operations on a non-`MainActor` executor.
///
/// `DownloadManager` and `UploadManager` are `@MainActor`, but their
/// transfer loops perform synchronous `FileHandle` I/O for every chunk.
/// Doing that on the main actor blocks UI updates, peer-event dispatch,
/// and Swift's timer-task scheduler — long enough on slow disks (or under
/// memory pressure) to make 30 s receive-timeout watchdogs fire late.
///
/// Hopping each chunk through this actor moves the I/O onto a background
/// thread while keeping the surrounding state mutations (transfer status,
/// progress, statistics) on `MainActor`. The cost is one actor hop per
/// chunk; the benefit is that disk stalls can no longer wedge the main
/// thread.
///
/// `FileHandle` conforms to `Sendable` (it's `@unchecked Sendable` via
/// `NSObject`), so the actor can hold it directly. The actor's serial
/// executor naturally serializes access, which matches `FileHandle`'s
/// per-handle locking on the underlying file descriptor.
actor TransferFileIO {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func read(upTo count: Int) throws -> Data? {
        try handle.read(upToCount: count)
    }

    func seek(to offset: UInt64) throws {
        try handle.seek(toOffset: offset)
    }

    func seekToEnd() throws -> UInt64 {
        try handle.seekToEnd()
    }

    func synchronize() throws {
        try handle.synchronize()
    }

    func close() {
        try? handle.close()
    }
}
