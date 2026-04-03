import Foundation

public struct User: Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var status: UserStatus
    public var isPrivileged: Bool
    public var averageSpeed: UInt32
    public var downloadCount: UInt64
    public var fileCount: UInt32
    public var folderCount: UInt32
    public var countryCode: String?

    public init(
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

    public var formattedSpeed: String {
        ByteFormatter.formatSpeed(Int64(averageSpeed))
    }

    public var statusIcon: String {
        switch status {
        case .offline: "circle.slash"
        case .away: "moon.fill"
        case .online: "circle.fill"
        }
    }
}
