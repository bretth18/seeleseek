import Foundation

/// Represents a user in the buddy list
struct Buddy: Identifiable, Codable, Hashable, Sendable {
    var id: String { username }
    let username: String
    var status: BuddyStatus = .offline
    var isPrivileged: Bool = false
    var averageSpeed: UInt32 = 0
    var fileCount: UInt32 = 0
    var folderCount: UInt32 = 0
    var countryCode: String?
    var notes: String?
    var dateAdded: Date = Date()
    var lastSeen: Date?

    init(
        username: String,
        status: BuddyStatus = .offline,
        isPrivileged: Bool = false,
        averageSpeed: UInt32 = 0,
        fileCount: UInt32 = 0,
        folderCount: UInt32 = 0,
        countryCode: String? = nil,
        notes: String? = nil,
        dateAdded: Date = Date(),
        lastSeen: Date? = nil
    ) {
        self.username = username
        self.status = status
        self.isPrivileged = isPrivileged
        self.averageSpeed = averageSpeed
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.countryCode = countryCode
        self.notes = notes
        self.dateAdded = dateAdded
        self.lastSeen = lastSeen
    }
}

/// User online status (mirrors protocol UserStatus but simplified for UI)
enum BuddyStatus: Int, Codable, Hashable, Sendable, Comparable {
    case offline = 0
    case away = 1
    case online = 2

    var description: String {
        switch self {
        case .offline: "Offline"
        case .away: "Away"
        case .online: "Online"
        }
    }

    var color: String {
        switch self {
        case .offline: "gray"
        case .away: "yellow"
        case .online: "green"
        }
    }

    static func < (lhs: BuddyStatus, rhs: BuddyStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Convert from protocol UserStatus
    init(from userStatus: UserStatus) {
        switch userStatus {
        case .offline: self = .offline
        case .away: self = .away
        case .online: self = .online
        }
    }
}
