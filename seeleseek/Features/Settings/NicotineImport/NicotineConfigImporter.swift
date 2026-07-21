import Foundation

/// Values SeeleSeek can adopt from a Nicotine+ `config` file.
struct NicotineConfig: Equatable {
    var username: String?
    var password: String?
    var listenPort: Int?
    var downloadDirectory: String?
    var incompleteDirectory: String?
    var uploadSlots: Int?
    /// KB/s. 0 = unlimited. Same convention as SettingsState.
    var uploadSpeedLimit: Int?
    var downloadSpeedLimit: Int?
    var sharedFolders: [String] = []
    var autojoinRooms: [String] = []
    var ignoredUsers: [String] = []

    var isEmpty: Bool {
        username == nil && password == nil && listenPort == nil
            && downloadDirectory == nil && incompleteDirectory == nil
            && uploadSlots == nil && uploadSpeedLimit == nil && downloadSpeedLimit == nil
            && sharedFolders.isEmpty && autojoinRooms.isEmpty && ignoredUsers.isEmpty
    }
}

/// Reads the Nicotine+ `config` file. The file has INI sections from
/// Python's configparser. Values are Python literals: bare strings, ints,
/// True/False/None, and lists/tuples such as `[('Music', '/path')]`.
/// The parser skips values it cannot read. It does not fail.
enum NicotineConfigImporter {

    /// Returns `$XDG_CONFIG_HOME/nicotine/config`, or
    /// `~/.config/nicotine/config` if XDG_CONFIG_HOME is not set.
    /// Returns nil if the file does not exist.
    static func defaultConfigURL() -> URL? {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let url = base.appendingPathComponent("nicotine/config")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func load(from url: URL) throws -> NicotineConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        return parse(text)
    }

    static func parse(_ text: String) -> NicotineConfig {
        let sections = parseINI(text)
        let server = sections["server"] ?? [:]
        let transfers = sections["transfers"] ?? [:]

        var config = NicotineConfig()
        config.username = nonEmptyString(server["login"])
        config.password = nonEmptyString(server["passw"])

        if case .list(let ports)? = server["portrange"].map(PythonLiteral.parse),
           case .int(let port)? = ports.first,
           (1...65535).contains(port) {
            config.listenPort = port
        }

        config.autojoinRooms = stringList(server["autojoin"])
        var ignored = stringList(server["ignorelist"])
        for banned in stringList(server["banlist"]) where !ignored.contains(banned) {
            ignored.append(banned)
        }
        config.ignoredUsers = ignored

        config.downloadDirectory = nonEmptyString(transfers["downloaddir"])
        config.incompleteDirectory = nonEmptyString(transfers["incompletedir"])
        config.uploadSlots = positiveInt(transfers["uploadslots"])
        config.uploadSpeedLimit = nonNegativeInt(transfers["uploadlimit"])
        config.downloadSpeedLimit = nonNegativeInt(transfers["downloadlimit"])

        var shares = folderPaths(transfers["shared"])
        for path in folderPaths(transfers["buddyshared"]) where !shares.contains(path) {
            shares.append(path)
        }
        config.sharedFolders = shares

        return config
    }

    // MARK: - Value extraction

