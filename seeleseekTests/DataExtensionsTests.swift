import Testing
import Foundation
@testable import seeleseek

@Suite("Data Extensions Tests")
struct DataExtensionsTests {

    @Test("Read UInt8 at valid offset")
    func testReadUInt8Valid() {
        let data = Data([0x42, 0x00, 0xFF])
        #expect(data.readUInt8(at: 0) == 0x42)
        #expect(data.readUInt8(at: 1) == 0x00)
        #expect(data.readUInt8(at: 2) == 0xFF)
    }

    @Test("Read UInt8 at invalid offset returns nil")
    func testReadUInt8Invalid() {
        let data = Data([0x42])
        #expect(data.readUInt8(at: 1) == nil)
        #expect(data.readUInt8(at: -1) == nil)
        #expect(data.readUInt8(at: 100) == nil)
    }

    @Test("Read UInt32 little-endian")
    func testReadUInt32() {
        // 0x12345678 in little-endian is: 78 56 34 12
        let data = Data([0x78, 0x56, 0x34, 0x12])
        #expect(data.readUInt32(at: 0) == 0x12345678)
    }

    @Test("Read UInt32 at invalid offset returns nil")
    func testReadUInt32Invalid() {
        let data = Data([0x78, 0x56, 0x34]) // Only 3 bytes
        #expect(data.readUInt32(at: 0) == nil)
        #expect(data.readUInt32(at: -1) == nil)
    }

    @Test("Read UInt64 little-endian")
    func testReadUInt64() {
        // 0x123456789ABCDEF0 in little-endian
        let data = Data([0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12])
        #expect(data.readUInt64(at: 0) == 0x123456789ABCDEF0)
    }

    @Test("Read string with length prefix")
    func testReadString() {
        // Length (4 bytes little-endian) + string bytes
        // "Hello" = 5 bytes, so length is [0x05, 0x00, 0x00, 0x00]
        var data = Data()
        data.appendUInt32(5)
        data.append("Hello".data(using: .utf8)!)

        let result = data.readString(at: 0)
        #expect(result?.string == "Hello")
        #expect(result?.bytesConsumed == 9) // 4 + 5
    }

    @Test("Read string with empty content")
    func testReadEmptyString() {
        var data = Data()
        data.appendUInt32(0)

        let result = data.readString(at: 0)
        #expect(result?.string == "")
        #expect(result?.bytesConsumed == 4)
    }

    @Test("Read string with insufficient data returns nil")
    func testReadStringInvalid() {
        // Length says 10 bytes but only 5 provided
        var data = Data()
        data.appendUInt32(10)
        data.append("Hello".data(using: .utf8)!)

        #expect(data.readString(at: 0) == nil)
    }

    @Test("Read bool")
    func testReadBool() {
        let data = Data([0x00, 0x01, 0xFF])
        #expect(data.readBool(at: 0) == false)
        #expect(data.readBool(at: 1) == true)
        #expect(data.readBool(at: 2) == true) // Any non-zero is true
    }

    @Test("Write UInt32 little-endian")
    func testWriteUInt32() {
        var data = Data()
        data.appendUInt32(0x12345678)
        #expect(data == Data([0x78, 0x56, 0x34, 0x12]))
    }

    @Test("Write string with length prefix")
    func testWriteString() {
        var data = Data()
        data.appendString("Hi")

        // Should be: length (2 as UInt32) + "Hi"
        #expect(data.count == 6)
        #expect(data.readUInt32(at: 0) == 2)
        #expect(data.readString(at: 0)?.string == "Hi")
    }

    @Test("Safe subdata extraction")
    func testSafeSubdata() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        #expect(data.safeSubdata(in: 1..<4) == Data([0x02, 0x03, 0x04]))
        #expect(data.safeSubdata(in: 0..<5) == data)
        #expect(data.safeSubdata(in: 0..<0) == Data())

        // Invalid ranges
        #expect(data.safeSubdata(in: -1..<3) == nil)
        #expect(data.safeSubdata(in: 0..<10) == nil)
        // Note: 3..<2 can't be tested — Range traps if lowerBound > upperBound at construction
    }

    @Test("Hex string conversion")
    func testHexString() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(data.hexString == "de ad be ef")
    }

    @Test("Data from hex string")
    func testDataFromHexString() {
        let data = Data(hexString: "de ad be ef")
        #expect(data == Data([0xDE, 0xAD, 0xBE, 0xEF]))

        let dataNoSpaces = Data(hexString: "deadbeef")
        #expect(dataNoSpaces == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }
}
