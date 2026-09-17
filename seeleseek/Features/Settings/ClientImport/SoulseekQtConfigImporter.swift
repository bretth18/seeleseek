import Foundation

/// Reads a SoulseekQt "Export Client Configuration Data" file (`.scd1`;
/// the digit is SoulseekQt's `data_version`). The layout was reverse
/// engineered from a real export:
///
///     u32 tableCount
///     tableCount × { string name, u32 nodeCount, nodeCount × { u32 id, string value } }
///     u32 linkCount
///     linkCount × { u32 id, u32 id }
///
/// Integers are little-endian. A string is `u32 byteCount` + UTF-8 bytes,
/// no terminator. Every node belongs to one table (`global`,
/// `global_value`, `user`, `shared_folder`, …) and holds one string. Links
/// join a setting to its value (`global` → `global_value`) or an entity to
/// an attribute (`user` → `in_user_list`). Link direction is not
/// consistent across tables, so the graph is read as undirected.
enum SoulseekQtConfigImporter {

    struct MalformedFile: LocalizedError {
        let offset: Int
        var errorDescription: String? {
            "This is not a SoulseekQt configuration export (unexpected data at byte \(offset))."
        }
    }

    static func load(from url: URL) throws -> ImportedClientConfig {
        try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> ImportedClientConfig {
        let graph = try SoulseekQtDataGraph(data)
        var config = ImportedClientConfig()

        config.username = graph.global("username")
        config.password = graph.global("password")
        if let port = graph.global("listening_port").flatMap(Int.init), (1...65535).contains(port) {
            config.listenPort = port
        }
        // SoulseekQt writes partial downloads into the download folder
        // itself, so there is no incomplete directory to carry over.
        config.downloadDirectory = graph.global("download_folder")
        if let slots = graph.global("upload_slots").flatMap(Int.init), slots > 0 {
            config.uploadSlots = slots
        }
        config.uploadSpeedLimit = speedLimit(graph, "upload_speed_limit")
        config.downloadSpeedLimit = speedLimit(graph, "download_speed_limit")

        config.sharedFolders = graph.values(in: "shared_folder")
        config.ignoredUsers = graph.entities("user", flaggedBy: "is_ignored")
        config.autojoinRooms = graph.entities("room", flaggedBy: "room_autojoin")
        return config
    }

    /// SoulseekQt keeps the KB/s number and an on/off switch as separate
    /// settings. A switched-off limit is unlimited (0), as in SettingsState.
    private static func speedLimit(_ graph: SoulseekQtDataGraph, _ key: String) -> Int? {
        guard let value = graph.global(key).flatMap(Int.init), value >= 0 else { return nil }
        return SoulseekQtDataGraph.isTrue(graph.global(key + "_enabled")) ? value : 0
    }
}

/// The decoded node graph. Only the lookups the importer needs.
struct SoulseekQtDataGraph {
    private var tableOf: [UInt32: String] = [:]
    private var valueOf: [UInt32: String] = [:]
    /// Node ids per table, in file order.
    private var idsIn: [String: [UInt32]] = [:]
    private var neighbors: [UInt32: [UInt32]] = [:]

    init(_ data: Data) throws {
        var reader = Reader(data)
        let tableCount = try reader.u32()
        for _ in 0..<tableCount {
            let table = try reader.string()
            let nodeCount = try reader.u32()
            for _ in 0..<nodeCount {
                let id = try reader.u32()
                valueOf[id] = try reader.string()
                tableOf[id] = table
                idsIn[table, default: []].append(id)
            }
        }
        let linkCount = try reader.u32()
        for _ in 0..<linkCount {
            let a = try reader.u32()
            let b = try reader.u32()
            neighbors[a, default: []].append(b)
            neighbors[b, default: []].append(a)
        }
    }

    /// The `global_value` linked to the `global` key. Empty strings read as
    /// absent.
    func global(_ key: String) -> String? {
        guard let keyID = idsIn["global"]?.first(where: { valueOf[$0] == key }) else { return nil }
        return neighbors[keyID]?
            .first { tableOf[$0] == "global_value" }
            .flatMap { valueOf[$0] }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Non-empty values of every node in `table`, deduplicated, file order.
    func values(in table: String) -> [String] {
        var seen = Set<String>()
        return (idsIn[table] ?? []).compactMap { id in
            guard let value = valueOf[id], !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    /// Names of `entityTable` nodes that carry a true `flagTable`
    /// attribute, e.g. `user` nodes linked to an `is_ignored` = "1" node.
    /// The real export only showed this shape for `in_user_list` and
    /// `shared_public`; `is_ignored` and `room_autojoin` were empty. If a
    /// flag node has no entity neighbour and is not boolean-looking, its
    /// own value is taken as the name.
    func entities(_ entityTable: String, flaggedBy flagTable: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        func add(_ name: String) {
            if !name.isEmpty, seen.insert(name).inserted { names.append(name) }
        }
        for flagID in idsIn[flagTable] ?? [] {
            let flag = valueOf[flagID] ?? ""
            let linked = (neighbors[flagID] ?? []).filter { tableOf[$0] == entityTable }
            if linked.isEmpty {
                if !Self.isBoolean(flag) { add(flag) }
            } else if Self.isTrue(flag) {
                for id in linked { add(valueOf[id] ?? "") }
            }
        }
        return names
    }

    static func isTrue(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return ["1", "yes", "true"].contains(raw.lowercased())
    }

    private static func isBoolean(_ raw: String) -> Bool {
        isTrue(raw) || ["0", "no", "false"].contains(raw.lowercased())
    }

    private struct Reader {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        mutating func u32() throws -> UInt32 {
            guard offset + 4 <= bytes.count else { throw SoulseekQtConfigImporter.MalformedFile(offset: offset) }
            let value = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            offset += 4
            return value
        }

        mutating func string() throws -> String {
            let start = offset
            let count = Int(try u32())
            guard count <= bytes.count - offset else { throw SoulseekQtConfigImporter.MalformedFile(offset: start) }
            defer { offset += count }
            return String(decoding: bytes[offset..<offset + count], as: UTF8.self)
        }
    }
}
