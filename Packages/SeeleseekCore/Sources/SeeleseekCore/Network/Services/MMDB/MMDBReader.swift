import Foundation

/// Pure-Swift reader for MaxMind DB (MMDB) format, as used by the GeoLite2
/// country/city/ASN databases.
///
/// Spec: https://maxmind.github.io/MaxMind-DB/
///
/// Scope: full data-section decoder, tree-walker, and metadata parser. No
/// writer. No network fetching. No City-specific typed accessors — use
/// `lookup(address:)` and destructure the returned `MMDBValue`.
///
/// Thread-safety: the reader holds a reference to immutable `Data` and has
/// no mutable state, so it's `Sendable` and can be used from any isolation
/// domain without serialization.
public final class MMDBReader: @unchecked Sendable {

    // MARK: - Public types

    public enum Error: Swift.Error, Equatable, Sendable {
        case metadataNotFound
        case invalidFormat(String)
        case invalidAddress(String)
        case outOfBounds
        case unsupportedExtendedType(UInt8)
    }

    public struct Metadata: Sendable, Equatable {
        public let binaryFormatMajorVersion: UInt16
        public let binaryFormatMinorVersion: UInt16
        public let buildEpoch: UInt64
        public let databaseType: String
        public let description: [String: String]
        public let ipVersion: UInt16
        public let languages: [String]
        public let nodeCount: UInt32
        public let recordSize: UInt16
    }

    public indirect enum Value: Sendable, Equatable {
        case pointer(UInt32)
        case string(String)
        case double(Double)
        case float(Float)
        case bytes(Data)
        case uint16(UInt16)
        case uint32(UInt32)
        case uint64(UInt64)
        case uint128(Data)       // 16 bytes, big-endian
        case int32(Int32)
        case bool(Bool)
        case map([String: Value])
        case array([Value])
    }

    // MARK: - State

    public let metadata: Metadata
    private let data: Data
    private let dataSectionStart: Int
    private let nodeCount: Int
    private let recordSize: Int
    private let nodeByteSize: Int

    // MARK: - Init

    public init(data: Data) throws {
        self.data = data

        // 1. Find the metadata marker, searching from the end (metadata lives
        //    in the trailing 128KiB of the file per spec).
        let marker = Data([0xAB, 0xCD, 0xEF] + Array("MaxMind.com".utf8))
        let searchStart = max(0, data.count - 128 * 1024)
        guard let markerRange = data.range(of: marker, in: searchStart..<data.count) else {
            throw Error.metadataNotFound
        }
        let metaStart = markerRange.upperBound

        // 2. Metadata is encoded as a data-section Map whose pointers are
        //    relative to the metadata section (i.e. the byte right after the
        //    marker). Decode with base = metaStart.
        let metadataDecoder = Decoder(data: data, sectionBase: metaStart)
        let (metaValue, _) = try metadataDecoder.decodeValue(at: metaStart)
        guard case .map(let metaMap) = metaValue else {
            throw Error.invalidFormat("metadata is not a map")
        }
        self.metadata = try Self.buildMetadata(from: metaMap)

        // 3. Derive tree geometry + data-section base.
        self.nodeCount = Int(metadata.nodeCount)
        self.recordSize = Int(metadata.recordSize)
        self.nodeByteSize = (recordSize * 2) / 8
        self.dataSectionStart = nodeCount * nodeByteSize + 16  // 16-byte separator
    }

