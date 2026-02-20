import Testing
import Foundation
@testable import seeleseek

/// Test parsing of server messages by constructing raw payload Data and reading fields
/// using the same Data extension methods the handler uses.
/// These tests do NOT require a NetworkClient — they verify the wire format is parseable.
@Suite("Server Message Parsing Tests")
struct ServerMessageParsingTests {

    // MARK: - IP Helper (matches ServerMessageHandler.ipString)

    /// Soulseek sends IP as LE uint32 but value is in network byte order (big-endian).
    private func ipString(from value: UInt32) -> String {
        let b1 = (value >> 24) & 0xFF
        let b2 = (value >> 16) & 0xFF
        let b3 = (value >> 8) & 0xFF
        let b4 = value & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    /// Construct an IP uint32 in the protocol's format: bytes in network order stored as LE uint32.
    /// e.g. 192.168.1.100 → 0xC0A80164
    private func makeIP(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
    }

    // MARK: - Auth & Session

    @Test("parseLoginResponse - success")
    func testLoginSuccess() {
        var p = Data()
        p.appendBool(true)
        p.appendString("Welcome!")
        p.appendUInt32(makeIP(10, 20, 30, 40))

        let result = MessageParser.parseLoginResponse(p)
        switch result {
        case .success(let greeting, let ip, _):
            #expect(greeting == "Welcome!")
            #expect(ip == "10.20.30.40")
        default:
            Issue.record("Expected success")
        }
    }

    @Test("parseLoginResponse - failure")
    func testLoginFailure() {
        var p = Data()
        p.appendBool(false)
        p.appendString("Bad password")

        let result = MessageParser.parseLoginResponse(p)
        switch result {
        case .failure(let reason):
            #expect(reason == "Bad password")
        default:
            Issue.record("Expected failure")
        }
    }

    @Test("getPeerAddress - IP byte order")
    func testGetPeerAddress() {
        var p = Data()
        p.appendString("alice")
        p.appendUInt32(makeIP(192, 168, 1, 100))
        p.appendUInt32(2234)

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "alice")
        let ip = p.readUInt32(at: o)!; o += 4
        #expect(ipString(from: ip) == "192.168.1.100")
        let port = p.readUInt32(at: o)!
        #expect(port == 2234)
    }

