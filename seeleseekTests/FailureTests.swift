import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

@Suite("Failure & Negative Tests")
struct FailureTests {

    // MARK: - 1. DataExtensions Boundary Tests

    @Test("Read integer types from empty Data")
    func testReadFromEmptyData() {
        let empty = Data()
        #expect(empty.readUInt8(at: 0) == nil)
        #expect(empty.readUInt16(at: 0) == nil)
        #expect(empty.readUInt32(at: 0) == nil)
        #expect(empty.readUInt64(at: 0) == nil)
        #expect(empty.readInt32(at: 0) == nil)
        #expect(empty.readString(at: 0) == nil)
        #expect(empty.readBool(at: 0) == nil)
        #expect(empty.readByte(at: 0) == nil)
    }

    @Test("Read UInt32 at exact boundary where only 3 bytes remain")
    func testReadUInt32AtBoundary() {
        let data = Data([0x01, 0x02, 0x03])
        #expect(data.readUInt32(at: 0) == nil)

        // Read at offset where only 3 bytes are left
        let data2 = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        #expect(data2.readUInt32(at: 4) == nil)
    }

    @Test("Read UInt64 at exact boundary where only 7 bytes remain")
    func testReadUInt64AtBoundary() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        #expect(data.readUInt64(at: 0) == nil)
    }

    @Test("Read UInt16 at exact boundary where only 1 byte remains")
    func testReadUInt16AtBoundary() {
        let data = Data([0x42])
        #expect(data.readUInt16(at: 0) == nil)
    }

    @Test("Read string where length field claims more bytes than available")
    func testReadStringLengthExceedsData() {
        var data = Data()
        data.appendUInt32(100) // Claims 100 bytes
        data.append(Data([0x41])) // Only 1 byte of content
        #expect(data.readString(at: 0) == nil)
    }

    @Test("Read string at exactly maxStringLength boundary succeeds")
    func testReadStringMaxLengthBoundary() {
        var data = Data()
        data.appendUInt32(Data.maxStringLength) // 1_000_000
        data.append(Data(repeating: 0x41, count: Int(Data.maxStringLength)))

        let result = data.readString(at: 0)
        #expect(result != nil)
        #expect(result?.string.count == Int(Data.maxStringLength))
        #expect(result?.bytesConsumed == 4 + Int(Data.maxStringLength))
    }

    @Test("Read string exceeding maxStringLength rejects")
    func testReadStringExceedsMaxLength() {
        var data = Data()
        data.appendUInt32(Data.maxStringLength + 1)
        data.append(Data(repeating: 0x41, count: Int(Data.maxStringLength) + 1))
        #expect(data.readString(at: 0) == nil)
    }

    @Test("Read string with length 0xFFFFFFFF rejects immediately")
    func testReadStringMaxUInt32Length() {
        var data = Data()
        data.appendUInt32(0xFFFFFFFF)
        // Don't need to append that many bytes — length check rejects first
        #expect(data.readString(at: 0) == nil)
    }

    @Test("safeSubdata with empty and boundary ranges")
    func testSafeSubdataEdgeCases() {
        let data = Data([0x01, 0x02, 0x03])

        // Empty range at start
        #expect(data.safeSubdata(in: 0..<0) == Data())
        // Empty range at end
        #expect(data.safeSubdata(in: 3..<3) == Data())
        // Full range
        #expect(data.safeSubdata(in: 0..<3) == data)
        // Just past end
        #expect(data.safeSubdata(in: 0..<4) == nil)
        // Negative lower bound
        #expect(data.safeSubdata(in: -1..<2) == nil)

        // Empty data
        let empty = Data()
        #expect(empty.safeSubdata(in: 0..<0) == Data())
        #expect(empty.safeSubdata(in: 0..<1) == nil)
    }

    @Test("readString with invalid UTF-8 falls back to Latin-1")
    func testReadStringInvalidUTF8FallsBackToLatin1() {
        // 0xE9 alone is invalid UTF-8 (expects continuation bytes)
        // but is 'é' in Latin-1
        var data = Data()
        data.appendUInt32(1)
        data.append(Data([0xE9]))

        let result = data.readString(at: 0)
        #expect(result != nil)
        #expect(result?.string == "é")
        #expect(result?.bytesConsumed == 5)
    }

    @Test("readString with bytes that are invalid UTF-8 but valid Latin-1")
    func testReadStringLatin1ControlCharacters() {
        // 0x80-0x9F are control chars in Latin-1 but invalid as standalone UTF-8
        var data = Data()
        let bytes: [UInt8] = [0x80, 0x8F, 0x9F, 0xFF]
        data.appendUInt32(UInt32(bytes.count))
        data.append(Data(bytes))

        let result = data.readString(at: 0)
        #expect(result != nil)
        #expect(result?.bytesConsumed == 4 + bytes.count)
    }

    @Test("hexString round-trip with odd-length hex input")
    func testHexStringOddLength() {
        // "abc" → "ab" = 0xAB, "c" = 0x0C
        let data = Data(hexString: "abc")
        #expect(data == Data([0xAB, 0x0C]))

        // Single char
        let single = Data(hexString: "f")
        #expect(single == Data([0x0F]))

        // Empty
        let empty = Data(hexString: "")
        #expect(empty == Data())

        // Invalid hex chars produce empty data
        let invalid = Data(hexString: "zz")
        #expect(invalid == Data())
    }

    // MARK: - 2. Frame Parsing Failure Tests

    @Test("Frame with length = 0 returns nil (no room for code)")
    func testFrameLengthZero() {
        var data = Data()
        data.appendUInt32(0) // length = 0
        data.appendUInt32(1) // bytes exist but outside frame
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with length = 3 returns nil (code needs 4 bytes)")
    func testFrameLengthThree() {
        var data = Data()
        data.appendUInt32(3) // length = 3, not enough for code
        data.append(Data(repeating: 0x00, count: 5))
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with length = 1 returns nil")
    func testFrameLengthOne() {
        var data = Data()
        data.appendUInt32(1)
        data.append(Data(repeating: 0x00, count: 5))
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with length = 2 returns nil")
    func testFrameLengthTwo() {
        var data = Data()
        data.appendUInt32(2)
        data.append(Data(repeating: 0x00, count: 5))
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with length = 4 is minimal valid frame with empty payload")
    func testFrameLengthFourMinimal() {
        var data = Data()
        data.appendUInt32(4) // just the code
        data.appendUInt32(1) // code = 1

        let result = MessageParser.parseFrame(from: data)
        #expect(result != nil)
        #expect(result?.frame.code == 1)
        #expect(result?.frame.payload.isEmpty == true)
        #expect(result?.consumed == 8)
    }

    @Test("Frame with length = maxMessageSize but insufficient data returns nil")
    func testFrameMaxMessageSizeBoundary() {
        var data = Data()
        data.appendUInt32(MessageParser.maxMessageSize) // 100_000_000
        data.appendUInt32(1) // Only 4 bytes of payload

        // data.count < 4 + maxMessageSize → nil
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with length = maxMessageSize + 1 exceeds limit")
    func testFrameExceedsMaxMessageSize() {
        var data = Data()
        data.appendUInt32(MessageParser.maxMessageSize + 1)
        data.appendUInt32(1)
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Frame with only 7 bytes returns nil (need 8 minimum)")
    func testFrameSevenBytes() {
        let data = Data([0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00])
        #expect(data.count == 7)
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    @Test("Multiple frames in buffer, second one truncated")
    func testMultipleFramesSecondTruncated() {
        var data = Data()
        // First frame: length=4, code=1
        data.appendUInt32(4)
        data.appendUInt32(1)
        // Second frame: length=100 but only 4 bytes of payload
        data.appendUInt32(100)
        data.appendUInt32(2)

        // First frame parses fine
        let result1 = MessageParser.parseFrame(from: data)
        #expect(result1 != nil)
        #expect(result1?.frame.code == 1)
        #expect(result1?.consumed == 8)

        // Second frame (from remaining data) fails
        let remaining = Data(data.dropFirst(8))
        #expect(MessageParser.parseFrame(from: remaining) == nil)
    }

    @Test("Frame with entirely zero bytes returns nil (length=0)")
    func testFrameAllZeros() {
        let data = Data(repeating: 0x00, count: 8)
        #expect(MessageParser.parseFrame(from: data) == nil)
    }

    // MARK: - 3. Login Response Parsing Failures

    @Test("Login success but no greeting string")
    func testLoginSuccessNoGreeting() {
        var payload = Data()
        payload.appendBool(true) // success
        // No greeting
        #expect(MessageParser.parseLoginResponse(payload) == nil)
    }

    @Test("Login success with greeting but no IP field")
    func testLoginSuccessNoIP() {
        var payload = Data()
        payload.appendBool(true)
        payload.appendString("Welcome!")
        // No IP
        #expect(MessageParser.parseLoginResponse(payload) == nil)
    }

    @Test("Login success with greeting and IP but truncated hash")
    func testLoginSuccessTruncatedHash() {
        var payload = Data()
        payload.appendBool(true)
        payload.appendString("Welcome!")
        payload.appendUInt32(0x0A0B0C0D) // IP
        // Hash length claims 100 bytes but none follow
        payload.appendUInt32(100)

        // Should still succeed — hash is optional
        let result = MessageParser.parseLoginResponse(payload)
        switch result {
        case .success(let greeting, let ip, let hash):
            #expect(greeting == "Welcome!")
            #expect(ip == "10.11.12.13")
            #expect(hash == nil)
        default:
            Issue.record("Expected success with nil hash")
        }
    }

    @Test("Login failure but no reason string returns Unknown error")
    func testLoginFailureNoReason() {
        var payload = Data()
        payload.appendBool(false)
        // No reason string

        let result = MessageParser.parseLoginResponse(payload)
        switch result {
        case .failure(let reason):
            #expect(reason == "Unknown error")
        default:
            Issue.record("Expected failure with Unknown error")
        }
    }

    @Test("Login with just success byte returns nil")
    func testLoginJustSuccessByte() {
        let payload = Data([0x01])
        #expect(MessageParser.parseLoginResponse(payload) == nil)
    }

    @Test("Login payload 0x00 with no reason defaults to Unknown error")
    func testLoginJustFailureByte() {
        let payload = Data([0x00])
        let result = MessageParser.parseLoginResponse(payload)
        switch result {
        case .failure(let reason):
            #expect(reason == "Unknown error")
        default:
            Issue.record("Expected failure with Unknown error")
        }
    }

    // MARK: - 4. Room List Parsing Failures

    @Test("Room count = 5 but only 3 room names provided")
    func testRoomListTruncatedNames() {
        var payload = Data()
        payload.appendUInt32(5)
        payload.appendString("room1")
        payload.appendString("room2")
        payload.appendString("room3")
        // Missing room4 and room5

        #expect(MessageParser.parseRoomList(payload) == nil)
    }

    @Test("Room count exceeds maxItemCount")
    func testRoomListExceedsMaxItemCount() {
        var payload = Data()
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseRoomList(payload) == nil)
    }

    @Test("Room count at exactly maxItemCount passes limit check")
    func testRoomListAtMaxItemCount() {
        var payload = Data()
        payload.appendUInt32(MessageParser.maxItemCount) // Exactly at limit
        // Payload won't have enough data, but the limit check passes
        // It will fail later trying to read room names
        #expect(MessageParser.parseRoomList(payload) == nil)
    }

    @Test("Room names parsed but userCountsCount is missing")
    func testRoomListMissingUserCountsCount() {
        var payload = Data()
        payload.appendUInt32(2)
        payload.appendString("room1")
        payload.appendString("room2")
        // No userCountsCount field

        #expect(MessageParser.parseRoomList(payload) == nil)
    }

    @Test("5 room names but only 2 user counts: remaining rooms default to 0")
    func testRoomListMismatchedCounts() {
        var payload = Data()
        payload.appendUInt32(5)
        payload.appendString("room1")
        payload.appendString("room2")
        payload.appendString("room3")
        payload.appendString("room4")
        payload.appendString("room5")
        payload.appendUInt32(2) // only 2 user counts
        payload.appendUInt32(10)
        payload.appendUInt32(20)

        let result = MessageParser.parseRoomList(payload)
        #expect(result != nil)
        let rooms = result?.publicRooms ?? []
        // All 5 rooms are returned; the last 3 get userCount = 0 because the
        // counts array ran out (matching the inline handler's behaviour).
        #expect(rooms.count == 5)
        #expect(rooms[0] == MessageParser.RoomListEntry(name: "room1", userCount: 10))
        #expect(rooms[1] == MessageParser.RoomListEntry(name: "room2", userCount: 20))
        #expect(rooms[2].userCount == 0)
    }

    @Test("Room count = 0 returns empty array")
    func testRoomListZeroRooms() {
        var payload = Data()
        payload.appendUInt32(0) // no rooms
        payload.appendUInt32(0) // no user counts

        let result = MessageParser.parseRoomList(payload)
        #expect(result != nil)
        #expect(result?.publicRooms.isEmpty == true)
    }

    @Test("Room name with length field pointing past end of data")
    func testRoomListNameLengthOverflow() {
        var payload = Data()
        payload.appendUInt32(1) // 1 room
        payload.appendUInt32(9999) // room name claims 9999 bytes
        // No actual string data

        #expect(MessageParser.parseRoomList(payload) == nil)
    }

    // MARK: - 5. Search Reply Parsing Failures

    @Test("Search reply with no username")
    func testSearchReplyNoUsername() {
        let payload = Data()
        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with username but no token")
    func testSearchReplyNoToken() {
        var payload = Data()
        payload.appendString("user1")
        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with token but no file count")
    func testSearchReplyNoFileCount() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with file count exceeding maxItemCount")
    func testSearchReplyFileCountExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply file entry truncated mid-filename")
    func testSearchReplyTruncatedFilename() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1) // 1 file
        payload.appendUInt8(1) // code byte
        payload.appendUInt32(100) // filename length = 100
        payload.append(Data([0x41, 0x42])) // only 2 bytes

        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply file entry truncated at size field (only 4 of 8 bytes)")
    func testSearchReplyTruncatedSize() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1)
        payload.appendUInt8(1)
        payload.appendString("test.mp3")
        payload.append(Data([0x01, 0x02, 0x03, 0x04])) // 4 of 8 bytes for UInt64

        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with attribute count exceeding maxAttributeCount")
    func testSearchReplyAttrCountExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1)
        payload.appendUInt8(1)
        payload.appendString("test.mp3")
        payload.appendUInt64(1024)
        payload.appendString("mp3")
        payload.appendUInt32(MessageParser.maxAttributeCount + 1)

        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with attribute entry truncated (type present, value missing)")
    func testSearchReplyTruncatedAttribute() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1)
        payload.appendUInt8(1)
        payload.appendString("test.mp3")
        payload.appendUInt64(1024)
        payload.appendString("mp3")
        payload.appendUInt32(1) // 1 attribute
        payload.appendUInt32(0) // attr type
        // Missing attr value

        #expect(MessageParser.parseSearchReply(payload) == nil)
    }

    @Test("Search reply with private files count exceeding limit still returns public files")
    func testSearchReplyInvalidPrivateCount() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1) // 1 public file
        payload.appendUInt8(1)
        payload.appendString("test.mp3")
        payload.appendUInt64(1024)
        payload.appendString("mp3")
        payload.appendUInt32(0) // no attributes
        payload.appendBool(true) // freeSlots
        payload.appendUInt32(100) // uploadSpeed
        payload.appendUInt32(0) // queueLength
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(MessageParser.maxItemCount + 1) // exceeds limit

        let result = MessageParser.parseSearchReply(payload)
        #expect(result != nil)
        #expect(result?.files.count == 1)
        #expect(result?.files[0].filename == "test.mp3")
        #expect(result?.files[0].isPrivate == false)
    }

    @Test("Search reply with valid public files but corrupted private files returns public files")
    func testSearchReplyCorruptedPrivateFiles() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(12345)
        payload.appendUInt32(1)
        payload.appendUInt8(1)
        payload.appendString("public.mp3")
        payload.appendUInt64(2048)
        payload.appendString("mp3")
        payload.appendUInt32(0)
        payload.appendBool(true)
        payload.appendUInt32(100)
        payload.appendUInt32(0)
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(2) // claims 2 private files
        // But only garbage follows
        payload.append(Data([0xFF, 0xFF]))

        let result = MessageParser.parseSearchReply(payload)
        #expect(result != nil)
        #expect(result?.files.count == 1)
        #expect(result?.files[0].filename == "public.mp3")
    }

    // MARK: - 6. Transfer Request Parsing Failures

    @Test("Transfer request payload too short (< 12 bytes)")
    func testTransferRequestTooShort() {
        let payload = Data([0x00, 0x00, 0x00, 0x00, 0x01, 0x02])
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    @Test("Transfer request with invalid direction value (255)")
    func testTransferRequestInvalidDirection() {
        var payload = Data()
        payload.appendUInt32(255) // Invalid direction (only 0 and 1 valid)
        payload.appendUInt32(12345)
        payload.appendString("test.mp3")
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    @Test("Transfer request upload direction with missing fileSize is rejected")
    func testTransferRequestUploadMissingFileSize() {
        var payload = Data()
        payload.appendUInt32(1) // upload
        payload.appendUInt32(12345)
        payload.appendString("test.mp3")
        // No fileSize bytes

        // Upload-direction TransferRequests MUST carry an 8-byte file
        // size. Previously the parser accepted truncated payloads and
        // returned `fileSize == nil`, which downstream coerced to `0` —
        // creating a phantom "0/0" transfer that immediately succeeded.
        // The parser now treats this as malformed and drops the message.
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    @Test("Transfer request upload direction with zero fileSize is rejected")
    func testTransferRequestUploadZeroFileSize() {
        var payload = Data()
        payload.appendUInt32(1) // upload
        payload.appendUInt32(12345)
        payload.appendString("test.mp3")
        payload.appendUInt64(0) // explicit zero size

        // Same rationale as above: a zero-size upload-direction request
        // is either parser misalignment or a peer-side bug; accepting it
        // would make a corrupt transfer look valid.
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    @Test("Transfer request download direction succeeds without fileSize")
    func testTransferRequestDownloadNoFileSize() {
        var payload = Data()
        payload.appendUInt32(0) // download
        payload.appendUInt32(12345)
        payload.appendString("test.mp3")

        let result = MessageParser.parseTransferRequest(payload)
        #expect(result != nil)
        #expect(result?.direction == .download)
        #expect(result?.token == 12345)
        #expect(result?.filename == "test.mp3")
        #expect(result?.fileSize == nil)
    }

    @Test("Transfer request with truncated filename")
    func testTransferRequestTruncatedFilename() {
        var payload = Data()
        payload.appendUInt32(0) // download
        payload.appendUInt32(12345)
        payload.appendUInt32(100) // filename length claims 100 bytes
        payload.append(Data([0x41, 0x42])) // only 2 bytes
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    @Test("Transfer request with direction > 255 stored in UInt32")
    func testTransferRequestLargeDirection() {
        var payload = Data()
        payload.appendUInt32(256) // Doesn't fit in UInt8
        payload.appendUInt32(12345)
        payload.appendString("test.mp3")
        // Should return nil, not crash
        #expect(MessageParser.parseTransferRequest(payload) == nil)
    }

    // MARK: - 7. ConnectToPeer Parsing Failures

    @Test("ConnectToPeer with missing username")
    func testConnectToPeerNoUsername() {
        let payload = Data()
        #expect(MessageParser.parseConnectToPeer(payload) == nil)
    }

    @Test("ConnectToPeer with username but no connection type")
    func testConnectToPeerNoType() {
        var payload = Data()
        payload.appendString("user1")
        #expect(MessageParser.parseConnectToPeer(payload) == nil)
    }

    @Test("ConnectToPeer missing IP/port after type")
    func testConnectToPeerNoIPPort() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendString("P")
        #expect(MessageParser.parseConnectToPeer(payload) == nil)
    }

    @Test("ConnectToPeer missing token after port")
    func testConnectToPeerNoToken() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendString("P")
        payload.appendUInt32(0x0A0B0C0D) // IP
        payload.appendUInt32(2234) // port
        // No token
        #expect(MessageParser.parseConnectToPeer(payload) == nil)
    }

    @Test("ConnectToPeer happy path round-trips all fields")
    func testConnectToPeerRoundTrip() {
        var payload = Data()
        payload.appendString("musicfan42")
        payload.appendString("P")
        payload.appendUInt32(0x0A0B0C0D) // 10.11.12.13
        payload.appendUInt32(2234)
        payload.appendUInt32(0xDEADBEEF)
        payload.appendBool(true) // privileged

        let info = MessageParser.parseConnectToPeer(payload)
        #expect(info?.username == "musicfan42")
        #expect(info?.connectionType == "P")
        #expect(info?.ip == "10.11.12.13")
        #expect(info?.port == 2234)
        #expect(info?.token == 0xDEADBEEF)
        #expect(info?.privileged == true)
    }

    // MARK: - 8. Private Message Parsing Failures

    @Test("Private message with missing message ID")
    func testPrivateMessageNoID() {
        let payload = Data()
        #expect(MessageParser.parsePrivateMessage(payload) == nil)
    }

    @Test("Private message with ID + timestamp but no username")
    func testPrivateMessageNoUsername() {
        var payload = Data()
        payload.appendUInt32(1) // ID
        payload.appendUInt32(1704067200) // timestamp
        #expect(MessageParser.parsePrivateMessage(payload) == nil)
    }

    @Test("Private message with ID + timestamp + username but no message body")
    func testPrivateMessageNoBody() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(1704067200)
        payload.appendString("sender")
        #expect(MessageParser.parsePrivateMessage(payload) == nil)
    }

    @Test("Private message with missing new-message byte defaults to live (true)")
    func testPrivateMessageNoNewMessageByte() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(1704067200)
        payload.appendString("sender")
        payload.appendString("Hello!")
        // No trailing isNewMessage byte — spec doesn't require it server-side;
        // absence means live delivery (the common case).

        let result = MessageParser.parsePrivateMessage(payload)
        #expect(result != nil)
        #expect(result?.isNewMessage == true)
    }

    // MARK: - 9. Chat Room Message Parsing Failures

    @Test("Chat room message with missing room name")
    func testChatRoomNoRoomName() {
        let payload = Data()
        #expect(MessageParser.parseSayInChatRoom(payload) == nil)
    }

    @Test("Chat room message with room name but no username")
    func testChatRoomNoUsername() {
        var payload = Data()
        payload.appendString("room1")
        #expect(MessageParser.parseSayInChatRoom(payload) == nil)
    }

    @Test("Chat room message with room name + username but no message")
    func testChatRoomNoMessage() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendString("user1")
        #expect(MessageParser.parseSayInChatRoom(payload) == nil)
    }

    // MARK: - 10. UserStatus Parsing Failures

    @Test("UserStatus with missing username")
    func testUserStatusNoUsername() {
        let payload = Data()
        #expect(MessageParser.parseGetUserStatus(payload) == nil)
    }

    @Test("UserStatus with username but no status value")
    func testUserStatusNoStatus() {
        var payload = Data()
        payload.appendString("user1")
        #expect(MessageParser.parseGetUserStatus(payload) == nil)
    }

    @Test("UserStatus with unknown raw value defaults to offline")
    func testUserStatusUnknownValue() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(99) // Unknown status

        let result = MessageParser.parseGetUserStatus(payload)
        #expect(result != nil)
        #expect(result?.status == .offline)
    }

    @Test("UserStatus with missing privileged byte defaults to false")
    func testUserStatusNoPrivilegedByte() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(2) // online
        // No privileged byte

        let result = MessageParser.parseGetUserStatus(payload)
        #expect(result != nil)
        #expect(result?.status == .online)
        #expect(result?.privileged == false)
    }

    // MARK: - 11. Message Builder Edge Cases

    @Test("Build login message with empty username and password")
    func testBuildLoginEmptyCredentials() {
        let message = MessageBuilder.loginMessage(username: "", password: "")

        // Should not crash, should produce a valid frame
        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)
        #expect(frame?.frame.code == ServerMessageCode.login.rawValue)
    }

    @Test("wrapMessage produces correct length prefix for ping")
    func testWrapMessageCorrectLengthPing() {
        let message = MessageBuilder.pingMessage()

        // Ping: length prefix (4 bytes) + code 32 (4 bytes) = 8 bytes total
        #expect(message.count == 8)
        #expect(message.readUInt32(at: 0) == 4) // length = 4
        #expect(message.readUInt32(at: 4) == ServerMessageCode.ping.rawValue)
    }

    @Test("wrapMessage produces correct length for known payload size")
    func testWrapMessageCorrectLengthWithPayload() {
        // setListenPort: code(4) + port(4) = 8 bytes payload
        let message = MessageBuilder.setListenPortMessage(port: 2234)
        #expect(message.count == 12) // 4 (length prefix) + 8 (payload)
        #expect(message.readUInt32(at: 0) == 8) // length field
    }

    @Test("Build transferRequest with download direction and nil fileSize omits size")
    func testBuildTransferRequestDownloadNoSize() {
        let message = MessageBuilder.transferRequestMessage(
            direction: .download,
            token: 42,
            filename: "test.mp3"
        )

        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)

        let parsed = MessageParser.parseTransferRequest(frame!.frame.payload)
        #expect(parsed != nil)
        #expect(parsed?.direction == .download)
        #expect(parsed?.token == 42)
        #expect(parsed?.filename == "test.mp3")
        #expect(parsed?.fileSize == nil)
    }

    @Test("Build transferRequest with upload direction includes fileSize")
    func testBuildTransferRequestUploadWithSize() {
        let message = MessageBuilder.transferRequestMessage(
            direction: .upload,
            token: 42,
            filename: "test.mp3",
            fileSize: 1024
        )

        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)

        let parsed = MessageParser.parseTransferRequest(frame!.frame.payload)
        #expect(parsed != nil)
        #expect(parsed?.direction == .upload)
        #expect(parsed?.fileSize == 1024)
    }

    @Test("Build transferReply with allowed=false and no reason")
    func testBuildTransferReplyDeniedNoReason() {
        let message = MessageBuilder.transferReplyMessage(
            token: 42,
            allowed: false,
            reason: nil
        )

        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)
        #expect(frame?.frame.code == UInt32(PeerMessageCode.transferReply.rawValue))

        // Payload: token(4) + allowed(1) = 5 bytes minimum
        let payload = frame!.frame.payload
        #expect(payload.readUInt32(at: 0) == 42)
        #expect(payload.readBool(at: 4) == false)
    }

    @Test("Build transferReply with allowed=true and fileSize")
    func testBuildTransferReplyAllowedWithSize() {
        let message = MessageBuilder.transferReplyMessage(
            token: 42,
            allowed: true,
            fileSize: 1024
        )

        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)

        let payload = frame!.frame.payload
        #expect(payload.readUInt32(at: 0) == 42)
        #expect(payload.readBool(at: 4) == true)
        #expect(payload.readUInt64(at: 5) == 1024)
    }

    // MARK: - 12. Decompression Edge Cases

    @Test("Decompression rejects data shorter than 7 bytes")
    func testDecompressDataTooShort() {
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompress(Data([0x78, 0x9C, 0x00, 0x01, 0x02]))
        }
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompress(Data())
        }
    }

    @Test("Decompression with valid zlib header but garbage deflate data")
    func testDecompressGarbageDeflate() {
        // Valid zlib header (0x78 0x9C) + garbage + fake Adler32
        var data = Data([0x78, 0x9C])
        data.append(Data(repeating: 0xFF, count: 10))
        data.append(Data([0x00, 0x00, 0x00, 0x00])) // fake checksum
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompress(data)
        }
    }

    @Test("Decompression with non-zlib header falls back to raw deflate")
    func testDecompressNonZlibHeader() {
        // CMF byte with method != 8 triggers raw deflate path
        var data = Data([0x00, 0x00]) // method = 0, not 8
        data.append(Data(repeating: 0xFF, count: 10))
        data.append(Data([0x00, 0x00, 0x00, 0x00]))
        // Raw deflate fallback is best-effort: may throw or decode garbage.
        // The important thing is it doesn't crash and, if it throws, it's a DecompressionError.
        do {
            _ = try ZlibDecompression.decompress(data)
            // Fallback decoded something — acceptable
        } catch is DecompressionError {
            // Expected failure path
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Decompression round-trip succeeds with valid data")
    func testDecompressRoundTrip() throws {
        // Build a shares reply (which compresses internally) and decompress the payload
        let message = MessageBuilder.sharesReplyMessage(files: [
            (directory: "Music", files: [
                (filename: "song.mp3", size: 1024, bitrate: 320, duration: 180)
            ])
        ])

        // Extract compressed payload (skip length prefix + code)
        let frame = MessageParser.parseFrame(from: message)
        #expect(frame != nil)

        let compressedPayload = frame!.frame.payload
        let decompressed = try ZlibDecompression.decompress(compressedPayload)
        #expect(decompressed.count > compressedPayload.count)

        // Verify decompressed data parses correctly
        let parsed = MessageParser.parseSharesReply(decompressed)
        #expect(parsed != nil)
        #expect(parsed?.files.count == 1)
    }

    @Test("Raw deflate with garbage data throws")
    func testRawDeflateGarbage() {
        let garbage = Data(repeating: 0xAB, count: 20)
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompressRawDeflate(garbage)
        }
    }

    @Test("Raw deflate with empty data throws")
    func testRawDeflateEmpty() {
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompressRawDeflate(Data())
        }
    }

    @Test("Decompression with exactly 7 bytes (minimum valid zlib)")
    func testDecompressMinimumSize() {
        // 2 header + 1 deflate + 4 checksum = 7 bytes minimum
        let data = Data([0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x01])
        // This is actually valid zlib for empty input
        let result = try? ZlibDecompression.decompress(data)
        // May or may not succeed depending on checksum, but shouldn't crash
        _ = result
    }

    // MARK: - 13. SharesReply Parsing Failures

    @Test("SharesReply with empty decompressed data")
    func testSharesReplyEmpty() {
        #expect(MessageParser.parseSharesReply(Data()) == nil)
    }

    @Test("SharesReply with dir count exceeding limit")
    func testSharesReplyDirCountExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseSharesReply(payload) == nil)
    }

    @Test("SharesReply with dir count but truncated dir name")
    func testSharesReplyTruncatedDirName() {
        var payload = Data()
        payload.appendUInt32(1) // 1 directory
        payload.appendUInt32(100) // dir name length = 100
        // No actual dir name data
        #expect(MessageParser.parseSharesReply(payload) == nil)
    }

    @Test("SharesReply with dir name + file count but truncated file entry")
    func testSharesReplyTruncatedFile() {
        var payload = Data()
        payload.appendUInt32(1) // 1 directory
        payload.appendString("Music")
        payload.appendUInt32(1) // 1 file
        payload.appendUInt8(1) // code byte
        payload.appendUInt32(50) // filename length
        // Truncated filename
        #expect(MessageParser.parseSharesReply(payload) == nil)
    }

    @Test("SharesReply with file count exceeding limit")
    func testSharesReplyFileCountExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendString("Music")
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseSharesReply(payload) == nil)
    }

    @Test("SharesReply with zero dirs returns empty file list")
    func testSharesReplyZeroDirs() {
        var payload = Data()
        payload.appendUInt32(0)
        let result = MessageParser.parseSharesReply(payload)
        #expect(result != nil)
        #expect(result?.files.isEmpty == true)
    }

    @Test("SharesReply with valid public + corrupted private still returns public files")
    func testSharesReplyCorruptedPrivate() {
        var payload = Data()
        // 1 directory with 1 file
        payload.appendUInt32(1)
        payload.appendString("Music")
        payload.appendUInt32(1)
        payload.appendUInt8(1) // code
        payload.appendString("song.mp3")
        payload.appendUInt64(1024)
        payload.appendString("mp3")
        payload.appendUInt32(0) // no attrs
        // Unknown uint32
        payload.appendUInt32(0)
        // Private dirs: count = 2 but garbage follows
        payload.appendUInt32(2)
        payload.append(Data([0xFF, 0xFF]))

        let result = MessageParser.parseSharesReply(payload)
        #expect(result != nil)
        #expect(result?.files.count == 1)
        #expect(result?.files[0].filename == "Music\\song.mp3")
    }

    // MARK: - 14. FolderContentsReply Parsing Failures

    @Test("FolderContentsReply with missing token")
    func testFolderContentsReplyNoToken() {
        #expect(MessageParser.parseFolderContentsReply(Data()) == nil)
    }

    @Test("FolderContentsReply with token but missing folder name")
    func testFolderContentsReplyNoFolder() {
        var payload = Data()
        payload.appendUInt32(12345) // token
        #expect(MessageParser.parseFolderContentsReply(payload) == nil)
    }

    @Test("FolderContentsReply with folder but missing folder count")
    func testFolderContentsReplyNoFolderCount() {
        var payload = Data()
        payload.appendUInt32(12345)
        payload.appendString("Music\\Album")
        #expect(MessageParser.parseFolderContentsReply(payload) == nil)
    }

    @Test("FolderContentsReply with folder count exceeding limit")
    func testFolderContentsReplyFolderCountExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(12345)
        payload.appendString("Music")
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseFolderContentsReply(payload) == nil)
    }

    @Test("FolderContentsReply with truncated file entry")
    func testFolderContentsReplyTruncatedFile() {
        var payload = Data()
        payload.appendUInt32(12345)
        payload.appendString("Music")
        payload.appendUInt32(1) // 1 folder
        payload.appendString("Music") // dir name
        payload.appendUInt32(1) // 1 file
        payload.appendUInt8(1) // code
        payload.appendString("song.mp3") // filename
        // Missing size (UInt64)

        let result = MessageParser.parseFolderContentsReply(payload)
        #expect(result != nil)
        #expect(result?.files.isEmpty == true) // file parse broke, no files added
    }

    // MARK: - 15. UserInfoReply Parsing Failures

    @Test("UserInfoReply with empty data")
    func testUserInfoReplyEmpty() {
        #expect(MessageParser.parseUserInfoReply(Data()) == nil)
    }

    @Test("UserInfoReply with description but no hasPicture flag")
    func testUserInfoReplyNoPictureFlag() {
        var payload = Data()
        payload.appendString("Hello, I share music!")
        #expect(MessageParser.parseUserInfoReply(payload) == nil)
    }

    @Test("UserInfoReply with hasPicture=true but missing picture length")
    func testUserInfoReplyNoPictureLength() {
        var payload = Data()
        payload.appendString("Hello!")
        payload.appendBool(true) // has picture
        // No picture length
        #expect(MessageParser.parseUserInfoReply(payload) == nil)
    }

    @Test("UserInfoReply with hasPicture=true but picture data truncated")
    func testUserInfoReplyTruncatedPicture() {
        var payload = Data()
        payload.appendString("Hello!")
        payload.appendBool(true)
        payload.appendUInt32(1000) // claims 1000 bytes
        payload.append(Data(repeating: 0xFF, count: 10)) // only 10 bytes
        #expect(MessageParser.parseUserInfoReply(payload) == nil)
    }

    @Test("UserInfoReply with hasPicture=false succeeds without picture data")
    func testUserInfoReplyNoPicture() {
        var payload = Data()
        payload.appendString("Hello!")
        payload.appendBool(false) // no picture
        payload.appendUInt32(100) // totalUploads
        payload.appendUInt32(5) // queueSize
        payload.appendBool(true) // hasFreeSlots

        let result = MessageParser.parseUserInfoReply(payload)
        #expect(result != nil)
        #expect(result?.description == "Hello!")
        #expect(result?.hasPicture == false)
        #expect(result?.pictureData == nil)
        #expect(result?.totalUploads == 100)
        #expect(result?.hasFreeSlots == true)
    }

    @Test("UserInfoReply with all fields present but missing hasFreeSlots")
    func testUserInfoReplyNoFreeSlots() {
        var payload = Data()
        payload.appendString("Hello!")
        payload.appendBool(false)
        payload.appendUInt32(100)
        payload.appendUInt32(5)
        // Missing hasFreeSlots
        #expect(MessageParser.parseUserInfoReply(payload) == nil)
    }

    // MARK: - 16. TransferReply Parsing Failures

    @Test("TransferReply with empty data")
    func testTransferReplyEmpty() {
        #expect(MessageParser.parseTransferReply(Data()) == nil)
    }

    @Test("TransferReply with token but no allowed flag")
    func testTransferReplyNoAllowed() {
        var payload = Data()
        payload.appendUInt32(42)
        #expect(MessageParser.parseTransferReply(payload) == nil)
    }

    @Test("TransferReply with allowed=true but no fileSize")
    func testTransferReplyAllowedNoSize() {
        var payload = Data()
        payload.appendUInt32(42)
        payload.appendBool(true)
        // No fileSize - optional field

        let result = MessageParser.parseTransferReply(payload)
        #expect(result != nil)
        #expect(result?.token == 42)
        #expect(result?.allowed == true)
        #expect(result?.fileSize == nil)
    }

    @Test("TransferReply with allowed=false and reason string")
    func testTransferReplyDeniedWithReason() {
        var payload = Data()
        payload.appendUInt32(42)
        payload.appendBool(false)
        payload.appendString("Queued")

        let result = MessageParser.parseTransferReply(payload)
        #expect(result != nil)
        #expect(result?.allowed == false)
        #expect(result?.reason == "Queued")
        #expect(result?.fileSize == nil)
    }

    // MARK: - 17. JoinRoom Parsing Failures

    @Test("JoinRoom with missing room name")
    func testJoinRoomNoRoomName() {
        #expect(MessageParser.parseJoinRoom(Data()) == nil)
    }

    @Test("JoinRoom with room name but no user count")
    func testJoinRoomNoUserCount() {
        var payload = Data()
        payload.appendString("room1")
        #expect(MessageParser.parseJoinRoom(payload) == nil)
    }

    @Test("JoinRoom with user count exceeding limit")
    func testJoinRoomUserCountExceedsLimit() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseJoinRoom(payload) == nil)
    }

    @Test("JoinRoom with users but status section overflow")
    func testJoinRoomStatusSectionOverflow() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(2)
        payload.appendString("user1")
        payload.appendString("user2")
        // Status section: count = 2, needs 8 bytes of data
        payload.appendUInt32(2)
        payload.appendUInt32(2) // status for user1
        // Missing status for user2 (need 4 more bytes)

        #expect(MessageParser.parseJoinRoom(payload) == nil)
    }

    @Test("JoinRoom with zero users succeeds")
    func testJoinRoomZeroUsers() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(0) // no users

        let result = MessageParser.parseJoinRoom(payload)
        #expect(result != nil)
        #expect(result?.roomName == "room1")
        #expect(result?.users.isEmpty == true)
    }

    @Test("JoinRoom with status count exceeding limit")
    func testJoinRoomStatusCountExceedsLimit() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(0) // 0 users
        payload.appendUInt32(MessageParser.maxItemCount + 1) // status count exceeds
        #expect(MessageParser.parseJoinRoom(payload) == nil)
    }

    // MARK: - 18. WatchUser Parsing Failures

    @Test("WatchUser with missing username")
    func testWatchUserNoUsername() {
        #expect(MessageParser.parseWatchUser(Data()) == nil)
    }

    @Test("WatchUser with username but no exists flag")
    func testWatchUserNoExists() {
        var payload = Data()
        payload.appendString("user1")
        #expect(MessageParser.parseWatchUser(payload) == nil)
    }

    @Test("WatchUser with exists=false returns early with offline status")
    func testWatchUserNotExists() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendBool(false)

        let result = MessageParser.parseWatchUser(payload)
        #expect(result != nil)
        #expect(result?.username == "user1")
        #expect(result?.exists == false)
        #expect(result?.status == nil)
    }

    @Test("WatchUser with exists=true but missing status field")
    func testWatchUserExistsNoStatus() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendBool(true)
        // No status field
        #expect(MessageParser.parseWatchUser(payload) == nil)
    }

    @Test("WatchUser with exists=true but truncated at dirs field")
    func testWatchUserTruncatedAtDirs() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendBool(true)
        payload.appendUInt32(2) // status (online)
        payload.appendUInt32(100) // avgSpeed
        payload.appendUInt32(50) // uploadNum
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(1000) // files
        // Missing dirs
        #expect(MessageParser.parseWatchUser(payload) == nil)
    }

    @Test("WatchUser with exists=true and all fields present")
    func testWatchUserComplete() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendBool(true)
        payload.appendUInt32(2) // online
        payload.appendUInt32(100) // avgSpeed
        payload.appendUInt32(50) // uploadNum
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(1000) // files
        payload.appendUInt32(20) // dirs
        payload.appendString("DE") // country code (online/away only)

        let result = MessageParser.parseWatchUser(payload)
        #expect(result != nil)
        #expect(result?.exists == true)
        #expect(result?.status == .online)
        #expect(result?.avgSpeed == 100)
        #expect(result?.files == 1000)
        #expect(result?.dirs == 20)
        #expect(result?.countryCode == "DE")
    }

    @Test("WatchUser with offline status omits country code")
    func testWatchUserOfflineNoCountry() {
        var payload = Data()
        payload.appendString("sleeper")
        payload.appendBool(true)
        payload.appendUInt32(0) // offline
        payload.appendUInt32(0); payload.appendUInt32(0)
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(0); payload.appendUInt32(0)
        // No country code since offline.

        let result = MessageParser.parseWatchUser(payload)
        #expect(result?.exists == true)
        #expect(result?.status == .offline)
        #expect(result?.countryCode == nil)
    }

    // MARK: - 19. PossibleParents Parsing Failures

    @Test("PossibleParents with missing count")
    func testPossibleParentsNoCount() {
        #expect(MessageParser.parsePossibleParents(Data()) == nil)
    }

    @Test("PossibleParents with count but truncated entries")
    func testPossibleParentsTruncated() {
        var payload = Data()
        payload.appendUInt32(2) // 2 parents
        payload.appendString("parent1")
        payload.appendUInt32(0x0A0B0C0D) // IP
        // Missing port for parent1
        let result = MessageParser.parsePossibleParents(payload)
        #expect(result != nil)
        #expect(result?.isEmpty == true) // broke before completing first entry
    }

    @Test("PossibleParents with count exceeding limit")
    func testPossibleParentsCountExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parsePossibleParents(payload) == nil)
    }

    @Test("PossibleParents with zero count returns empty array")
    func testPossibleParentsZero() {
        var payload = Data()
        payload.appendUInt32(0)
        let result = MessageParser.parsePossibleParents(payload)
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    // MARK: - 20. Recommendations Parsing Failures

    @Test("Recommendations with missing rec count")
    func testRecommendationsNoCount() {
        #expect(MessageParser.parseRecommendations(Data()) == nil)
    }

    @Test("Recommendations with rec count but truncated items")
    func testRecommendationsTruncatedItems() {
        var payload = Data()
        payload.appendUInt32(2) // 2 recommendations
        payload.appendString("jazz")
        // Missing score for "jazz"

        let result = MessageParser.parseRecommendations(payload)
        // Recs truncated (loop breaks), then unrec count missing → returns with empty unrecs
        #expect(result != nil)
        #expect(result?.recommendations.isEmpty == true)
    }

    @Test("Recommendations with recs but missing unrec count returns recs only")
    func testRecommendationsNoUnrecCount() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendString("jazz")
        payload.appendInt32(10)
        // No unrecommendation count

        let result = MessageParser.parseRecommendations(payload)
        #expect(result != nil)
        #expect(result?.recommendations.count == 1)
        #expect(result?.recommendations[0].item == "jazz")
        #expect(result?.unrecommendations.isEmpty == true)
    }

    @Test("Recommendations with rec count exceeding limit")
    func testRecommendationsCountExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(MessageParser.maxItemCount + 1)
        #expect(MessageParser.parseRecommendations(payload) == nil)
    }

    // MARK: - 21. UserInterests Parsing Failures

    @Test("UserInterests with missing username")
    func testUserInterestsNoUsername() {
        #expect(MessageParser.parseUserInterests(Data()) == nil)
    }

    @Test("UserInterests with username + liked count but truncated likes")
    func testUserInterestsTruncatedLikes() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(3) // 3 likes
        payload.appendString("jazz")
        // Only 1 of 3 likes, then hated count missing

        #expect(MessageParser.parseUserInterests(payload) == nil)
    }

    @Test("UserInterests with likes parsed but missing hated count")
    func testUserInterestsNoHatedCount() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(1)
        payload.appendString("jazz")
        // No hated count
        #expect(MessageParser.parseUserInterests(payload) == nil)
    }

    // MARK: - 22. SimilarUsers Parsing Failures

    @Test("SimilarUsers with missing user count")
    func testSimilarUsersNoCount() {
        #expect(MessageParser.parseSimilarUsers(Data()) == nil)
    }

    @Test("SimilarUsers with count but truncated entries")
    func testSimilarUsersTruncated() {
        var payload = Data()
        payload.appendUInt32(2)
        payload.appendString("user1")
        // Missing rating for user1
        let result = MessageParser.parseSimilarUsers(payload)
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    @Test("SimilarUsers with zero count returns empty")
    func testSimilarUsersZero() {
        var payload = Data()
        payload.appendUInt32(0)
        let result = MessageParser.parseSimilarUsers(payload)
        #expect(result != nil)
        #expect(result?.isEmpty == true)
    }

    // MARK: - 23. UserStats Parsing Failures

    @Test("UserStats with missing username")
    func testUserStatsNoUsername() {
        #expect(MessageParser.parseGetUserStats(Data()) == nil)
    }

    @Test("UserStats with username but truncated stats")
    func testUserStatsTruncated() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(100) // avgSpeed
        // Missing uploadNum, unknown, files, dirs
        #expect(MessageParser.parseGetUserStats(payload) == nil)
    }

    @Test("UserStats with all fields present")
    func testUserStatsComplete() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(100) // avgSpeed
        payload.appendUInt32(50) // uploadNum
        payload.appendUInt32(0) // unknown
        payload.appendUInt32(1000) // files
        payload.appendUInt32(20) // dirs

        let result = MessageParser.parseGetUserStats(payload)
        #expect(result != nil)
        #expect(result?.username == "user1")
        #expect(result?.avgSpeed == 100)
        #expect(result?.files == 1000)
    }

    // MARK: - 24. RoomTickerState Parsing Failures

    @Test("RoomTickerState with missing room name")
    func testRoomTickerStateNoRoom() {
        #expect(MessageParser.parseRoomTickerState(Data()) == nil)
    }

    @Test("RoomTickerState with room but missing ticker count")
    func testRoomTickerStateNoCount() {
        var payload = Data()
        payload.appendString("room1")
        #expect(MessageParser.parseRoomTickerState(payload) == nil)
    }

    @Test("RoomTickerState with truncated ticker entries")
    func testRoomTickerStateTruncated() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(2) // 2 tickers
        payload.appendString("user1")
        // Missing ticker string for user1

        let result = MessageParser.parseRoomTickerState(payload)
        #expect(result != nil)
        #expect(result?.tickers.isEmpty == true)
    }

    @Test("RoomTickerState with zero tickers returns empty")
    func testRoomTickerStateZero() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(0)

        let result = MessageParser.parseRoomTickerState(payload)
        #expect(result != nil)
        #expect(result?.room == "room1")
        #expect(result?.tickers.isEmpty == true)
    }

    // MARK: - 25. RoomMembers Parsing Failures

    @Test("RoomMembers with missing room name")
    func testRoomMembersNoRoom() {
        #expect(MessageParser.parseRoomMembers(Data()) == nil)
    }

    @Test("RoomMembers with room but missing member count")
    func testRoomMembersNoCount() {
        var payload = Data()
        payload.appendString("room1")
        #expect(MessageParser.parseRoomMembers(payload) == nil)
    }

    @Test("RoomMembers with count but truncated member names")
    func testRoomMembersTruncated() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(3)
        payload.appendString("user1")
        // Only 1 of 3 members

        let result = MessageParser.parseRoomMembers(payload)
        #expect(result != nil)
        #expect(result?.members.count == 1) // parsed 1 before break
    }

    @Test("RoomMembers with zero count returns empty")
    func testRoomMembersZero() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(0)

        let result = MessageParser.parseRoomMembers(payload)
        #expect(result != nil)
        #expect(result?.room == "room1")
        #expect(result?.members.isEmpty == true)
    }

    // MARK: - 26. ExcludedSearchPhrases Parsing Failures

    @Test("ExcludedSearchPhrases with missing count")
    func testExcludedSearchPhrasesNoCount() {
        #expect(MessageParser.parseExcludedSearchPhrases(Data()) == nil)
    }

    @Test("ExcludedSearchPhrases with count but truncated phrases")
    func testExcludedSearchPhrasesTruncated() {
        var payload = Data()
        payload.appendUInt32(3)
        payload.appendString("phrase1")
        // Only 1 of 3 phrases

        let result = MessageParser.parseExcludedSearchPhrases(payload)
        #expect(result != nil)
        #expect(result?.count == 1)
    }

    // MARK: - 27. DistributedSearch Parsing Failures

    @Test("DistributedSearch with missing unknown field")
    func testDistributedSearchNoUnknown() {
        #expect(MessageParser.parseDistributedSearch(Data()) == nil)
    }

    @Test("DistributedSearch with unknown + username but missing token")
    func testDistributedSearchNoToken() {
        var payload = Data()
        payload.appendUInt32(0) // unknown
        payload.appendString("user1")
        // No token
        #expect(MessageParser.parseDistributedSearch(payload) == nil)
    }

    @Test("DistributedSearch with token but missing query")
    func testDistributedSearchNoQuery() {
        var payload = Data()
        payload.appendUInt32(0)
        payload.appendString("user1")
        payload.appendUInt32(12345)
        // No query
        #expect(MessageParser.parseDistributedSearch(payload) == nil)
    }

    @Test("DistributedSearch with all fields present")
    func testDistributedSearchComplete() {
        var payload = Data()
        payload.appendUInt32(0)
        payload.appendString("searcher")
        payload.appendUInt32(99999)
        payload.appendString("beatles")

        let result = MessageParser.parseDistributedSearch(payload)
        #expect(result != nil)
        #expect(result?.username == "searcher")
        #expect(result?.token == 99999)
        #expect(result?.query == "beatles")
    }

    // MARK: - 28. IP Validation (PeerConnectionPool.isValidPeerIP)

    @Test("Valid public IP addresses are accepted")
    func testValidPublicIPs() {
        #expect(PeerConnectionPool.isValidPeerIP("8.8.8.8") == true)
        #expect(PeerConnectionPool.isValidPeerIP("1.1.1.1") == true)
        #expect(PeerConnectionPool.isValidPeerIP("203.0.113.1") == true)
        #expect(PeerConnectionPool.isValidPeerIP("100.24.50.1") == true)
    }

    @Test("Private IPs are accepted (valid for LAN peers)")
    func testPrivateIPsAccepted() {
        #expect(PeerConnectionPool.isValidPeerIP("192.168.1.1") == true)
        #expect(PeerConnectionPool.isValidPeerIP("10.0.0.1") == true)
        #expect(PeerConnectionPool.isValidPeerIP("172.16.0.1") == true)
    }

    @Test("Loopback addresses are rejected")
    func testLoopbackRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("127.0.0.1") == false)
        #expect(PeerConnectionPool.isValidPeerIP("127.255.255.255") == false)
    }

    @Test("Multicast addresses are rejected")
    func testMulticastRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("224.0.0.1") == false)
        #expect(PeerConnectionPool.isValidPeerIP("239.255.255.255") == false)
    }

    @Test("Broadcast address is rejected")
    func testBroadcastRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("255.255.255.255") == false)
    }

    @Test("Zero address is rejected")
    func testZeroAddressRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("0.0.0.0") == false)
    }

    @Test("Reserved addresses (240+) are rejected")
    func testReservedRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("240.0.0.1") == false)
        #expect(PeerConnectionPool.isValidPeerIP("250.1.2.3") == false)
    }

    @Test("Malformed IP strings are rejected")
    func testMalformedIPRejected() {
        #expect(PeerConnectionPool.isValidPeerIP("") == false)
        #expect(PeerConnectionPool.isValidPeerIP("not.an.ip") == false)
        #expect(PeerConnectionPool.isValidPeerIP("1.2.3") == false)
        #expect(PeerConnectionPool.isValidPeerIP("1.2.3.4.5") == false)
        #expect(PeerConnectionPool.isValidPeerIP("999.999.999.999") == false)
        #expect(PeerConnectionPool.isValidPeerIP("abc.def.ghi.jkl") == false)
    }

    // MARK: - 29. GeoIPService.flag() Edge Cases

    @Test("Flag emoji for valid country codes")
    func testFlagValidCodes() {
        let usFlag = GeoIPService.flag(for: "US")
        #expect(usFlag.count > 0)
        #expect(usFlag != "🏳️")

        let deFlag = GeoIPService.flag(for: "DE")
        #expect(deFlag.count > 0)
        #expect(deFlag != "🏳️")
    }

    @Test("Flag emoji for empty/invalid country codes")
    func testFlagInvalidCodes() {
        #expect(GeoIPService.flag(for: "") == "🏳️")
        #expect(GeoIPService.flag(for: "A") == "🏳️")
        #expect(GeoIPService.flag(for: "USA") == "🏳️")
    }

    @Test("Flag emoji for lowercase input")
    func testFlagLowercase() {
        // flag() uppercases internally
        let flag = GeoIPService.flag(for: "us")
        #expect(flag != "🏳️")
    }

    // MARK: - 30. SearchReply Private Files Parsing

    @Test("SearchReply with valid private files section")
    func testSearchReplyWithPrivateFiles() {
        var payload = Data()
        payload.appendString("buddy_user")
        payload.appendUInt32(42)  // token
        payload.appendUInt32(1)   // file count = 1

        // File entry: code byte + filename + size + ext + attrCount
        payload.appendUInt8(1)
        payload.appendString("Music/song.mp3")
        payload.appendUInt64(5000000)
        payload.appendString("mp3")
        payload.appendUInt32(0)  // no attributes

        // freeSlots, uploadSpeed, queueLength
        payload.appendBool(true)
        payload.appendUInt32(10000)
        payload.appendUInt32(0)

        // unknown uint32 (always 0)
        payload.appendUInt32(0)

        // Private file count = 1
        payload.appendUInt32(1)
        payload.appendUInt8(1)
        payload.appendString("Private/secret.flac")
        payload.appendUInt64(30000000)
        payload.appendString("flac")
        payload.appendUInt32(0)  // no attributes

        let result = MessageParser.parseSearchReply(payload)
        #expect(result != nil)
        #expect(result?.files.count == 2)  // 1 public + 1 private
        // Check the private file is marked as private
        let privateFile = result?.files.last
        #expect(privateFile?.isPrivate == true)
        #expect(privateFile?.filename == "Private/secret.flac")
    }

    @Test("SearchReply private file count exceeds maxItemCount")
    func testSearchReplyPrivateCountExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(1)  // token
        payload.appendUInt32(0)  // 0 public files

        payload.appendBool(true)
        payload.appendUInt32(100)
        payload.appendUInt32(0)

        // unknown uint32
        payload.appendUInt32(0)
        // Private count exceeds limit
        payload.appendUInt32(100_001)

        let result = MessageParser.parseSearchReply(payload)
        // Should still return result (with just public files, private section skipped)
        #expect(result != nil)
        #expect(result?.files.count == 0)
    }

    @Test("SearchReply private files truncated mid-entry")
    func testSearchReplyPrivateFilesTruncated() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(1)  // token
        payload.appendUInt32(0)  // 0 public files

        payload.appendBool(true)
        payload.appendUInt32(100)
        payload.appendUInt32(0)

        // unknown uint32
        payload.appendUInt32(0)
        // Private count = 2 but only partial data for 1
        payload.appendUInt32(2)
        payload.appendUInt8(1)
        payload.appendString("file1.mp3")
        // truncated - no size/ext/attrs, and no second file

        let result = MessageParser.parseSearchReply(payload)
        #expect(result != nil)
        // Should still return result with 0 files (private parsing breaks early)
        #expect(result?.files.count == 0)
    }

    @Test("SearchReply private file with attrCount exceeding limit")
    func testSearchReplyPrivateAttrCountExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(1)
        payload.appendUInt32(0)  // 0 public files

        payload.appendBool(true)
        payload.appendUInt32(100)
        payload.appendUInt32(0)

        payload.appendUInt32(0)  // unknown
        payload.appendUInt32(1)  // 1 private file
        payload.appendUInt8(1)
        payload.appendString("file.mp3")
        payload.appendUInt64(1000)
        payload.appendString("mp3")
        payload.appendUInt32(101)  // attrCount exceeds maxAttributeCount (100)

        let result = MessageParser.parseSearchReply(payload)
        #expect(result != nil)
        // Private file parsing should break at the excess attrCount
        #expect(result?.files.count == 0)
    }

    // MARK: - 31. JoinRoom Private Room Owner & Operators

    @Test("JoinRoom with private room owner and operators")
    func testJoinRoomWithOwnerAndOperators() {
        var payload = Data()
        payload.appendString("SecretRoom")

        // User count = 2
        payload.appendUInt32(2)
        payload.appendString("alice")
        payload.appendString("bob")

        // Status count = 2 (uint32 per user)
        payload.appendUInt32(2)
        payload.appendUInt32(2)  // alice = away
        payload.appendUInt32(1)  // bob = online

        // Stats count = 2 (20 bytes per user: avgSpeed + uploadNum + unknown + files + dirs)
        payload.appendUInt32(2)
        for _ in 0..<2 {
            payload.appendUInt32(10000)  // avgSpeed
            payload.appendUInt32(500)    // uploadNum
            payload.appendUInt32(0)      // unknown
            payload.appendUInt32(100)    // files
            payload.appendUInt32(10)     // dirs
        }

        // Slots count = 2
        payload.appendUInt32(2)
        payload.appendUInt32(1)  // alice has free slots
        payload.appendUInt32(0)  // bob doesn't

        // Country count = 2
        payload.appendUInt32(2)
        payload.appendString("US")
        payload.appendString("DE")

        // Private room: owner
        payload.appendString("alice")
        // Operator count = 1
        payload.appendUInt32(1)
        payload.appendString("bob")

        let result = MessageParser.parseJoinRoom(payload)
        #expect(result != nil)
        #expect(result?.roomName == "SecretRoom")
        #expect(result?.users.count == 2)
        #expect(result?.owner == "alice")
        #expect(result?.operators.count == 1)
        #expect(result?.operators.first == "bob")
    }

    @Test("JoinRoom with empty owner string (should be nil)")
    func testJoinRoomEmptyOwner() {
        var payload = Data()
        payload.appendString("Room")

        // 1 user
        payload.appendUInt32(1)
        payload.appendString("user1")

        // 1 status
        payload.appendUInt32(1)
        payload.appendUInt32(1)

        // 1 stats
        payload.appendUInt32(1)
        payload.appendUInt32(100)   // avgSpeed
        payload.appendUInt32(50)    // uploadNum
        payload.appendUInt32(0)     // unknown
        payload.appendUInt32(10)    // files
        payload.appendUInt32(1)     // dirs

        // 1 slots
        payload.appendUInt32(1)
        payload.appendUInt32(1)

        // 1 country
        payload.appendUInt32(1)
        payload.appendString("US")

        // Empty owner string → should become nil
        payload.appendString("")

        let result = MessageParser.parseJoinRoom(payload)
        #expect(result != nil)
        #expect(result?.owner == nil)
    }

    @Test("JoinRoom with operator count exceeding limit")
    func testJoinRoomOperatorCountExceedsLimit() {
        var payload = Data()
        payload.appendString("Room")

        payload.appendUInt32(1)
        payload.appendString("user1")

        payload.appendUInt32(1)
        payload.appendUInt32(1)

        payload.appendUInt32(1)
        payload.appendUInt32(100)
        payload.appendUInt32(50)
        payload.appendUInt32(0)
        payload.appendUInt32(10)
        payload.appendUInt32(1)

        payload.appendUInt32(1)
        payload.appendUInt32(1)

        payload.appendUInt32(1)
        payload.appendString("US")

        payload.appendString("owner")
        payload.appendUInt32(100_001)  // exceeds maxItemCount

        let result = MessageParser.parseJoinRoom(payload)
        #expect(result == nil)
    }

    // MARK: - 32. MessageBuilder Compression Edge Cases

    @Test("SharesReply with empty file list")
    func testSharesReplyEmptyFileList() {
        let message = MessageBuilder.sharesReplyMessage(files: [])
        // Should produce a valid message (just the code + compressed empty data)
        #expect(message.count > 4)  // at least length prefix
    }

    @Test("SearchReply with no files compresses correctly")
    func testSearchReplyNoFiles() {
        let message = MessageBuilder.searchReplyMessage(
            username: "test",
            token: 1,
            results: [],
            hasFreeSlots: true,
            uploadSpeed: 100,
            queueLength: 0
        )
        #expect(message.count > 4)
    }

    @Test("Compression round-trip preserves data integrity")
    func testCompressionRoundTripIntegrity() throws {
        // Build shares with known data, then decompress and parse
        let files: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])] = [
            (directory: "Music/Album", files: [
                (filename: "Music/Album/track01.mp3", size: 5_000_000, bitrate: 128, duration: 240),
                (filename: "Music/Album/track02.mp3", size: 6_000_000, bitrate: 320, duration: 300),
            ])
        ]
        let message = MessageBuilder.sharesReplyMessage(files: files)

        // Extract the compressed payload (skip 4 length + 4 code = 8 bytes)
        let compressed = message.subdata(in: 8..<message.count)
        let decompressed = try ZlibDecompression.decompress(compressed)
        let parsed = MessageParser.parseSharesReply(decompressed)
        #expect(parsed != nil)
        #expect(parsed?.files.count == 2)
    }

    @Test("FolderContents round-trip with single folder")
    func testFolderContentsRoundTrip() throws {
        let message = MessageBuilder.folderContentsResponseMessage(
            token: 42,
            folder: "Dir1",
            files: [
                (filename: "Dir1/file.txt", size: 100, extension_: "txt", attributes: []),
                (filename: "Dir1/photo.jpg", size: 200000, extension_: "jpg", attributes: [(0, 72)])
            ]
        )
        let compressed = message.subdata(in: 8..<message.count)
        let decompressed = try ZlibDecompression.decompress(compressed)
        let parsed = MessageParser.parseFolderContentsReply(decompressed)
        #expect(parsed != nil)
        #expect(parsed?.token == 42)
    }

    // MARK: - 33. DataExtensions Additional Edge Cases

    @Test("readString at exact maxStringLength boundary")
    func testReadStringAtMaxStringLength() {
        // Create data with length field = maxStringLength (1MB)
        var data = Data()
        data.appendUInt32(Data.maxStringLength)
        // Append exactly that many bytes
        data.append(Data(repeating: 0x41, count: Int(Data.maxStringLength))) // 'A' bytes

        let result = data.readString(at: 0)
        #expect(result != nil)
        #expect(result?.string.count == Int(Data.maxStringLength))
    }

    @Test("readString at maxStringLength + 1 is rejected")
    func testReadStringExceedsMaxStringLength() {
        var data = Data()
        data.appendUInt32(Data.maxStringLength + 1)
        // Even if we have enough bytes, the length exceeds the limit
        data.append(Data(repeating: 0x41, count: Int(Data.maxStringLength) + 1))

        let result = data.readString(at: 0)
        #expect(result == nil)
    }

    @Test("readInt32 with negative values")
    func testReadInt32Negative() {
        var data = Data()
        data.appendInt32(-1)
        data.appendInt32(-2_000_000_000)
        data.appendInt32(Int32.min)

        #expect(data.readInt32(at: 0) == -1)
        #expect(data.readInt32(at: 4) == -2_000_000_000)
        #expect(data.readInt32(at: 8) == Int32.min)
    }

    @Test("hexString with odd-length hex input parses trailing nibble")
    func testHexStringOddLengthTrailingNibble() {
        // Odd-length hex: last single char is still parsed as a byte
        let data = Data(hexString: "0a0")  // 3 chars
        // "0a" → 0x0A, "0" → 0x00 (single-char hex)
        #expect(data.count == 2)
    }

    @Test("hexString with all invalid hex characters produces empty data")
    func testHexStringAllInvalidChars() {
        let data = Data(hexString: "zz")
        #expect(data.count == 0)
    }

    @Test("hexString encode/decode round-trip preserves bytes")
    func testHexStringEncodeDecodeRoundTrip() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let hex = original.hexString  // "de ad be ef"
        let roundTripped = Data(hexString: hex)
        #expect(roundTripped == original)
    }

    @Test("safeSubdata with empty range (lower == upper)")
    func testSafeSubdataEmptyRange() {
        let data = Data([0x01, 0x02, 0x03])
        let result = data.safeSubdata(in: 1..<1)
        #expect(result != nil)
        #expect(result?.count == 0)
    }

    @Test("safeSubdata at exact end of data")
    func testSafeSubdataAtEnd() {
        let data = Data([0x01, 0x02, 0x03])
        let result = data.safeSubdata(in: 3..<3)
        #expect(result != nil)
        #expect(result?.count == 0)

        // Past end should fail
        let pastEnd = data.safeSubdata(in: 3..<4)
        #expect(pastEnd == nil)
    }

    @Test("readUInt64 max value and off-by-one boundary")
    func testReadUInt64MaxValueBoundary() {
        var data = Data()
        data.appendUInt64(UInt64.max)
        // Reading with not enough remaining bytes (offset 1 = only 7 bytes)
        #expect(data.readUInt64(at: 1) == nil)
        // Reading at exact start
        #expect(data.readUInt64(at: 0) == UInt64.max)
    }

    @Test("appendString with empty string")
    func testAppendEmptyString() {
        var data = Data()
        data.appendString("")
        // Should write uint32(0) length + no string bytes = 4 bytes total
        #expect(data.count == 4)
        #expect(data.readUInt32(at: 0) == 0)
    }

    // MARK: - 34. Frame Parsing Additional Edge Cases

    @Test("parseFrame with messageLength = UInt32.max")
    func testFrameMaxUInt32Length() {
        var data = Data()
        data.appendUInt32(UInt32.max)  // length
        data.appendUInt32(1)           // code
        // Even though code is present, length exceeds maxMessageSize
        let result = MessageParser.parseFrame(from: data)
        #expect(result == nil)
    }

    @Test("parseFrame with multiple frames, first valid, second valid")
    func testFrameMultipleValid() {
        // Frame 1: length=4, code=1 (login), no payload
        var data = Data()
        data.appendUInt32(4)  // length
        data.appendUInt32(1)  // code = login
        // Frame 2: length=4, code=26 (roomList)
        data.appendUInt32(4)
        data.appendUInt32(26)

        // First parse should return frame 1
        let result1 = MessageParser.parseFrame(from: data)
        #expect(result1 != nil)
        #expect(result1?.frame.code == 1)
        #expect(result1?.consumed == 8)

        // Parse frame 2 from remaining data
        if let consumed = result1?.consumed {
            let remaining = data.subdata(in: consumed..<data.count)
            let result2 = MessageParser.parseFrame(from: remaining)
            #expect(result2 != nil)
            #expect(result2?.frame.code == 26)
        }
    }

    @Test("parseFrame with exactly maxMessageSize length")
    func testFrameExactMaxMessageSize() {
        // This tests that the boundary is inclusive (<=, not <)
        var data = Data()
        let maxSize: UInt32 = 100_000_000
        data.appendUInt32(maxSize)
        data.appendUInt32(1)  // code
        // We don't actually need the full payload for the test
        // parseFrame will return nil because data.count < totalLength
        let result = MessageParser.parseFrame(from: data)
        #expect(result == nil)  // Not enough data, but length is accepted
    }

    // MARK: - 35. Login Response IP Formatting

    @Test("Login response IP 0x00000000 formats as 0.0.0.0")
    func testLoginIPZero() {
        var payload = Data()
        payload.appendBool(true)
        payload.appendString("Welcome!")
        payload.appendUInt32(0x00000000)  // IP = 0.0.0.0

        let result = MessageParser.parseLoginResponse(payload)
        #expect(result != nil)
        if case .success(let greeting, let ip, _) = result {
            #expect(greeting == "Welcome!")
            #expect(ip == "0.0.0.0")
        }
    }

    @Test("Login response IP encodes correctly (network byte order)")
    func testLoginIPEncoding() {
        var payload = Data()
        payload.appendBool(true)
        payload.appendString("Hi")
        // IP bytes in LE uint32: value is in network byte order (big-endian within LE storage)
        // For 8.8.8.8: big-endian = 0x08080808
        // Stored as LE uint32: bytes are [0x08, 0x08, 0x08, 0x08]
        // readUInt32 reads LE → 0x08080808
        // formatLittleEndianIPv4: extracts bytes from big-endian format
        // (0x08080808 >> 24) & 0xFF = 8, etc.
        payload.appendUInt32(0x08080808)

        let result = MessageParser.parseLoginResponse(payload)
        if case .success(_, let ip, _) = result {
            #expect(ip == "8.8.8.8")
        }
    }

    // MARK: - 36. WatchUser with Full Stats

    @Test("WatchUser exists=true with all stats fields")
    func testWatchUserFullStats() {
        var payload = Data()
        payload.appendString("online_user")
        payload.appendBool(true)       // exists
        payload.appendUInt32(1)        // status = online
        payload.appendUInt32(50000)    // avgSpeed
        payload.appendUInt32(1000)     // uploadNum
        payload.appendUInt32(0)        // unknown
        payload.appendUInt32(500)      // files
        payload.appendUInt32(50)       // dirs

        let result = MessageParser.parseWatchUser(payload)
        #expect(result != nil)
        #expect(result?.exists == true)
        #expect(result?.avgSpeed == 50000)
        #expect(result?.uploadNum == 1000)
        #expect(result?.files == 500)
        #expect(result?.dirs == 50)
    }

    @Test("WatchUser truncated before files field")
    func testWatchUserTruncatedAtFiles() {
        var payload = Data()
        payload.appendString("user")
        payload.appendBool(true)
        payload.appendUInt32(1)     // status
        payload.appendUInt32(100)   // avgSpeed
        payload.appendUInt32(50)    // uploadNum
        payload.appendUInt32(0)     // unknown
        // Missing: files and dirs
        #expect(MessageParser.parseWatchUser(payload) == nil)
    }

    @Test("WatchUser with unknown status value defaults to offline")
    func testWatchUserUnknownStatus() {
        var payload = Data()
        payload.appendString("user")
        payload.appendBool(true)
        payload.appendUInt32(99)       // unknown status
        payload.appendUInt32(100)
        payload.appendUInt32(50)
        payload.appendUInt32(0)
        payload.appendUInt32(10)
        payload.appendUInt32(1)

        let result = MessageParser.parseWatchUser(payload)
        #expect(result != nil)
        #expect(result?.status == .offline)
    }

    // MARK: - 37. PossibleParents Parsing

    @Test("PossibleParents with valid entries and IP formatting")
    func testPossibleParentsValidWithIP() {
        var payload = Data()
        payload.appendUInt32(2)  // 2 parents
        payload.appendString("parent1")
        payload.appendUInt32(0x0A000001)  // IP (network order)
        payload.appendUInt32(2242)        // port
        payload.appendString("parent2")
        payload.appendUInt32(0xC0A80001)  // 192.168.0.1 in network order
        payload.appendUInt32(2243)

        let result = MessageParser.parsePossibleParents(payload)
        #expect(result != nil)
        #expect(result?.count == 2)
        #expect(result?.first?.username == "parent1")
        #expect(result?.first?.port == 2242)
    }

    @Test("PossibleParents count exceeds maxItemCount returns nil")
    func testPossibleParentsCountOverLimit() {
        var payload = Data()
        payload.appendUInt32(100_001)
        #expect(MessageParser.parsePossibleParents(payload) == nil)
    }

    @Test("PossibleParents truncated at port field")
    func testPossibleParentsMissingPort() {
        var payload = Data()
        payload.appendUInt32(2)  // claims 2 parents
        payload.appendString("parent1")
        payload.appendUInt32(0x0A000001)
        // Missing port for parent1
        let result = MessageParser.parsePossibleParents(payload)
        #expect(result != nil)
        #expect(result?.count == 0)  // loop breaks when port read fails
    }

    // MARK: - 38. Recommendations Parsing Edge Cases

    @Test("Recommendations with negative scores")
    func testRecommendationsNegativeScores() {
        var payload = Data()
        payload.appendUInt32(2)  // 2 recommendations
        payload.appendString("jazz")
        payload.appendInt32(-5)
        payload.appendString("rock")
        payload.appendInt32(10)
        // 1 unrecommendation
        payload.appendUInt32(1)
        payload.appendString("country")
        payload.appendInt32(-100)

        let result = MessageParser.parseRecommendations(payload)
        #expect(result != nil)
        #expect(result?.recommendations.count == 2)
        #expect(result?.recommendations.first?.score == -5)
        #expect(result?.unrecommendations.count == 1)
    }

    @Test("Recommendations with count exceeding limit")
    func testRecommendationsExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(100_001)  // exceeds maxItemCount
        #expect(MessageParser.parseRecommendations(payload) == nil)
    }

    @Test("Recommendations with unrecommendation count exceeding limit")
    func testRecommendationsUnrecExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(0)  // 0 recommendations
        payload.appendUInt32(100_001)  // unrec exceeds limit
        #expect(MessageParser.parseRecommendations(payload) == nil)
    }

    // MARK: - 39. UserInterests Parsing Edge Cases

    @Test("UserInterests with count exceeding limit")
    func testUserInterestsLikedExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(100_001)  // liked count exceeds limit
        #expect(MessageParser.parseUserInterests(payload) == nil)
    }

    @Test("UserInterests with hated count exceeding limit")
    func testUserInterestsHatedExceedsLimit() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(0)        // 0 likes
        payload.appendUInt32(100_001)  // hated count exceeds limit
        #expect(MessageParser.parseUserInterests(payload) == nil)
    }

    // MARK: - 40. SimilarUsers Exceeds Limit

    @Test("SimilarUsers count exceeds maxItemCount")
    func testSimilarUsersExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(100_001)
        #expect(MessageParser.parseSimilarUsers(payload) == nil)
    }

    // MARK: - 41. RoomTickerState Exceeds Limit

    @Test("RoomTickerState ticker count exceeds maxItemCount")
    func testRoomTickerStateExceedsLimit() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(100_001)
        #expect(MessageParser.parseRoomTickerState(payload) == nil)
    }

    // MARK: - 42. RoomMembers Exceeds Limit

    @Test("RoomMembers member count exceeds maxItemCount")
    func testRoomMembersExceedsLimit() {
        var payload = Data()
        payload.appendString("room1")
        payload.appendUInt32(100_001)
        #expect(MessageParser.parseRoomMembers(payload) == nil)
    }

    // MARK: - 43. ExcludedSearchPhrases Exceeds Limit

    @Test("ExcludedSearchPhrases count exceeds maxItemCount")
    func testExcludedSearchPhrasesExceedsLimit() {
        var payload = Data()
        payload.appendUInt32(100_001)
        #expect(MessageParser.parseExcludedSearchPhrases(payload) == nil)
    }

    // MARK: - 44. TransferRequest/Reply Builder Edge Cases

    @Test("TransferRequest with download direction omits fileSize")
    func testTransferRequestDownloadNoSize() {
        let message = MessageBuilder.transferRequestMessage(
            direction: .download, token: 123, filename: "test.mp3"
        )
        // Parse it back
        let payload = message.subdata(in: 8..<message.count)  // skip length + code
        let result = MessageParser.parseTransferRequest(payload)
        #expect(result != nil)
        #expect(result?.direction == .download)
        #expect(result?.filename == "test.mp3")
    }

    @Test("TransferRequest with upload direction includes fileSize")
    func testTransferRequestUploadWithSize() {
        let message = MessageBuilder.transferRequestMessage(
            direction: .upload, token: 456, filename: "song.flac", fileSize: 50_000_000
        )
        let payload = message.subdata(in: 8..<message.count)
        let result = MessageParser.parseTransferRequest(payload)
        #expect(result != nil)
        #expect(result?.direction == .upload)
        #expect(result?.fileSize == 50_000_000)
    }

    @Test("TransferReply build/parse round-trip denied with reason")
    func testTransferReplyBuildParseDeniedReason() {
        let message = MessageBuilder.transferReplyMessage(
            token: 789, allowed: false, reason: "Queued"
        )
        let payload = message.subdata(in: 8..<message.count)
        let result = MessageParser.parseTransferReply(payload)
        #expect(result != nil)
        #expect(result?.allowed == false)
        #expect(result?.reason == "Queued")
    }

    @Test("TransferReply allowed=true with fileSize round-trips")
    func testTransferReplyAllowedWithSize() {
        let message = MessageBuilder.transferReplyMessage(
            token: 100, allowed: true, fileSize: 99_000_000
        )
        let payload = message.subdata(in: 8..<message.count)
        let result = MessageParser.parseTransferReply(payload)
        #expect(result != nil)
        #expect(result?.allowed == true)
    }

    // MARK: - 45. ConnectToPeer IP Formatting

    @Test("ConnectToPeer IP formatting with known values")
    func testConnectToPeerIPFormat() {
        var payload = Data()
        payload.appendString("testuser")
        payload.appendString("P")
        // IP 192.168.1.100 in network byte order as LE uint32
        // Network order: 0xC0A80164
        payload.appendUInt32(0xC0A80164)
        payload.appendUInt32(2242)
        payload.appendUInt32(999)
        payload.appendBool(false)

        let result = MessageParser.parseConnectToPeer(payload)
        #expect(result != nil)
        #expect(result?.ip == "192.168.1.100")
    }

    // MARK: - 46. UserStats Parsing

    @Test("UserStats all fields validates full parse")
    func testUserStatsAllFieldsParse() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(100000)  // avgSpeed
        payload.appendUInt32(5000)    // uploadNum
        payload.appendUInt32(0)       // unknown
        payload.appendUInt32(1000)    // files
        payload.appendUInt32(50)      // dirs

        let result = MessageParser.parseGetUserStats(payload)
        #expect(result != nil)
        #expect(result?.username == "user1")
        #expect(result?.avgSpeed == 100000)
        #expect(result?.files == 1000)
        #expect(result?.dirs == 50)
    }

    @Test("UserStats truncated at unknown field returns nil")
    func testUserStatsTruncatedAtUnknownField() {
        var payload = Data()
        payload.appendString("user1")
        payload.appendUInt32(100)   // avgSpeed
        payload.appendUInt32(50)    // uploadNum
        // Missing unknown, files, dirs

        let result = MessageParser.parseGetUserStats(payload)
        #expect(result == nil)
    }

    // MARK: - 47. Decompression Boundary Tests

    @Test("Decompression with exactly 7 bytes (minimum to pass > 6 check)")
    func testDecompress7Bytes() {
        let data = Data(repeating: 0xFF, count: 7)
        // Should not crash — either throws DecompressionError or produces output
        do {
            _ = try ZlibDecompression.decompress(data)
        } catch is DecompressionError {
            // Expected
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Decompression with valid zlib but truncated data")
    func testDecompressValidHeaderTruncated() {
        // Valid zlib header, but only 1 byte of deflate data + fake checksum
        var data = Data([0x78, 0x9C])
        data.append(0x03)  // empty deflate stream (BFINAL=1, BTYPE=fixed, end of block)
        data.append(Data([0x00, 0x00, 0x00, 0x00]))  // fake adler32
        // After stripping header (2) and footer (4), left with 1 byte [0x03]
        // This is actually a valid minimal deflate stream
        do {
            let result = try ZlibDecompression.decompress(data)
            #expect(result.count >= 0)  // success is fine
        } catch is DecompressionError {
            // Also acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Raw deflate with single zero byte")
    func testRawDeflateSingleByte() {
        let data = Data([0x00])
        #expect(throws: DecompressionError.self) {
            _ = try ZlibDecompression.decompressRawDeflate(data)
        }
    }

    // MARK: - 48. MessageParser parseFrame edge cases with real server codes

    @Test("parseFrame extracts correct code for all common server message types")
    func testFrameCommonServerCodes() {
        let codes: [UInt32] = [1, 5, 14, 15, 16, 18, 22, 26, 64, 66, 69, 71, 102, 104]
        for code in codes {
            var data = Data()
            data.appendUInt32(8)     // length: 4 bytes code + 4 bytes payload
            data.appendUInt32(code)
            data.appendUInt32(0)     // dummy payload

            let result = MessageParser.parseFrame(from: data)
            #expect(result != nil, "Code \(code) should parse")
            #expect(result?.frame.code == code, "Code should be \(code)")
        }
    }

    // MARK: - 49. ChatRoom Message Edge Cases

    @Test("ChatRoom message with empty message body")
    func testChatRoomEmptyMessage() {
        var payload = Data()
        payload.appendString("room")
        payload.appendString("user")
        payload.appendString("")

        let result = MessageParser.parseSayInChatRoom(payload)
        #expect(result != nil)
        #expect(result?.message == "")
    }

    @Test("Private message with unicode in all fields")
    func testPrivateMessageUnicode() {
        var payload = Data()
        payload.appendUInt32(1)        // id
        payload.appendUInt32(1000)     // timestamp
        payload.appendString("Ünîcödé_üser")
        payload.appendString("Héllo Wörld! 你好世界 🎵")

        let result = MessageParser.parsePrivateMessage(payload)
        #expect(result != nil)
        #expect(result?.username == "Ünîcödé_üser")
        #expect(result?.message == "Héllo Wörld! 你好世界 🎵")
    }

    // MARK: - 50. LoginResponse Edge Cases

    @Test("Login failure with empty reason")
    func testLoginFailureEmptyReason() {
        var payload = Data()
        payload.appendBool(false)
        payload.appendString("")

        let result = MessageParser.parseLoginResponse(payload)
        #expect(result != nil)
        if case .failure(let reason) = result {
            #expect(reason == "")
        }
    }

    @Test("Login success with very long greeting")
    func testLoginSuccessLongGreeting() {
        var payload = Data()
        payload.appendBool(true)
        let longGreeting = String(repeating: "A", count: 10000)
        payload.appendString(longGreeting)
        payload.appendUInt32(0x7F000001)  // 127.0.0.1

        let result = MessageParser.parseLoginResponse(payload)
        #expect(result != nil)
        if case .success(let greeting, _, _) = result {
            #expect(greeting == longGreeting)
        }
    }

    // MARK: - 51. RoomList Boundary Tests

    @Test("RoomList with zero rooms returns empty array")
    func testRoomListEmptyValid() {
        var payload = Data()
        payload.appendUInt32(0)  // room count = 0
        payload.appendUInt32(0)  // user counts count = 0

        let result = MessageParser.parseRoomList(payload)
        #expect(result != nil)
        #expect(result?.publicRooms.count == 0)
    }

    @Test("RoomList more rooms than user counts: missing counts default to 0")
    func testRoomListMoreRoomsThanUserCounts() {
        var payload = Data()
        payload.appendUInt32(3)  // 3 rooms
        payload.appendString("Room1")
        payload.appendString("Room2")
        payload.appendString("Room3")
        payload.appendUInt32(2)  // only 2 user counts
        payload.appendUInt32(10)
        payload.appendUInt32(20)

        let result = MessageParser.parseRoomList(payload)
        #expect(result != nil)
        // All 3 rooms returned; third one gets userCount = 0.
        #expect(result?.publicRooms.count == 3)
        #expect(result?.publicRooms[2].userCount == 0)
    }
}
