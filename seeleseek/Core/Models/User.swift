import Foundation

struct User: Identifiable, Hashable, Sendable {
    let id: String
    var username: String
    var status: UserStatus
    var isPrivileged: Bool
    var averageSpeed: UInt32
    var downloadCount: UInt64
    var fileCount: UInt32
    var folderCount: UInt32
    var countryCode: String?

    init(
        username: String,
        status: UserStatus = .offline,
        isPrivileged: Bool = false,
        averageSpeed: UInt32 = 0,
        downloadCount: UInt64 = 0,
        fileCount: UInt32 = 0,
        folderCount: UInt32 = 0,
        countryCode: String? = nil
    ) {
        self.id = username
        self.username = username
        self.status = status
        self.isPrivileged = isPrivileged
        self.averageSpeed = averageSpeed
        self.downloadCount = downloadCount
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.countryCode = countryCode
    }

    var formattedSpeed: String {
        ByteFormatter.formatSpeed(Int64(averageSpeed))
    }

    var statusIcon: String {
        switch status {
        case .offline: "circle.slash"
        case .away: "moon.fill"
        case .online: "circle.fill"
        }
    }
}
