import Foundation
import GRDB

/// Database record for SharedFile (hierarchical file tree) persistence
struct SharedFileRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "shared_files"

    var id: String
    var userSharesId: String
    var parentId: String?
    var filename: String
    var size: Int64
    var bitrate: Int?
    var duration: Int?
    var isDirectory: Bool
    var sortOrder: Int

    // Custom coding for Bool<->Int conversion
    enum CodingKeys: String, CodingKey {
        case id, userSharesId, parentId, filename, size, bitrate, duration, isDirectory, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userSharesId = try container.decode(String.self, forKey: .userSharesId)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        filename = try container.decode(String.self, forKey: .filename)
        size = try container.decode(Int64.self, forKey: .size)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        isDirectory = (try container.decode(Int.self, forKey: .isDirectory)) != 0
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userSharesId, forKey: .userSharesId)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encode(filename, forKey: .filename)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(bitrate, forKey: .bitrate)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(isDirectory ? 1 : 0, forKey: .isDirectory)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    init(
        id: String,
        userSharesId: String,
        parentId: String?,
        filename: String,
        size: Int64,
        bitrate: Int?,
        duration: Int?,
        isDirectory: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.userSharesId = userSharesId
        self.parentId = parentId
        self.filename = filename
        self.size = size
        self.bitrate = bitrate
        self.duration = duration
        self.isDirectory = isDirectory
        self.sortOrder = sortOrder
    }

    /// Convert flat records to hierarchical SharedFile structure
    static func toSharedFiles(from records: [SharedFileRecord]) -> [SharedFile] {
        // Build lookup maps
        var recordsById: [String: SharedFileRecord] = [:]
        var childrenByParentId: [String: [SharedFileRecord]] = [:]

        for record in records {
            recordsById[record.id] = record
            let parentKey = record.parentId ?? "root"
            childrenByParentId[parentKey, default: []].append(record)
        }

        // Sort children by sortOrder
        for key in childrenByParentId.keys {
            childrenByParentId[key]?.sort { $0.sortOrder < $1.sortOrder }
        }

        // Recursively build tree
        func buildFile(from record: SharedFileRecord) -> SharedFile {
            let children = childrenByParentId[record.id]?.map { buildFile(from: $0) }
            return SharedFile(
                id: UUID(uuidString: record.id) ?? UUID(),
                filename: record.filename,
                size: UInt64(record.size),
                bitrate: record.bitrate.map { UInt32($0) },
                duration: record.duration.map { UInt32($0) },
                isDirectory: record.isDirectory,
                children: children
            )
        }

        // Get root-level files
        let rootRecords = childrenByParentId["root"] ?? []
        return rootRecords.map { buildFile(from: $0) }
    }

    /// Flatten hierarchical SharedFile structure to records
    static func from(_ files: [SharedFile], userSharesId: UUID, parentId: UUID? = nil) -> [SharedFileRecord] {
        var records: [SharedFileRecord] = []

        for (index, file) in files.enumerated() {
            let record = SharedFileRecord(
                id: file.id.uuidString,
                userSharesId: userSharesId.uuidString,
                parentId: parentId?.uuidString,
                filename: file.filename,
                size: Int64(file.size),
                bitrate: file.bitrate.map { Int($0) },
                duration: file.duration.map { Int($0) },
                isDirectory: file.isDirectory,
                sortOrder: index
            )
            records.append(record)

            // Recursively process children
            if let children = file.children {
                records.append(contentsOf: from(children, userSharesId: userSharesId, parentId: file.id))
            }
        }

        return records
    }
}