    public convenience init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data)
    }

    // MARK: - Public lookup

    /// Look up an IP address. Returns `nil` if the address isn't in the DB.
    /// Throws on malformed input or corrupt DB.
    public func lookup(address: String) throws -> Value? {
        guard let bits = Self.bitsFor(address: address) else {
            throw Error.invalidAddress(address)
        }
        let isIPv4Input = bits.count == 32

        // For IPv6 DBs, IPv4 addresses are looked up under `::A.B.C.D`
        // (96 zero bits prepended). For IPv4-only DBs (ipVersion == 4),
        // IPv6 input isn't meaningful — reject it.
        if metadata.ipVersion == 4, !isIPv4Input {
            return nil
        }

        let fullBits: [UInt8]
        if metadata.ipVersion == 6, isIPv4Input {
            fullBits = Array(repeating: 0, count: 96) + bits
        } else {
            fullBits = bits
        }

        guard let dataOffset = try walkTree(bits: fullBits) else {
            return nil
        }

        let decoder = Decoder(data: data, sectionBase: dataSectionStart)
        let (value, _) = try decoder.decodeValue(at: dataSectionStart + dataOffset)
        return value
    }

    /// Convenience: for a GeoLite2-Country style record, return the ISO 3166-1
    /// alpha-2 country code under `country.iso_code`. Returns nil if missing.
    public func lookupCountryCode(for address: String) throws -> String? {
        guard case .map(let top) = try lookup(address: address) else { return nil }
        if case .map(let registered) = top["country"],
           case .string(let code) = registered["iso_code"] {
            return code
        }
        if case .map(let represented) = top["registered_country"],
           case .string(let code) = represented["iso_code"] {
            return code
        }
        return nil
    }

    // MARK: - Tree walk

    /// Walks the binary search tree bit-by-bit. Returns a data-section
    /// offset on hit, `nil` on "not found", throws on corruption.
    private func walkTree(bits: [UInt8]) throws -> Int? {
        var nodeIdx = 0
        for bit in bits {
            if nodeIdx >= nodeCount {
                // Shouldn't happen pre-terminal, but bail defensively.
                break
            }
            let recordValue = try readRecord(nodeIdx: nodeIdx, record: Int(bit))

            if recordValue == nodeCount {
                // Explicit "not found" sentinel.
                return nil
            } else if recordValue > nodeCount {
                // Data-section hit — returned offset is relative to the start
                // of the data section (after subtracting the 16-byte separator
                // AND the node_count bias, per spec).
                return recordValue - nodeCount - 16
            } else {
                nodeIdx = recordValue
            }
        }
        return nil
    }

    /// Reads one of the two records at a given tree node. `record` is 0 (left)
    /// or 1 (right). Packing depends on `recordSize` — 24, 28, and 32 bits are
    /// the documented sizes; 28 is the tricky one.
    private func readRecord(nodeIdx: Int, record: Int) throws -> Int {
        let nodeOffset = nodeIdx * nodeByteSize
        guard nodeOffset + nodeByteSize <= data.count else {
            throw Error.outOfBounds
        }

        switch recordSize {
        case 24:
            let base = nodeOffset + record * 3
            return (Int(data[base]) << 16) | (Int(data[base + 1]) << 8) | Int(data[base + 2])
        case 28:
            // Left record = bytes[0..2] + high nibble of byte[3].
            // Right record = low nibble of byte[3] + bytes[4..6].
            let b0 = Int(data[nodeOffset])
            let b1 = Int(data[nodeOffset + 1])
            let b2 = Int(data[nodeOffset + 2])
            let b3 = Int(data[nodeOffset + 3])
            let b4 = Int(data[nodeOffset + 4])
            let b5 = Int(data[nodeOffset + 5])
            let b6 = Int(data[nodeOffset + 6])
            if record == 0 {
                return ((b3 & 0xF0) << 20) | (b0 << 16) | (b1 << 8) | b2
            } else {
                return ((b3 & 0x0F) << 24) | (b4 << 16) | (b5 << 8) | b6
            }
        case 32:
            let base = nodeOffset + record * 4
            return (Int(data[base]) << 24) | (Int(data[base + 1]) << 16)
                 | (Int(data[base + 2]) << 8) | Int(data[base + 3])
        default:
            throw Error.invalidFormat("unsupported record size \(recordSize)")
        }
    }

    // MARK: - Metadata extraction

    private static func buildMetadata(from map: [String: Value]) throws -> Metadata {
        func uintValue(_ key: String) -> UInt64 {
            switch map[key] {
            case .uint16(let v): return UInt64(v)
            case .uint32(let v): return UInt64(v)
            case .uint64(let v): return v
            default: return 0
            }
        }
        func stringValue(_ key: String) -> String {
            if case .string(let s) = map[key] { return s }
            return ""
        }
        func stringMap(_ key: String) -> [String: String] {
            guard case .map(let m) = map[key] else { return [:] }
            var out: [String: String] = [:]
            for (k, v) in m {
                if case .string(let s) = v { out[k] = s }
            }
            return out
        }
        func stringArray(_ key: String) -> [String] {
            guard case .array(let arr) = map[key] else { return [] }
            return arr.compactMap { v in
                if case .string(let s) = v { return s }
                return nil
            }
        }

        return Metadata(
            binaryFormatMajorVersion: UInt16(uintValue("binary_format_major_version")),
            binaryFormatMinorVersion: UInt16(uintValue("binary_format_minor_version")),
            buildEpoch: uintValue("build_epoch"),
            databaseType: stringValue("database_type"),
            description: stringMap("description"),
            ipVersion: UInt16(uintValue("ip_version")),
            languages: stringArray("languages"),
            nodeCount: UInt32(uintValue("node_count")),
            recordSize: UInt16(uintValue("record_size"))
        )
    }

    // MARK: - Address parsing

    /// Converts a dotted-quad IPv4 or colon-hex IPv6 string into an array of
    /// bits, MSB first. Returns nil on malformed input.
    static func bitsFor(address: String) -> [UInt8]? {
        if let bytes = parseIPv4(address) {
            return bitsOf(bytes)
        }
        if let bytes = parseIPv6(address) {
            return bitsOf(bytes)
        }
        return nil
    }

    private static func bitsOf(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 8)
        for byte in bytes {
            for shift in stride(from: 7, through: 0, by: -1) {
                out.append((byte >> UInt8(shift)) & 1)
            }
        }
        return out
    }

    private static func parseIPv4(_ s: String) -> [UInt8]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard let v = UInt16(part), v <= 255 else { return nil }
            bytes.append(UInt8(v))
        }
        return bytes
    }

    private static func parseIPv6(_ s: String) -> [UInt8]? {
        // Delegate to inet_pton — handles ::, embedded IPv4, zone suffixes.
        var addr = in6_addr()
        let ok = s.withCString { cstr -> Int32 in
            inet_pton(AF_INET6, cstr, &addr)
        }
        guard ok == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }
}

