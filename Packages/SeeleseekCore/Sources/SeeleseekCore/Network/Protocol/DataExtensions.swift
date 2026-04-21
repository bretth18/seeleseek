import Foundation

// MARK: - Data Reading Extensions (Little-Endian)
// These extensions are nonisolated to allow use from any actor context
public extension Data {
    nonisolated func readUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[self.startIndex.advanced(by: offset)]
    }

    nonisolated func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { bytes in
            UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    nonisolated func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { bytes in
            UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    nonisolated func readUInt64(at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        return withUnsafeBytes { bytes in
            UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
    }

    nonisolated func readInt32(at offset: Int) -> Int32? {
        guard let uint = readUInt32(at: offset) else { return nil }
        return Int32(bitPattern: uint)
    }

    // SECURITY: Maximum string length for protocol parsing
    nonisolated static let maxStringLength: UInt32 = 1_000_000  // 1MB max for any single string

    nonisolated func readString(at offset: Int) -> (string: String, bytesConsumed: Int)? {
        guard let length = readUInt32(at: offset) else { return nil }
        let len = Int(length)

        // SECURITY: Reject excessively long strings to prevent memory exhaustion.
        guard len <= Self.maxStringLength, offset + 4 + len <= count else { return nil }

        let start = self.startIndex.advanced(by: offset + 4)
        let end = start.advanced(by: len)
        let stringData = self[start..<end]

        // Soulseek peers in the wild still send Latin-1 filenames (old Windows
        // clients, non-English locales). Fall back rather than dropping the
        // whole message — isoLatin1 will never fail since every byte maps to a
        // codepoint, so the final `return nil` is only a safety belt.
        if let utf8 = String(data: stringData, encoding: .utf8) {
            return (utf8, 4 + len)
        }
        if let latin1 = String(data: stringData, encoding: .isoLatin1) {
            return (latin1, 4 + len)
        }
        return nil
    }

    nonisolated func readBool(at offset: Int) -> Bool? {
        readUInt8(at: offset).map { $0 != 0 }
    }

    /// Alias for readUInt8
    nonisolated func readByte(at offset: Int) -> UInt8? {
        readUInt8(at: offset)
    }

    // Safe subdata extraction
    nonisolated func safeSubdata(in range: Range<Int>) -> Data? {
        guard range.lowerBound >= 0,
              range.upperBound <= count,
              range.lowerBound <= range.upperBound else {
            return nil
        }
        let start = self.startIndex.advanced(by: range.lowerBound)
        let end = self.startIndex.advanced(by: range.upperBound)
        return self[start..<end]
    }
}

// MARK: - Data Writing Extensions (Little-Endian)
public extension Data {
    nonisolated mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    nonisolated mutating func appendUInt16(_ value: UInt16) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }

    nonisolated mutating func appendUInt32(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { self.append(contentsOf: $0) }
    }

    nonisolated mutating func appendUInt64(_ value: UInt64) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0 )}
    }

    nonisolated mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    nonisolated mutating func appendString(_ string: String) {
        let data = Data(string.utf8)
        appendUInt32(UInt32(data.count))
        append(data)
    }

    nonisolated mutating func appendBool(_ value: Bool) {
        append(value ? 1 : 0)
    }
}

// MARK: - Data Utilities
public extension Data {
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    public init(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        self = data
    }
}
