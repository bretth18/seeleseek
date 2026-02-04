import Foundation
import GRDB

/// Database record for SearchResult persistence
struct SearchResultRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "search_results"

    var id: String
    var queryId: String
    var username: String
    var filename: String
    var size: Int64
    var bitrate: Int?
    var duration: Int?
    var isVBR: Bool
    var freeSlots: Bool
    var uploadSpeed: Int
    var queueLength: Int

    // Custom coding keys to handle Bool<->Int conversion
    enum CodingKeys: String, CodingKey {
        case id, queryId, username, filename, size, bitrate, duration
        case isVBR, freeSlots, uploadSpeed, queueLength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        queryId = try container.decode(String.self, forKey: .queryId)
        username = try container.decode(String.self, forKey: .username)
        filename = try container.decode(String.self, forKey: .filename)
        size = try container.decode(Int64.self, forKey: .size)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        // Decode integers as bools
        isVBR = (try container.decode(Int.self, forKey: .isVBR)) != 0
        freeSlots = (try container.decode(Int.self, forKey: .freeSlots)) != 0
        uploadSpeed = try container.decode(Int.self, forKey: .uploadSpeed)
        queueLength = try container.decode(Int.self, forKey: .queueLength)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(queryId, forKey: .queryId)
        try container.encode(username, forKey: .username)
        try container.encode(filename, forKey: .filename)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(bitrate, forKey: .bitrate)
        try container.encodeIfPresent(duration, forKey: .duration)
        // Encode bools as integers
        try container.encode(isVBR ? 1 : 0, forKey: .isVBR)
        try container.encode(freeSlots ? 1 : 0, forKey: .freeSlots)
        try container.encode(uploadSpeed, forKey: .uploadSpeed)
        try container.encode(queueLength, forKey: .queueLength)
    }

    init(
        id: String,
        queryId: String,
        username: String,
        filename: String,
        size: Int64,
        bitrate: Int?,
        duration: Int?,
        isVBR: Bool,
        freeSlots: Bool,
        uploadSpeed: Int,
        queueLength: Int
    ) {
        self.id = id
        self.queryId = queryId
        self.username = username
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.isVBR = isVBR
        self.freeSlots = freeSlots
        self.uploadSpeed = uploadSpeed
        self.queueLength = queueLength
    }

    /// Convert database record to domain model
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: UUID(uuidString: id) ?? UUID(),
            username: username,
            filename: filename,
            size: UInt64(size),
            bitrate: bitrate.map { UInt32($0) },
            duration: duration.map { UInt32($0) },
            isVBR: isVBR,
            freeSlots: freeSlots,
            uploadSpeed: UInt32(uploadSpeed),
            queueLength: UInt32(queueLength)
        )
    }

    /// Create database record from domain model
    static func from(_ result: SearchResult, queryId: UUID) -> SearchResultRecord {
        SearchResultRecord(
            id: result.id.uuidString,
            queryId: queryId.uuidString,
            username: result.username,
            filename: result.filename,
            size: Int64(result.size),
            bitrate: result.bitrate.map { Int($0) },
            duration: result.duration.map { Int($0) },
            isVBR: result.isVBR,
            freeSlots: result.freeSlots,
            uploadSpeed: Int(result.uploadSpeed),
            queueLength: Int(result.queueLength)
        )
    }
}