// MARK: - Data section decoder

extension MMDBReader {

    /// Decodes the MMDB data-section wire format.
    ///
    /// The format uses a 1-byte control header with a 3-bit type and 5-bit
    /// size, extended when needed. Pointers and container types (Map, Array)
    /// recurse. See: https://maxmind.github.io/MaxMind-DB/#data-section
    struct Decoder {
        let data: Data
        /// Pointers are offsets from this byte — it differs between the
        /// metadata section and the main data section.
        let sectionBase: Int

        /// Decodes the value at an absolute offset. Returns the value and the
        /// offset immediately past it.
        func decodeValue(at offset: Int) throws -> (Value, Int) {
            guard offset < data.count else { throw Error.outOfBounds }
            let control = data[offset]
            var cursor = offset + 1

            let typeBits = (control & 0b1110_0000) >> 5
            let sizeBits = control & 0b0001_1111

            // Pointer is a special case — it has its own size encoding.
            if typeBits == 1 {
                let (ptr, next) = try decodePointer(control: control, start: cursor)
                // Follow the pointer, return its value, but advance past the
                // pointer header itself (not past the target).
                let (resolved, _) = try decodeValue(at: sectionBase + Int(ptr))
                return (resolved, next)
            }

            // Resolve the actual type, including the extended-type escape.
            let resolvedType: UInt8
            if typeBits == 0 {
                // Extended type — next byte + 7.
                guard cursor < data.count else { throw Error.outOfBounds }
                resolvedType = data[cursor] + 7
                cursor += 1
            } else {
                resolvedType = typeBits
            }

            // Read the payload size (except for pointer, handled above).
            let (size, sizeCursor) = try decodeSize(sizeBits: sizeBits, start: cursor)
            cursor = sizeCursor

            return try decodePayload(
                type: resolvedType,
                size: size,
                start: cursor
            )
        }

        // MARK: Pointer

        private func decodePointer(control: UInt8, start: Int) throws -> (UInt32, Int) {
            let ptrSizeSelector = (control & 0b0001_1000) >> 3
            let lowBits = UInt32(control & 0b0000_0111)
            var cursor = start
            var ptr: UInt32

            switch ptrSizeSelector {
            case 0:
                guard cursor + 1 <= data.count else { throw Error.outOfBounds }
                ptr = (lowBits << 8) | UInt32(data[cursor])
                cursor += 1
            case 1:
                guard cursor + 2 <= data.count else { throw Error.outOfBounds }
                ptr = (lowBits << 16)
                    | (UInt32(data[cursor]) << 8)
                    | UInt32(data[cursor + 1])
                ptr = ptr &+ 2048
                cursor += 2
            case 2:
                guard cursor + 3 <= data.count else { throw Error.outOfBounds }
                ptr = (lowBits << 24)
                    | (UInt32(data[cursor]) << 16)
                    | (UInt32(data[cursor + 1]) << 8)
                    | UInt32(data[cursor + 2])
                ptr = ptr &+ 526336
                cursor += 3
            default:  // 3
                guard cursor + 4 <= data.count else { throw Error.outOfBounds }
                ptr = (UInt32(data[cursor]) << 24)
                    | (UInt32(data[cursor + 1]) << 16)
                    | (UInt32(data[cursor + 2]) << 8)
                    | UInt32(data[cursor + 3])
                cursor += 4
            }
            return (ptr, cursor)
        }

        // MARK: Size

