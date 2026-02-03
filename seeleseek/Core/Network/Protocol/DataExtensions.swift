import Foundation

// MARK: - Data Reading Extensions (Little-Endian)
extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[self.startIndex.advanced(by: offset)]
    }

    func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let start = self.startIndex.advanced(by: offset)
        return UInt16(self[start]) | (UInt16(self[start.advanced(by: 1)]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let start = self.startIndex.advanced(by: offset)
        return UInt32(self[start]) |
               (UInt32(self[start.advanced(by: 1)]) << 8) |
               (UInt32(self[start.advanced(by: 2)]) << 16) |
               (UInt32(self[start.advanced(by: 3)]) << 24)
    }

    func readUInt64(at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        let start = self.startIndex.advanced(by: offset)
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[start.advanced(by: i)]) << (i * 8)
        }
        return value
    }

    func readInt32(at offset: Int) -> Int32? {
        guard let uint = readUInt32(at: offset) else { return nil }
        return Int32(bitPattern: uint)
    }

    func readString(at offset: Int) -> (string: String, bytesConsumed: Int)? {
        guard let length = readUInt32(at: offset) else { return nil }

        // Sanity check - strings shouldn't be excessively long
        guard length <= 10_000_000 else { return nil }

        let stringStart = offset + 4
        let stringEnd = stringStart + Int(length)
        guard stringEnd <= count else { return nil }

        let startIndex = self.startIndex.advanced(by: stringStart)
        let endIndex = self.startIndex.advanced(by: stringEnd)
        let stringData = self[startIndex..<endIndex]

        guard let string = String(data: stringData, encoding: .utf8) else {
            // Try Latin-1 as fallback
            guard let fallbackString = String(data: stringData, encoding: .isoLatin1) else {
                return nil
            }
            return (fallbackString, 4 + Int(length))
        }
        return (string, 4 + Int(length))
    }

    func readBool(at offset: Int) -> Bool? {
        guard let byte = readUInt8(at: offset) else { return nil }
        return byte != 0
    }

    /// Alias for readUInt8
    func readByte(at offset: Int) -> UInt8? {
        readUInt8(at: offset)
    }

    // Safe subdata extraction
    func safeSubdata(in range: Range<Int>) -> Data? {
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
extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendUInt64(_ value: UInt64) {
        for i in 0..<8 {
            append(UInt8((value >> (i * 8)) & 0xFF))
        }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendString(_ string: String) {
        let data = string.data(using: .utf8) ?? Data()
        appendUInt32(UInt32(data.count))
        append(data)
    }

    mutating func appendBool(_ value: Bool) {
        append(value ? 1 : 0)
    }
}

// MARK: - Data Utilities
extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    init(hexString: String) {
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
