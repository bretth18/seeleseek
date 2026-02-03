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

struct ByteFormatter {
    static func format(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }

    static func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }
}
