import Testing
import Foundation
@testable import seeleseek

@Suite("Message Parser Tests")
struct MessageParserTests {

    @Test("Parse frame with valid data")
    func testParseFrameValid() {
        // Frame format: [length: 4 bytes][code: 4 bytes][payload...]
        // Length includes code + payload, so for code only: length = 4
        var data = Data()
        data.appendUInt32(4) // Length of payload (just the code)
        data.appendUInt32(1) // Code = 1 (login)

        let result = MessageParser.parseFrame(from: data)
        #expect(result != nil)
        #expect(result?.frame.code == 1)
        #expect(result?.consumed == 8)
        #expect(result?.frame.payload.isEmpty == true)
    }

    @Test("Parse frame with payload")
    func testParseFrameWithPayload() {
        var data = Data()
        data.appendUInt32(8) // Length: 4 (code) + 4 (payload)
        data.appendUInt32(26) // Code = 26 (file search)
        data.appendUInt32(12345) // Payload: some token

        let result = MessageParser.parseFrame(from: data)
        #expect(result != nil)
        #expect(result?.frame.code == 26)
        #expect(result?.consumed == 12)
        #expect(result?.frame.payload.count == 4)
    }

    @Test("Parse frame with insufficient data returns nil")
    func testParseFrameInsufficientData() {
        // Only 4 bytes, need at least 8
        let data = Data([0x04, 0x00, 0x00, 0x00])
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Parse frame with incomplete payload returns nil")
    func testParseFrameIncompletePayload() {
        var data = Data()
        data.appendUInt32(100) // Claims 100 bytes of payload
        data.appendUInt32(1)   // But only has code (4 bytes)

        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Parse successful login response")
    func testParseLoginResponseSuccess() {
        var payload = Data()
        payload.appendBool(true) // Success
        payload.appendString("Welcome to SoulSeek!")
        payload.appendUInt32(0x0A0B0C0D) // IP address

        let result = MessageParser.parseLoginResponse(payload)

        switch result {
        case .success(let greeting, let ip, _):
            #expect(greeting == "Welcome to SoulSeek!")
            #expect(ip == "10.11.12.13") // Network byte order (big-endian) within LE uint32
        case .failure, .none:
            Issue.record("Expected success response")
        }
    }

    @Test("Parse failed login response")
    func testParseLoginResponseFailure() {
        var payload = Data()
        payload.appendBool(false) // Failure
        payload.appendString("Invalid password")

        let result = MessageParser.parseLoginResponse(payload)

        switch result {
        case .failure(let reason):
            #expect(reason == "Invalid password")
        case .success, .none:
            Issue.record("Expected failure response")
        }
    }

    @Test("Parse user status")
    func testParseGetUserStatus() {
        var payload = Data()
        payload.appendString("testuser")
        payload.appendUInt32(2) // Online
        payload.appendBool(true) // Privileged

        let result = MessageParser.parseGetUserStatus(payload)
        #expect(result?.username == "testuser")
        #expect(result?.status == .online)
        #expect(result?.privileged == true)
    }

    @Test("Parse private message")
    func testParsePrivateMessage() {
        var payload = Data()
        payload.appendUInt32(123) // Message ID
        payload.appendUInt32(1704067200) // Timestamp
        payload.appendString("sender")
        payload.appendString("Hello there!")
        payload.appendBool(false) // Not admin

        let result = MessageParser.parsePrivateMessage(payload)
        #expect(result?.id == 123)
        #expect(result?.username == "sender")
        #expect(result?.message == "Hello there!")
        #expect(result?.isAdmin == false)
    }

    @Test("Parse with corrupted data returns nil")
    func testParseCorruptedData() {
        // Random garbage data
        let garbage = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01])

        // These should all return nil, not crash
        #expect(MessageParser.parseLoginResponse(garbage) == nil)
        #expect(MessageParser.parseGetUserStatus(garbage) == nil)
        #expect(MessageParser.parsePrivateMessage(garbage) == nil)
    }

    @Test("Parse empty data returns nil")
    func testParseEmptyData() {
        let empty = Data()

        #expect(MessageParser.parseLoginResponse(empty) == nil)
        #expect(MessageParser.parseGetUserStatus(empty) == nil)
        #expect(MessageParser.parseFrame(from: empty) == nil)
    }

    @Test("Frame parsing handles large length gracefully")
    func testParseFrameLargeLength() {
        var data = Data()
        data.appendUInt32(0xFFFFFFFF) // Huge length
        data.appendUInt32(1)

        // Should return nil due to sanity check, not crash
        #expect(MessageParser.parseFrame(from: data) == nil)
    }
}
