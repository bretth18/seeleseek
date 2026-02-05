import Foundation

/// User profile information retrieved from peer
struct UserProfile: Identifiable, Sendable {
    var id: String { username }
    let username: String
    var description: String = ""
    var picture: Data?
    var totalUploads: UInt32 = 0
    var queueSize: UInt32 = 0
    var hasFreeSlots: Bool = true
    var averageSpeed: UInt32 = 0
    var sharedFiles: UInt32 = 0
    var sharedFolders: UInt32 = 0
    var likedInterests: [String] = []
    var hatedInterests: [String] = []
    var status: BuddyStatus = .offline
    var isPrivileged: Bool = false
    var countryCode: String?

    init(
        username: String,
        description: String = "",
        picture: Data? = nil,
        totalUploads: UInt32 = 0,
        queueSize: UInt32 = 0,
        hasFreeSlots: Bool = true,
        averageSpeed: UInt32 = 0,
        sharedFiles: UInt32 = 0,
        sharedFolders: UInt32 = 0,
        likedInterests: [String] = [],
        hatedInterests: [String] = [],
        status: BuddyStatus = .offline,
        isPrivileged: Bool = false,
        countryCode: String? = nil
    ) {
        self.username = username
        self.description = description
        self.picture = picture
        self.totalUploads = totalUploads
        self.queueSize = queueSize
        self.hasFreeSlots = hasFreeSlots
        self.averageSpeed = averageSpeed
        self.sharedFiles = sharedFiles
        self.sharedFolders = sharedFolders
        self.likedInterests = likedInterests
        self.hatedInterests = hatedInterests
        self.status = status
        self.isPrivileged = isPrivileged
        self.countryCode = countryCode
    }

    /// Format speed for display (e.g., "1.5 MB/s")
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(averageSpeed), countStyle: .binary) + "/s"
    }

    /// Format file count for display
    var formattedFileCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: sharedFiles)) ?? "\(sharedFiles)"
    }
}