        private func decodeSize(sizeBits: UInt8, start: Int) throws -> (Int, Int) {
            var cursor = start
            let size: Int
            switch sizeBits {
            case 0...28:
                size = Int(sizeBits)
            case 29:
                guard cursor < data.count else { throw Error.outOfBounds }
                size = 29 + Int(data[cursor])
                cursor += 1
            case 30:
                guard cursor + 2 <= data.count else { throw Error.outOfBounds }
                size = 285 + (Int(data[cursor]) << 8) + Int(data[cursor + 1])
                cursor += 2
            default:  // 31
                guard cursor + 3 <= data.count else { throw Error.outOfBounds }
                size = 65821
                    + (Int(data[cursor]) << 16)
                    + (Int(data[cursor + 1]) << 8)
                    + Int(data[cursor + 2])
                cursor += 3
            }
            return (size, cursor)
        }

        // MARK: Payload

        private func decodePayload(type: UInt8, size: Int, start: Int) throws -> (Value, Int) {
            switch type {
            case 2:  // UTF-8 string
                guard start + size <= data.count else { throw Error.outOfBounds }
                let slice = data.subdata(in: start..<(start + size))
                let str = String(data: slice, encoding: .utf8) ?? ""
                return (.string(str), start + size)

            case 3:  // Double (IEEE 754, 8 bytes, big-endian)
                guard size == 8, start + 8 <= data.count else { throw Error.outOfBounds }
                let bits = readBigEndianUInt64(at: start)
                return (.double(Double(bitPattern: bits)), start + 8)

            case 4:  // Bytes
                guard start + size <= data.count else { throw Error.outOfBounds }
                return (.bytes(data.subdata(in: start..<(start + size))), start + size)

            case 5:  // uint16
                return (.uint16(UInt16(readBigEndianUInt(at: start, size: size))), start + size)

            case 6:  // uint32
                return (.uint32(UInt32(readBigEndianUInt(at: start, size: size))), start + size)

            case 7:  // Map
                return try decodeMap(entryCount: size, start: start)

            case 8:  // int32 (extended)
                let raw = UInt32(readBigEndianUInt(at: start, size: size))
                return (.int32(Int32(bitPattern: raw)), start + size)

            case 9:  // uint64 (extended)
                return (.uint64(readBigEndianUInt64(at: start, size: size)), start + size)

            case 10:  // uint128 (extended)
                guard start + size <= data.count, size <= 16 else { throw Error.outOfBounds }
                // Left-pad with zeros to full 16 bytes so the value has a
                // canonical representation.
                var bytes = [UInt8](repeating: 0, count: 16 - size)
                bytes.append(contentsOf: data[start..<(start + size)])
                return (.uint128(Data(bytes)), start + size)

            case 11:  // Array (extended)
                return try decodeArray(entryCount: size, start: start)

            case 12:  // Container marker (unused in practice)
                throw Error.unsupportedExtendedType(type)

            case 13:  // End marker
                throw Error.invalidFormat("unexpected end marker")

            case 14:  // Boolean (extended) — size is 0 or 1, no payload bytes
                return (.bool(size != 0), start)

            case 15:  // Float (extended, 4 bytes big-endian)
                guard size == 4, start + 4 <= data.count else { throw Error.outOfBounds }
                let raw = UInt32(readBigEndianUInt(at: start, size: 4))
                return (.float(Float(bitPattern: raw)), start + 4)

            default:
                throw Error.unsupportedExtendedType(type)
            }
        }

        private func decodeMap(entryCount: Int, start: Int) throws -> (Value, Int) {
            var cursor = start
            var out: [String: Value] = [:]
            out.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                let (keyValue, keyEnd) = try decodeValue(at: cursor)
                guard case .string(let key) = keyValue else {
                    throw Error.invalidFormat("map key is not a string")
                }
                cursor = keyEnd
                let (value, valueEnd) = try decodeValue(at: cursor)
                cursor = valueEnd
                out[key] = value
            }
            return (.map(out), cursor)
        }

        private func decodeArray(entryCount: Int, start: Int) throws -> (Value, Int) {
            var cursor = start
            var out: [Value] = []
            out.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                let (value, end) = try decodeValue(at: cursor)
                out.append(value)
                cursor = end
            }
            return (.array(out), cursor)
        }

        // MARK: Big-endian readers

        private func readBigEndianUInt(at offset: Int, size: Int) -> UInt64 {
            guard size > 0 else { return 0 }
            var v: UInt64 = 0
            for i in 0..<size {
                v = (v << 8) | UInt64(data[offset + i])
            }
            return v
        }

        private func readBigEndianUInt64(at offset: Int, size: Int = 8) -> UInt64 {
            readBigEndianUInt(at: offset, size: size)
        }
    }
}