    @Test("watchUser - exists with stats")
    func testWatchUserExists() {
        var p = Data()
        p.appendString("bob")
        p.appendBool(true) // exists
        p.appendUInt32(2)  // status = online
        p.appendUInt32(10_000) // avgSpeed
        p.appendUInt32(500) // uploadNum
        p.appendUInt32(0) // unknown
        p.appendUInt32(1234) // files
        p.appendUInt32(56) // dirs

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "bob")
        #expect(p.readBool(at: o) == true); o += 1
        let status = p.readUInt32(at: o)!; o += 4
        #expect(UserStatus(rawValue: status) == .online)
        let avgSpeed = p.readUInt32(at: o)!; o += 4
        #expect(avgSpeed == 10_000)
        o += 4 // uploadNum
        o += 4 // unknown
        let files = p.readUInt32(at: o)!; o += 4
        #expect(files == 1234)
        let dirs = p.readUInt32(at: o)!
        #expect(dirs == 56)
    }

    @Test("watchUser - does not exist")
    func testWatchUserNotExists() {
        var p = Data()
        p.appendString("ghost")
        p.appendBool(false)

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "ghost")
        #expect(p.readBool(at: o) == false)
    }

    @Test("getUserStatus")
    func testGetUserStatus() {
        let result = MessageParser.parseGetUserStatus(buildPayload {
            $0.appendString("carol")
            $0.appendUInt32(1) // away
            $0.appendUInt8(1) // privileged
        })
        #expect(result?.username == "carol")
        #expect(result?.status == .away)
        #expect(result?.privileged == true)
    }

    @Test("connectToPeer - IP byte order")
    func testConnectToPeer() {
        var p = Data()
        p.appendString("dave")
        p.appendString("P")
        p.appendUInt32(makeIP(172, 16, 0, 1))
        p.appendUInt32(6789)
        p.appendUInt32(12345) // token

        let result = MessageParser.parseConnectToPeer(p)
        #expect(result?.username == "dave")
        #expect(result?.ip == "172.16.0.1")
        #expect(result?.port == 6789)
        #expect(result?.token == 12345)
    }

    // MARK: - Chat

    @Test("sayInChatRoom")
    func testSayInChatRoom() {
        let result = MessageParser.parseSayInChatRoom(buildPayload {
            $0.appendString("Lounge")
            $0.appendString("alice")
            $0.appendString("Hello everyone!")
        })
        #expect(result?.roomName == "Lounge")
        #expect(result?.username == "alice")
        #expect(result?.message == "Hello everyone!")
    }

    @Test("privateMessage")
    func testPrivateMessage() {
        let result = MessageParser.parsePrivateMessage(buildPayload {
            $0.appendUInt32(999)
            $0.appendUInt32(1704067200)
            $0.appendString("bob")
            $0.appendString("Hey there")
            $0.appendBool(false) // not admin
        })
        #expect(result?.id == 999)
        #expect(result?.username == "bob")
        #expect(result?.message == "Hey there")
        #expect(result?.isAdmin == false)
    }

    @Test("userJoinedRoom")
    func testUserJoinedRoom() {
        var p = Data()
        p.appendString("Metal")
        p.appendString("headbanger42")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "Metal")
        let (user, _) = p.readString(at: o)!
        #expect(user == "headbanger42")
    }

    @Test("userLeftRoom")
    func testUserLeftRoom() {
        var p = Data()
        p.appendString("Jazz")
        p.appendString("smoothjazz")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "Jazz")
        let (user, _) = p.readString(at: o)!
        #expect(user == "smoothjazz")
    }

    @Test("leaveRoom")
    func testLeaveRoom() {
        var p = Data()
        p.appendString("TestRoom")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "TestRoom")
    }

    @Test("joinRoom full response with users/stats/countries")
    func testJoinRoomFull() {
        var p = Data()
        p.appendString("TestRoom")
        // 2 users
        p.appendUInt32(2)
        p.appendString("alice")
        p.appendString("bob")
        // statuses
        p.appendUInt32(2)
        p.appendUInt32(2) // alice: online
        p.appendUInt32(1) // bob: away
        // stats (avgspeed uint32, uploadnum uint64, files uint32, dirs uint32 = 20 bytes)
        p.appendUInt32(2)
        p.appendUInt32(50000); p.appendUInt64(100); p.appendUInt32(500); p.appendUInt32(20)
        p.appendUInt32(30000); p.appendUInt64(50); p.appendUInt32(200); p.appendUInt32(10)
        // slotsfull
        p.appendUInt32(2)
        p.appendUInt32(0); p.appendUInt32(1)
        // countries
        p.appendUInt32(2)
        p.appendString("US")
        p.appendString("DE")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "TestRoom")
        let userCount = p.readUInt32(at: o)!; o += 4
        #expect(userCount == 2)
        let (u1, u1L) = p.readString(at: o)!; o += u1L
        #expect(u1 == "alice")
        let (u2, u2L) = p.readString(at: o)!; o += u2L
        #expect(u2 == "bob")
    }

    // MARK: - Room List

    @Test("roomList - public rooms")
    func testRoomListPublic() {
        var p = Data()
        // 2 rooms
        p.appendUInt32(2)
        p.appendString("Lounge")
        p.appendString("Metal")
        // 2 counts
        p.appendUInt32(2)
        p.appendUInt32(50)
        p.appendUInt32(120)

        let result = MessageParser.parseRoomList(p)
        #expect(result?.count == 2)
        #expect(result?[0].name == "Lounge")
        #expect(result?[1].name == "Metal")
    }

    // MARK: - Interests & Recommendations

    @Test("recommendations with negative scores")
    func testRecommendations() {
        var p = Data()
        // 2 recommendations
        p.appendUInt32(2)
        p.appendString("electronic")
        p.appendInt32(42)
        p.appendString("ambient")
        p.appendInt32(-5)
        // 1 unrecommendation
        p.appendUInt32(1)
        p.appendString("country")
        p.appendInt32(-100)

        var o = 0
        let recCount = p.readUInt32(at: o)!; o += 4
        #expect(recCount == 2)
        let (r1, r1L) = p.readString(at: o)!; o += r1L
        #expect(r1 == "electronic")
        let s1 = p.readInt32(at: o)!; o += 4
        #expect(s1 == 42)
        let (r2, r2L) = p.readString(at: o)!; o += r2L
        #expect(r2 == "ambient")
        let s2 = p.readInt32(at: o)!; o += 4
        #expect(s2 == -5)
        let unrecCount = p.readUInt32(at: o)!; o += 4
        #expect(unrecCount == 1)
        let (u1, u1L) = p.readString(at: o)!; o += u1L
        #expect(u1 == "country")
        let us1 = p.readInt32(at: o)!
        #expect(us1 == -100)
    }

    @Test("globalRecommendations")
    func testGlobalRecommendations() {
        var p = Data()
        p.appendUInt32(1)
        p.appendString("rock")
        p.appendInt32(99)
        p.appendUInt32(0) // 0 unrecommendations

        var o = 0
        let recCount = p.readUInt32(at: o)!; o += 4
        #expect(recCount == 1)
        let (item, iLen) = p.readString(at: o)!; o += iLen
        #expect(item == "rock")
        let score = p.readInt32(at: o)!; o += 4
        #expect(score == 99)
        let unrecCount = p.readUInt32(at: o)!
        #expect(unrecCount == 0)
    }

    @Test("userInterests")
    func testUserInterests() {
        var p = Data()
        p.appendString("alice")
        // 2 likes
        p.appendUInt32(2)
        p.appendString("jazz")
        p.appendString("blues")
        // 1 hate
        p.appendUInt32(1)
        p.appendString("noise")

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "alice")
        let likeCount = p.readUInt32(at: o)!; o += 4
        #expect(likeCount == 2)
        let (l1, l1L) = p.readString(at: o)!; o += l1L
        #expect(l1 == "jazz")
        let (l2, l2L) = p.readString(at: o)!; o += l2L
        #expect(l2 == "blues")
        let hateCount = p.readUInt32(at: o)!; o += 4
        #expect(hateCount == 1)
        let (h1, _) = p.readString(at: o)!
        #expect(h1 == "noise")
    }

    @Test("similarUsers")
    func testSimilarUsers() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("user1")
        p.appendUInt32(85)
        p.appendString("user2")
        p.appendUInt32(72)

        var o = 0
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 2)
        let (u1, u1L) = p.readString(at: o)!; o += u1L
        #expect(u1 == "user1")
        #expect(p.readUInt32(at: o) == 85); o += 4
        let (u2, u2L) = p.readString(at: o)!; o += u2L
        #expect(u2 == "user2")
        #expect(p.readUInt32(at: o) == 72)
    }

    @Test("itemRecommendations")
    func testItemRecommendations() {
        var p = Data()
        p.appendString("electronic")
        p.appendUInt32(2)
        p.appendString("techno")
        p.appendInt32(50)
        p.appendString("house")
        p.appendInt32(30)

        var o = 0
        let (item, iLen) = p.readString(at: o)!; o += iLen
        #expect(item == "electronic")
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 2)
        let (r1, r1L) = p.readString(at: o)!; o += r1L
        #expect(r1 == "techno")
        #expect(p.readInt32(at: o) == 50); o += 4
        let (r2, _) = p.readString(at: o)!
        #expect(r2 == "house")
    }

    @Test("itemSimilarUsers")
    func testItemSimilarUsers() {
        var p = Data()
        p.appendString("jazz")
        p.appendUInt32(1)
        p.appendString("jazzfan99")

        var o = 0
        let (item, iLen) = p.readString(at: o)!; o += iLen
        #expect(item == "jazz")
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 1)
        let (user, _) = p.readString(at: o)!
        #expect(user == "jazzfan99")
    }

    // MARK: - Stats & Privileges

    @Test("getUserStats - verify unknown field skipped")
    func testGetUserStats() {
        var p = Data()
        p.appendString("alice")
        p.appendUInt32(50000) // avgSpeed
        p.appendUInt32(100)   // uploadNum
        p.appendUInt32(0)     // unknown (skip)
        p.appendUInt32(5000)  // files
        p.appendUInt32(200)   // dirs

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "alice")
        let avgSpeed = p.readUInt32(at: o)!; o += 4
        #expect(avgSpeed == 50000)
        o += 4 // uploadNum
        o += 4 // unknown
        let files = p.readUInt32(at: o)!; o += 4
        #expect(files == 5000)
        let dirs = p.readUInt32(at: o)!
        #expect(dirs == 200)
    }

    @Test("checkPrivileges")
    func testCheckPrivileges() {
        var p = Data()
        p.appendUInt32(86400) // seconds remaining
        #expect(p.readUInt32(at: 0) == 86400)
    }

    @Test("userPrivileges")
    func testUserPrivileges() {
        var p = Data()
        p.appendString("vipuser")
        p.appendBool(true)

        var o = 0
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "vipuser")
        #expect(p.readBool(at: o) == true)
    }

    // MARK: - Tickers

    @Test("roomTickerState")
    func testRoomTickerState() {
        var p = Data()
        p.appendString("Lounge")
        p.appendUInt32(2)
        p.appendString("alice")
        p.appendString("Playing jazz")
        p.appendString("bob")
        p.appendString("AFK")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "Lounge")
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 2)
        let (tu1, tu1L) = p.readString(at: o)!; o += tu1L
        #expect(tu1 == "alice")
        let (tt1, tt1L) = p.readString(at: o)!; o += tt1L
        #expect(tt1 == "Playing jazz")
        let (tu2, tu2L) = p.readString(at: o)!; o += tu2L
        #expect(tu2 == "bob")
        let (tt2, _) = p.readString(at: o)!
        #expect(tt2 == "AFK")
    }

    @Test("roomTickerAdd")
    func testRoomTickerAdd() {
        var p = Data()
        p.appendString("Lounge")
        p.appendString("carol")
        p.appendString("New ticker!")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "Lounge")
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "carol")
        let (ticker, _) = p.readString(at: o)!
        #expect(ticker == "New ticker!")
    }

    @Test("roomTickerRemove")
    func testRoomTickerRemove() {
        var p = Data()
        p.appendString("Lounge")
        p.appendString("dave")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "Lounge")
        let (user, _) = p.readString(at: o)!
        #expect(user == "dave")
    }

    // MARK: - Private Rooms

    @Test("privateRoomMembers")
    func testPrivateRoomMembers() {
        var p = Data()
        p.appendString("VIP")
        p.appendUInt32(3)
        p.appendString("alice")
        p.appendString("bob")
        p.appendString("carol")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 3)
        let (m1, m1L) = p.readString(at: o)!; o += m1L
        #expect(m1 == "alice")
        let (m2, m2L) = p.readString(at: o)!; o += m2L
        #expect(m2 == "bob")
        let (m3, _) = p.readString(at: o)!
        #expect(m3 == "carol")
    }

    @Test("privateRoomAddMember")
    func testPrivateRoomAddMember() {
        var p = Data()
        p.appendString("VIP")
        p.appendString("newmember")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = p.readString(at: o)!
        #expect(user == "newmember")
    }

    @Test("privateRoomRemoveMember")
    func testPrivateRoomRemoveMember() {
        var p = Data()
        p.appendString("VIP")
        p.appendString("exmember")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = p.readString(at: o)!
        #expect(user == "exmember")
    }

    @Test("privateRoomOperatorGranted")
    func testOperatorGranted() {
        var p = Data()
        p.appendString("VIP")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "VIP")
    }

    @Test("privateRoomOperatorRevoked")
    func testOperatorRevoked() {
        var p = Data()
        p.appendString("VIP")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "VIP")
    }

    @Test("privateRoomOperators")
    func testPrivateRoomOperators() {
        var p = Data()
        p.appendString("VIP")
        p.appendUInt32(2)
        p.appendString("mod1")
        p.appendString("mod2")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 2)
        let (op1, op1L) = p.readString(at: o)!; o += op1L
        #expect(op1 == "mod1")
        let (op2, _) = p.readString(at: o)!
        #expect(op2 == "mod2")
    }

    // MARK: - Distributed

    @Test("possibleParents - IP byte order")
    func testPossibleParents() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("parent1")
        p.appendUInt32(makeIP(10, 0, 0, 1))
        p.appendUInt32(2234)
        p.appendString("parent2")
        p.appendUInt32(makeIP(172, 16, 5, 5))
        p.appendUInt32(3456)

        var o = 0
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 2)

        let (u1, u1L) = p.readString(at: o)!; o += u1L
        #expect(u1 == "parent1")
        let ip1 = p.readUInt32(at: o)!; o += 4
        #expect(ipString(from: ip1) == "10.0.0.1")
        let port1 = p.readUInt32(at: o)!; o += 4
        #expect(port1 == 2234)

        let (u2, u2L) = p.readString(at: o)!; o += u2L
        #expect(u2 == "parent2")
        let ip2 = p.readUInt32(at: o)!; o += 4
        #expect(ipString(from: ip2) == "172.16.5.5")
        let port2 = p.readUInt32(at: o)!
        #expect(port2 == 3456)
    }

    @Test("embeddedMessage")
    func testEmbeddedMessage() {
        var p = Data()
        p.appendUInt8(DistributedMessageCode.searchRequest.rawValue)
        // distributed search payload
        p.appendUInt32(0) // unknown
        p.appendString("searcher")
        p.appendUInt32(12345)
        p.appendString("test query")

        let distribCode = p.readByte(at: 0)!
        #expect(distribCode == DistributedMessageCode.searchRequest.rawValue)

        let payload = p.safeSubdata(in: 1..<p.count)!
        var o = 0
        o += 4 // unknown
        let (user, uLen) = payload.readString(at: o)!; o += uLen
        #expect(user == "searcher")
        let token = payload.readUInt32(at: o)!; o += 4
        #expect(token == 12345)
        let (query, _) = payload.readString(at: o)!
        #expect(query == "test query")
    }

    @Test("distributedSearch")
    func testDistributedSearch() {
        var p = Data()
        p.appendUInt32(0) // unknown
        p.appendString("alice")
        p.appendUInt32(99999)
        p.appendString("pink floyd flac")

        var o = 0
        o += 4 // unknown
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "alice")
        #expect(p.readUInt32(at: o) == 99999); o += 4
        let (query, _) = p.readString(at: o)!
        #expect(query == "pink floyd flac")
    }

    @Test("parentMinSpeed")
    func testParentMinSpeed() {
        var p = Data()
        p.appendUInt32(1000)
        #expect(p.readUInt32(at: 0) == 1000)
    }

    @Test("parentSpeedRatio")
    func testParentSpeedRatio() {
        var p = Data()
        p.appendUInt32(50)
        #expect(p.readUInt32(at: 0) == 50)
    }

    // MARK: - Misc

    @Test("wishlistInterval")
    func testWishlistInterval() {
        var p = Data()
        p.appendUInt32(720)
        #expect(p.readUInt32(at: 0) == 720)
    }

    @Test("excludedSearchPhrases")
    func testExcludedSearchPhrases() {
        var p = Data()
        p.appendUInt32(3)
        p.appendString("xxx")
        p.appendString("warez")
        p.appendString("crack")

        var o = 0
        let count = p.readUInt32(at: o)!; o += 4
        #expect(count == 3)
        let (p1, p1L) = p.readString(at: o)!; o += p1L
        #expect(p1 == "xxx")
        let (p2, p2L) = p.readString(at: o)!; o += p2L
        #expect(p2 == "warez")
        let (p3, _) = p.readString(at: o)!
        #expect(p3 == "crack")
    }

    @Test("adminMessage")
    func testAdminMessage() {
        var p = Data()
        p.appendString("Server maintenance at midnight UTC")
        let (msg, _) = p.readString(at: 0)!
        #expect(msg == "Server maintenance at midnight UTC")
    }

    @Test("cantConnectToPeer")
    func testCantConnectToPeer() {
        var p = Data()
        p.appendUInt32(77777)
        #expect(p.readUInt32(at: 0) == 77777)
    }

    @Test("roomAdded")
    func testRoomAdded() {
        var p = Data()
        p.appendString("NewRoom")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "NewRoom")
    }

    @Test("roomRemoved")
    func testRoomRemoved() {
        var p = Data()
        p.appendString("OldRoom")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "OldRoom")
    }

    @Test("roomMembershipGranted")
    func testRoomMembershipGranted() {
        var p = Data()
        p.appendString("PrivateRoom")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "PrivateRoom")
    }

    @Test("roomMembershipRevoked")
    func testRoomMembershipRevoked() {
        var p = Data()
        p.appendString("PrivateRoom")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "PrivateRoom")
    }

    @Test("enableRoomInvitations")
    func testEnableRoomInvitations() {
        var p = Data()
        p.appendBool(true)
        #expect(p.readBool(at: 0) == true)

        var p2 = Data()
        p2.appendBool(false)
        #expect(p2.readBool(at: 0) == false)
    }

    @Test("newPassword")
    func testNewPassword() {
        var p = Data()
        p.appendString("newSecret123")
        let (pass, _) = p.readString(at: 0)!
        #expect(pass == "newSecret123")
    }

    @Test("globalRoomMessage")
    func testGlobalRoomMessage() {
        var p = Data()
        p.appendString("GlobalLounge")
        p.appendString("broadcaster")
        p.appendString("Hello everyone!")

        var o = 0
        let (room, rLen) = p.readString(at: o)!; o += rLen
        #expect(room == "GlobalLounge")
        let (user, uLen) = p.readString(at: o)!; o += uLen
        #expect(user == "broadcaster")
        let (msg, _) = p.readString(at: o)!
        #expect(msg == "Hello everyone!")
    }

    @Test("cantCreateRoom")
    func testCantCreateRoom() {
        var p = Data()
        p.appendString("Reserved Room")
        let (room, _) = p.readString(at: 0)!
        #expect(room == "Reserved Room")
    }

    // MARK: - Helpers

    private func buildPayload(_ builder: (inout Data) -> Void) -> Data {
        var data = Data()
        builder(&data)
        return data
    }
}