    private static func nonEmptyString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if case .string(let value) = PythonLiteral.parse(raw), !value.isEmpty {
            return value
        }
        return nil
    }

    private static func positiveInt(_ raw: String?) -> Int? {
        guard let raw, case .int(let value) = PythonLiteral.parse(raw), value > 0 else { return nil }
        return value
    }

    private static func nonNegativeInt(_ raw: String?) -> Int? {
        guard let raw, case .int(let value) = PythonLiteral.parse(raw), value >= 0 else { return nil }
        return value
    }

    private static func stringList(_ raw: String?) -> [String] {
        guard let raw, case .list(let items) = PythonLiteral.parse(raw) else { return [] }
        return items.compactMap {
            if case .string(let value) = $0, !value.isEmpty { return value }
            return nil
        }
    }

    /// Nicotine+ shares are `[('Virtual Name', '/path'), …]`. Some old
    /// configs hold plain path strings. This accepts both shapes.
    private static func folderPaths(_ raw: String?) -> [String] {
        guard let raw, case .list(let items) = PythonLiteral.parse(raw) else { return [] }
        var paths: [String] = []
        for item in items {
            switch item {
            case .string(let path) where !path.isEmpty:
                paths.append(path)
            case .list(let tuple):
                // Path is the last string element of the tuple.
                let strings = tuple.compactMap { element -> String? in
                    if case .string(let value) = element { return value }
                    return nil
                }
                if let path = strings.last, !path.isEmpty {
                    paths.append(path)
                }
            default:
                break
            }
        }
        return paths
    }

    // MARK: - INI parsing

    /// Returns section → key → raw value string. Reads `[section]`
    /// headers, `key = value` pairs, and indented continuation lines.
    private static func parseINI(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var currentSection: String?
        var currentKey: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                currentKey = nil
                continue
            }

            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                currentKey = nil
                continue
            }

            // A continuation line starts with whitespace. It extends the
            // value of the last key.
            if line.first?.isWhitespace == true, let section = currentSection, let key = currentKey {
                sections[section]?[key, default: ""] += " " + trimmed
                continue
            }

            guard let section = currentSection,
                  let separator = trimmed.firstIndex(of: "=")
            else {
                currentKey = nil
                continue
            }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                currentKey = nil
                continue
            }
            sections[section, default: [:]][key] = value
            currentKey = key
        }
        return sections
    }
}

/// Minimal parser for the Python literals configparser writes: quoted
/// strings, ints, True/False/None, and nested lists/tuples. A scalar
/// that does not parse becomes `.string(raw)`. A collection element
/// that does not parse is dropped.
enum PythonLiteral: Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case none
    indirect case list([PythonLiteral])

    static func parse(_ raw: String) -> PythonLiteral {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("(") {
            var cursor = Cursor(trimmed)
            if let value = cursor.parseValue() {
                return value
            }
            return .string(trimmed)
        }
        return scalar(trimmed)
    }

    private static func scalar(_ token: String) -> PythonLiteral {
        switch token {
        case "True": return .bool(true)
        case "False": return .bool(false)
        case "None": return .none
        default:
            if let value = Int(token) {
                return .int(value)
            }
            // Bare string. configparser writes strings without quotes.
            return .string(token)
        }
    }

    private struct Cursor {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) {
            chars = Array(text)
        }

        private var current: Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func skipWhitespace() {
            while let c = current, c.isWhitespace { index += 1 }
        }

        mutating func parseValue() -> PythonLiteral? {
            skipWhitespace()
            switch current {
            case "[", "(":
                return parseCollection()
            case "'", "\"":
                return parseQuoted()
            case nil:
                return nil
            default:
                return parseBareToken()
            }
        }

        private mutating func parseCollection() -> PythonLiteral? {
            guard let open = current else { return nil }
            let close: Character = open == "[" ? "]" : ")"
            index += 1
            var items: [PythonLiteral] = []
            while true {
                skipWhitespace()
                guard let c = current else { return nil }  // unterminated
                if c == close {
                    index += 1
                    return .list(items)
                }
                if c == "," {
                    index += 1
                    continue
                }
                guard let item = parseValue() else { return nil }
                items.append(item)
            }
        }

        private mutating func parseQuoted() -> PythonLiteral? {
            guard let quote = current else { return nil }
            index += 1
            var result = ""
            while let c = current {
                index += 1
                if c == "\\" {
                    if let escaped = current {
                        index += 1
                        switch escaped {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        default: result.append(escaped)
                        }
                    }
                } else if c == quote {
                    return .string(result)
                } else {
                    result.append(c)
                }
            }
            return nil  // unterminated
        }

        private mutating func parseBareToken() -> PythonLiteral? {
            var token = ""
            while let c = current, c != ",", c != "]", c != ")", !c.isWhitespace {
                token.append(c)
                index += 1
            }
            guard !token.isEmpty else { return nil }
            return PythonLiteral.scalar(token)
        }
    }
}
