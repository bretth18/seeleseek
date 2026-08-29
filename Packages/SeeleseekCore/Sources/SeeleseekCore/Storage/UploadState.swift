import Foundation

/// Value snapshot of `UploadManager`'s UI-facing queue state, built by the
/// manager at every queue/slot mutation and applied to `UploadState`.
public struct UploadQueueSnapshot: Sendable {
    public var queuedUploads: [UploadManager.QueuedUpload] = []
    public var activeUploadCount = 0
    public var inFlightTransferCount = 0
    public var maxConcurrentUploads = 5

    public init() {}
}

/// `@MainActor` mirror of the upload manager's queue state — what the
/// transfers UI (and AppState's leech check) observes instead of the
/// manager actor. Fed conflated (`.bufferingNewest(1)`): snapshots carry
/// complete state.
@Observable
@MainActor
public final class UploadState {
    public private(set) var queuedUploads: [UploadManager.QueuedUpload] = []
    public private(set) var activeUploadCount = 0
    public private(set) var inFlightTransferCount = 0
    public private(set) var maxConcurrentUploads = 5

    public var queueDepth: Int { queuedUploads.count }

    /// Summary string for upload slots (e.g. "2/3"). Uses the in-flight
    /// figure — the same one slot gating uses — so the UI can't read "0/5"
    /// while pending handshakes hold all the slots.
    public var slotsSummary: String { "\(inFlightTransferCount)/\(maxConcurrentUploads)" }

    public init() {}

    public func apply(_ s: UploadQueueSnapshot) {
        if queuedUploads.map(\.id) != s.queuedUploads.map(\.id) { queuedUploads = s.queuedUploads }
        if activeUploadCount != s.activeUploadCount { activeUploadCount = s.activeUploadCount }
        if inFlightTransferCount != s.inFlightTransferCount { inFlightTransferCount = s.inFlightTransferCount }
        if maxConcurrentUploads != s.maxConcurrentUploads { maxConcurrentUploads = s.maxConcurrentUploads }
    }
}
