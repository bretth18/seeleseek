import Foundation

/// The share manager's UI-facing state as one value.
public struct ShareSnapshot: Sendable {
    public var sharedFolders: [ShareManager.SharedFolder] = []
    public var totalFiles = 0
    public var totalSize: UInt64 = 0
    public var isScanning = false
    public var scanProgress: Double = 0
    public var lastScanDate: Date?

    public init() {}
}

/// What the shares-settings UI observes: folder list, counts, and scan
/// progress.
@Observable
@MainActor
public final class ShareState {
    public private(set) var sharedFolders: [ShareManager.SharedFolder] = []
    public private(set) var totalFiles = 0
    public private(set) var totalSize: UInt64 = 0
    public private(set) var isScanning = false
    public private(set) var scanProgress: Double = 0
    public private(set) var lastScanDate: Date?

    public var totalFolders: Int { sharedFolders.count }

    public init() {}

    public func apply(_ s: ShareSnapshot) {
        if sharedFolders != s.sharedFolders { sharedFolders = s.sharedFolders }
        if totalFiles != s.totalFiles { totalFiles = s.totalFiles }
        if totalSize != s.totalSize { totalSize = s.totalSize }
        if isScanning != s.isScanning { isScanning = s.isScanning }
        if scanProgress != s.scanProgress { scanProgress = s.scanProgress }
        if lastScanDate != s.lastScanDate { lastScanDate = s.lastScanDate }
    }
}
