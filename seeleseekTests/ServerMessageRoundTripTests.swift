import Testing
import Foundation
@testable import seeleseek

/// Round-trip every server message builder: build → read back code + all fields from wire-format Data.
/// Wire format: [uint32 length][uint32 code][payload...]
@Suite("Server Message Round-Trip Tests")
struct ServerMessageRoundTripTests {

    // MARK: - Helpers

    /// Skip the 4-byte length prefix; returns (code, payloadStartOffset)
    private func parseMessage(_ data: Data) -> (code: UInt32, payloadStart: Int) {
        let code = data.readUInt32(at: 4)!
        return (code, 8)
    }

    // MARK: - Auth & Session

    @Test("login message")
    func testLogin() {
        let msg = MessageBuilder.loginMessage(username: "alice", password: "secret")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.login.rawValue)

        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "alice")
        let (pass, pLen) = msg.readString(at: o)!; o += pLen
        #expect(pass == "secret")
        let version = msg.readUInt32(at: o)!; o += 4
        #expect(version == 160)
        // MD5 hash string
        let (hash, hLen) = msg.readString(at: o)!; o += hLen
        #expect(hash.count == 32) // MD5 hex = 32 chars
        // Minor version
        let minor = msg.readUInt32(at: o)!
        #expect(minor == 3)
    }

    @Test("setListenPort message")
    func testSetListenPort() {
        let msg = MessageBuilder.setListenPortMessage(port: 2234)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.setListenPort.rawValue)
        #expect(msg.readUInt32(at: off) == 2234)
    }

    @Test("setOnlineStatus - all 3 statuses")
    func testSetOnlineStatus() {
        for status in [UserStatus.offline, .away, .online] {
            let msg = MessageBuilder.setOnlineStatusMessage(status: status)
            let (code, off) = parseMessage(msg)
            #expect(code == ServerMessageCode.setOnlineStatus.rawValue)
            #expect(msg.readUInt32(at: off) == status.rawValue)
        }
    }

    @Test("sharedFoldersFiles message")
    func testSharedFoldersFiles() {
        let msg = MessageBuilder.sharedFoldersFilesMessage(folders: 42, files: 1337)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.sharedFoldersFiles.rawValue)
        #expect(msg.readUInt32(at: off) == 42)
        #expect(msg.readUInt32(at: off + 4) == 1337)
    }

    @Test("ping message (code-only)")
    func testPing() {
        let msg = MessageBuilder.pingMessage()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.ping.rawValue)
        #expect(msg.count == 8) // length(4) + code(4)
    }

    @Test("sendUploadSpeed message")
    func testSendUploadSpeed() {
        let msg = MessageBuilder.sendUploadSpeedMessage(speed: 50000)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.sendUploadSpeedRequest.rawValue)
        #expect(msg.readUInt32(at: off) == 50000)
    }

    @Test("checkPrivileges message")
    func testCheckPrivileges() {
        let msg = MessageBuilder.checkPrivileges()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.checkPrivileges.rawValue)
    }

    // MARK: - Search

    @Test("fileSearch message")
    func testFileSearch() {
        let msg = MessageBuilder.fileSearchMessage(token: 99999, query: "pink floyd")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.fileSearch.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 99999); o += 4
        let (q, _) = msg.readString(at: o)!
        #expect(q == "pink floyd")
    }

    @Test("roomSearch message")
    func testRoomSearch() {
        let msg = MessageBuilder.roomSearch(room: "Metal", token: 555, query: "iron maiden")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.roomSearch.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "Metal")
        #expect(msg.readUInt32(at: o) == 555); o += 4
        let (q, _) = msg.readString(at: o)!
        #expect(q == "iron maiden")
    }

    @Test("fileSearchRoom message (legacy code 25)")
    func testFileSearchRoom() {
        let msg = MessageBuilder.fileSearchRoomMessage(room: "Jazz", token: 777, query: "miles")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.fileSearchRoom.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "Jazz")
        #expect(msg.readUInt32(at: o) == 777); o += 4
        let (q, _) = msg.readString(at: o)!
        #expect(q == "miles")
    }

    @Test("wishlistSearch message")
    func testWishlistSearch() {
        let msg = MessageBuilder.wishlistSearch(token: 1234, query: "rare vinyl")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.wishlistSearch.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 1234); o += 4
        let (q, _) = msg.readString(at: o)!
        #expect(q == "rare vinyl")
    }

    @Test("userSearch message")
    func testUserSearch() {
        let msg = MessageBuilder.userSearchMessage(username: "bob", token: 42, query: "flac")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.userSearch.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "bob")
        #expect(msg.readUInt32(at: o) == 42); o += 4
        let (q, _) = msg.readString(at: o)!
        #expect(q == "flac")
    }

    // MARK: - Chat

    @Test("joinRoom - public")
    func testJoinRoomPublic() {
        let msg = MessageBuilder.joinRoomMessage(roomName: "Lounge")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.joinRoom.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "Lounge")
        #expect(msg.readUInt32(at: o) == 0) // isPrivate = false → 0
    }

    @Test("joinRoom - private")
    func testJoinRoomPrivate() {
        let msg = MessageBuilder.joinRoomMessage(roomName: "VIP", isPrivate: true)
        let (_, off) = parseMessage(msg)
        var o = off
        let (_, rLen) = msg.readString(at: o)!; o += rLen
        #expect(msg.readUInt32(at: o) == 1)
    }

    @Test("leaveRoom message")
    func testLeaveRoom() {
        let msg = MessageBuilder.leaveRoomMessage(roomName: "Lounge")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.leaveRoom.rawValue)
        let (room, _) = msg.readString(at: off)!
        #expect(room == "Lounge")
    }

    @Test("sayInChatRoom message")
    func testSayInChatRoom() {
        let msg = MessageBuilder.sayInChatRoomMessage(roomName: "Lounge", message: "Hello all!")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.sayInChatRoom.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "Lounge")
        let (text, _) = msg.readString(at: o)!
        #expect(text == "Hello all!")
    }

    @Test("privateMessage message")
    func testPrivateMessage() {
        let msg = MessageBuilder.privateMessageMessage(username: "bob", message: "hey!")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateMessages.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "bob")
        let (text, _) = msg.readString(at: o)!
        #expect(text == "hey!")
    }

    @Test("acknowledgePrivateMessage message")
    func testAckPrivateMessage() {
        let msg = MessageBuilder.acknowledgePrivateMessageMessage(messageId: 456)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.acknowledgePrivateMessage.rawValue)
        #expect(msg.readUInt32(at: off) == 456)
    }

    // MARK: - User

    @Test("watchUser message")
    func testWatchUser() {
        let msg = MessageBuilder.watchUserMessage(username: "carol")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.watchUser.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "carol")
    }

    @Test("unwatchUser message")
    func testUnwatchUser() {
        let msg = MessageBuilder.unwatchUserMessage(username: "carol")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.unwatchUser.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "carol")
    }

    @Test("ignoreUser message")
    func testIgnoreUser() {
        let msg = MessageBuilder.ignoreUserMessage(username: "troll")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.ignoreUser.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "troll")
    }

    @Test("unignoreUser message")
    func testUnignoreUser() {
        let msg = MessageBuilder.unignoreUserMessage(username: "troll")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.unignoreUser.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "troll")
    }

    @Test("getUserStatus message")
    func testGetUserStatus() {
        let msg = MessageBuilder.getUserStatusMessage(username: "dave")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.getUserStatus.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "dave")
    }

    @Test("getUserAddress message")
    func testGetUserAddress() {
        let msg = MessageBuilder.getUserAddress("dave")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.getPeerAddress.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "dave")
    }

    @Test("getUserStats message")
    func testGetUserStats() {
        let msg = MessageBuilder.getUserStats("eve")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.getUserStats.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "eve")
    }

    @Test("getUserPrivileges message")
    func testGetUserPrivileges() {
        let msg = MessageBuilder.getUserPrivileges("frank")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.userPrivileges.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "frank")
    }

    @Test("connectToPeer message")
    func testConnectToPeer() {
        let msg = MessageBuilder.connectToPeerMessage(token: 7777, username: "peer1", connectionType: "P")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.connectToPeer.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 7777); o += 4
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "peer1")
        let (connType, _) = msg.readString(at: o)!
        #expect(connType == "P")
    }

    @Test("cantConnectToPeer message")
    func testCantConnectToPeer() {
        let msg = MessageBuilder.cantConnectToPeer(token: 8888, username: "peer2")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.cantConnectToPeer.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 8888); o += 4
        let (user, _) = msg.readString(at: o)!
        #expect(user == "peer2")
    }

    // MARK: - Interests & Recommendations

    @Test("addThingILike message")
    func testAddThingILike() {
        let msg = MessageBuilder.addThingILike("jazz")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.addThingILike.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "jazz")
    }

    @Test("removeThingILike message")
    func testRemoveThingILike() {
        let msg = MessageBuilder.removeThingILike("jazz")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.removeThingILike.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "jazz")
    }

    @Test("addThingIHate message")
    func testAddThingIHate() {
        let msg = MessageBuilder.addThingIHate("noise")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.addThingIHate.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "noise")
    }

    @Test("removeThingIHate message")
    func testRemoveThingIHate() {
        let msg = MessageBuilder.removeThingIHate("noise")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.removeThingIHate.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "noise")
    }

    @Test("getRecommendations message (code-only)")
    func testGetRecommendations() {
        let msg = MessageBuilder.getRecommendations()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.recommendations.rawValue)
    }

    @Test("getGlobalRecommendations message (code-only)")
    func testGetGlobalRecommendations() {
        let msg = MessageBuilder.getGlobalRecommendations()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.globalRecommendations.rawValue)
    }

    @Test("getUserInterests message")
    func testGetUserInterests() {
        let msg = MessageBuilder.getUserInterests("grace")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.userInterests.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "grace")
    }

    @Test("getSimilarUsers message (code-only)")
    func testGetSimilarUsers() {
        let msg = MessageBuilder.getSimilarUsers()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.similarUsers.rawValue)
    }

    @Test("getItemRecommendations message")
    func testGetItemRecommendations() {
        let msg = MessageBuilder.getItemRecommendations("electronic")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.itemRecommendations.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "electronic")
    }

    @Test("getItemSimilarUsers message")
    func testGetItemSimilarUsers() {
        let msg = MessageBuilder.getItemSimilarUsers("classical")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.itemSimilarUsers.rawValue)
        let (item, _) = msg.readString(at: off)!
        #expect(item == "classical")
    }

    // MARK: - Rooms

    @Test("getRoomList message")
    func testGetRoomList() {
        let msg = MessageBuilder.getRoomListMessage()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.roomList.rawValue)
    }

    @Test("setRoomTicker message")
    func testSetRoomTicker() {
        let msg = MessageBuilder.setRoomTicker(room: "Chill", ticker: "Now playing: Nujabes")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.roomTickerSet.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "Chill")
        let (ticker, _) = msg.readString(at: o)!
        #expect(ticker == "Now playing: Nujabes")
    }

    // MARK: - Private Rooms

    @Test("privateRoomAddMember message")
    func testPrivateRoomAddMember() {
        let msg = MessageBuilder.privateRoomAddMember(room: "VIP", username: "heidi")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomAddMember.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = msg.readString(at: o)!
        #expect(user == "heidi")
    }

    @Test("privateRoomRemoveMember message")
    func testPrivateRoomRemoveMember() {
        let msg = MessageBuilder.privateRoomRemoveMember(room: "VIP", username: "heidi")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomRemoveMember.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = msg.readString(at: o)!
        #expect(user == "heidi")
    }

    @Test("privateRoomCancelMembership message")
    func testPrivateRoomCancelMembership() {
        let msg = MessageBuilder.privateRoomCancelMembership(room: "VIP")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomCancelMembership.rawValue)
        let (room, _) = msg.readString(at: off)!
        #expect(room == "VIP")
    }

    @Test("privateRoomCancelOwnership message")
    func testPrivateRoomCancelOwnership() {
        let msg = MessageBuilder.privateRoomCancelOwnership(room: "VIP")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomCancelOwnership.rawValue)
        let (room, _) = msg.readString(at: off)!
        #expect(room == "VIP")
    }

    @Test("privateRoomAddOperator message")
    func testPrivateRoomAddOperator() {
        let msg = MessageBuilder.privateRoomAddOperator(room: "VIP", username: "mod1")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomAddOperator.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = msg.readString(at: o)!
        #expect(user == "mod1")
    }

    @Test("privateRoomRemoveOperator message")
    func testPrivateRoomRemoveOperator() {
        let msg = MessageBuilder.privateRoomRemoveOperator(room: "VIP", username: "mod1")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.privateRoomRemoveOperator.rawValue)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "VIP")
        let (user, _) = msg.readString(at: o)!
        #expect(user == "mod1")
    }

    @Test("enableRoomInvitations message")
    func testEnableRoomInvitations() {
        let msg = MessageBuilder.enableRoomInvitationsMessage(enable: true)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.enableRoomInvitations.rawValue)
        #expect(msg.readBool(at: off) == true)
    }

    @Test("givePrivileges message")
    func testGivePrivileges() {
        let msg = MessageBuilder.givePrivilegesMessage(username: "ivan", days: 30)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.givePrivileges.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "ivan")
        #expect(msg.readUInt32(at: o) == 30)
    }

    @Test("messageUsers message")
    func testMessageUsers() {
        let msg = MessageBuilder.messageUsersMessage(usernames: ["a", "b", "c"], message: "broadcast!")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.messageUsers.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 3); o += 4
        let (u1, u1L) = msg.readString(at: o)!; o += u1L
        #expect(u1 == "a")
        let (u2, u2L) = msg.readString(at: o)!; o += u2L
        #expect(u2 == "b")
        let (u3, u3L) = msg.readString(at: o)!; o += u3L
        #expect(u3 == "c")
        let (text, _) = msg.readString(at: o)!
        #expect(text == "broadcast!")
    }

    @Test("joinGlobalRoom message")
    func testJoinGlobalRoom() {
        let msg = MessageBuilder.joinGlobalRoomMessage()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.joinGlobalRoom.rawValue)
    }

    @Test("leaveGlobalRoom message")
    func testLeaveGlobalRoom() {
        let msg = MessageBuilder.leaveGlobalRoomMessage()
        let (code, _) = parseMessage(msg)
        #expect(code == ServerMessageCode.leaveGlobalRoom.rawValue)
    }

    // MARK: - Distributed Network

    @Test("haveNoParent - true")
    func testHaveNoParentTrue() {
        let msg = MessageBuilder.haveNoParent(true)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.haveNoParent.rawValue)
        #expect(msg.readBool(at: off) == true)
    }

    @Test("haveNoParent - false")
    func testHaveNoParentFalse() {
        let msg = MessageBuilder.haveNoParent(false)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.haveNoParent.rawValue)
        #expect(msg.readBool(at: off) == false)
    }

    @Test("acceptChildren message")
    func testAcceptChildren() {
        let msg = MessageBuilder.acceptChildren(true)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.acceptChildren.rawValue)
        #expect(msg.readBool(at: off) == true)
    }

    @Test("branchLevel message")
    func testBranchLevel() {
        let msg = MessageBuilder.branchLevel(5)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.branchLevel.rawValue)
        #expect(msg.readUInt32(at: off) == 5)
    }

    @Test("branchRoot message")
    func testBranchRoot() {
        let msg = MessageBuilder.branchRoot("rootUser")
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.branchRoot.rawValue)
        let (user, _) = msg.readString(at: off)!
        #expect(user == "rootUser")
    }

    @Test("childDepth message")
    func testChildDepth() {
        let msg = MessageBuilder.childDepth(3)
        let (code, off) = parseMessage(msg)
        #expect(code == ServerMessageCode.childDepth.rawValue)
        #expect(msg.readUInt32(at: off) == 3)
    }

    // MARK: - Edge Cases

    @Test("unicode strings in messages")
    func testUnicodeRoundTrip() {
        let msg = MessageBuilder.sayInChatRoomMessage(roomName: "日本語ルーム", message: "こんにちは 🎵")
        let (_, off) = parseMessage(msg)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "日本語ルーム")
        let (text, _) = msg.readString(at: o)!
        #expect(text == "こんにちは 🎵")
    }

    @Test("empty strings in messages")
    func testEmptyStringRoundTrip() {
        let msg = MessageBuilder.sayInChatRoomMessage(roomName: "", message: "")
        let (_, off) = parseMessage(msg)
        var o = off
        let (room, rLen) = msg.readString(at: o)!; o += rLen
        #expect(room == "")
        let (text, _) = msg.readString(at: o)!
        #expect(text == "")
    }

    @Test("message length field is consistent")
    func testLengthFieldConsistency() {
        let messages: [Data] = [
            MessageBuilder.pingMessage(),
            MessageBuilder.fileSearchMessage(token: 1, query: "test"),
            MessageBuilder.joinRoomMessage(roomName: "room"),
            MessageBuilder.privateMessageMessage(username: "u", message: "m"),
            MessageBuilder.branchLevel(0),
        ]
        for msg in messages {
            let length = msg.readUInt32(at: 0)!
            #expect(Int(length) + 4 == msg.count, "Length field mismatch: stated \(length) + 4 != actual \(msg.count)")
        }
    }
}
