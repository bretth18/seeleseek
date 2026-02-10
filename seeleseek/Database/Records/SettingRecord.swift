import Foundation
import GRDB

/// Database record for settings key-value store
struct SettingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "settings"

    var key: String
    var value: String  // JSON-encoded value
    var updatedAt: Double

    /// Decode a value from the stored JSON
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Create a setting record with an encodable value
    static func create<T: Encodable>(key: String, value: T) throws -> SettingRecord {
        let data = try JSONEncoder().encode(value)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Failed to encode as UTF-8 string"))
        }
        return SettingRecord(
            key: key,
            value: jsonString,
            updatedAt: Date().timeIntervalSince1970
        )
    }
}

/// Transfer history record for statistics
struct TransferHistoryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transfer_history"

    var id: String
    var timestamp: Double
    var filename: String
    var username: String
    var size: Int64
    var duration: Double
    var averageSpeed: Double
    var isDownload: Bool
    var localPath: String?

    // Custom coding for Bool<->Int conversion
    enum CodingKeys: String, CodingKey {
        case id, timestamp, filename, username, size, duration, averageSpeed, isDownload, localPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
        filename = try container.decode(String.self, forKey: .filename)
        username = try container.decode(String.self, forKey: .username)
        size = try container.decode(Int64.self, forKey: .size)
        duration = try container.decode(Double.self, forKey: .duration)
        averageSpeed = try container.decode(Double.self, forKey: .averageSpeed)
        isDownload = (try container.decode(Int.self, forKey: .isDownload)) != 0
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(filename, forKey: .filename)
        try container.encode(username, forKey: .username)
        try container.encode(size, forKey: .size)
        try container.encode(duration, forKey: .duration)
        try container.encode(averageSpeed, forKey: .averageSpeed)
        try container.encode(isDownload ? 1 : 0, forKey: .isDownload)
        try container.encodeIfPresent(localPath, forKey: .localPath)
    }

    init(
        id: String = UUID().uuidString,
        timestamp: Double = Date().timeIntervalSince1970,
        filename: String,
        username: String,
        size: Int64,
        duration: Double,
        averageSpeed: Double,
        isDownload: Bool,
        localPath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filename = filename
        self.username = username
        self.size = size
        self.duration = duration
        self.averageSpeed = averageSpeed
        self.isDownload = isDownload
        self.localPath = localPath
    }

    /// Create from completed transfer
    static func from(_ transfer: Transfer, duration: TimeInterval) -> TransferHistoryRecord {
        let avgSpeed = duration > 0 ? Double(transfer.size) / duration : 0
        return TransferHistoryRecord(
            filename: transfer.filename,
            username: transfer.username,
            size: Int64(transfer.size),
            duration: duration,
            averageSpeed: avgSpeed,
            isDownload: transfer.direction == .download,
            localPath: transfer.localPath?.path
        )
    }
}
