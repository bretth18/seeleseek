import Foundation

// MARK: - Data Reading Extensions (Little-Endian)
extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset < count else { return nil }
        return self[offset]
    }

    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }

    func readUInt64(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[offset + i]) << (i * 8)
        }
        return value
    }

    func readInt32(at offset: Int) -> Int32? {
        guard let uint = readUInt32(at: offset) else { return nil }
        return Int32(bitPattern: uint)
    }

    func readString(at offset: Int) -> (string: String, bytesConsumed: Int)? {
        guard let length = readUInt32(at: offset) else { return nil }
        let stringStart = offset + 4
        let stringEnd = stringStart + Int(length)
        guard stringEnd <= count else { return nil }

        let stringData = self[stringStart..<stringEnd]
        guard let string = String(data: stringData, encoding: .utf8) else {
            return nil
        }
        return (string, 4 + Int(length))
    }

    func readBool(at offset: Int) -> Bool? {
        guard let byte = readUInt8(at: offset) else { return nil }
        return byte != 0
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
