import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Happy-path coverage tests for every MessageParser.parseX function.
/// Each case builds a known-good payload (matching the wire format per
/// PROTOCOL_REFERENCE_FULL.md) and asserts the parsed struct matches field
/// by field. Negative/malformed cases live in FailureTests.swift.
@Suite("Parser happy-path coverage")
struct ParserCoverageTests {

    // MARK: - Server messages

    @Test("parseSayInChatRoom")
    func testSayInChatRoom() {
        var p = Data()
        p.appendString("Lounge")
        p.appendString("alice")
        p.appendString("Hello!")
        let info = MessageParser.parseSayInChatRoom(p)
        #expect(info == MessageParser.ChatRoomMessageInfo(
            roomName: "Lounge", username: "alice", message: "Hello!"
        ))
    }

    @Test("parseGetUserStats")
    func testGetUserStats() {
        var p = Data()
        p.appendString("alice")
        p.appendUInt32(12345)  // avgSpeed
        p.appendUInt32(17)     // uploadNum
        p.appendUInt32(0)      // unknown
        p.appendUInt32(300)    // files
        p.appendUInt32(42)     // dirs
        let info = MessageParser.parseGetUserStats(p)
        #expect(info == MessageParser.UserStatsInfo(
            username: "alice", avgSpeed: 12345, uploadNum: 17, files: 300, dirs: 42
        ))
    }

    @Test("parsePossibleParents")
    func testPossibleParents() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("parent1")
        p.appendUInt32(0x0A0B0C0D)
        p.appendUInt32(2234)
        p.appendString("parent2")
        p.appendUInt32(0x01020304)
        p.appendUInt32(3333)
        let parents = MessageParser.parsePossibleParents(p)
        #expect(parents?.count == 2)
        #expect(parents?[0] == MessageParser.PossibleParentInfo(username: "parent1", ip: "10.11.12.13", port: 2234))
        #expect(parents?[1] == MessageParser.PossibleParentInfo(username: "parent2", ip: "1.2.3.4", port: 3333))
    }

    @Test("parseRecommendations — recommendations + unrecommendations")
    func testRecommendationsBoth() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("ambient"); p.appendInt32(12)
        p.appendString("techno"); p.appendInt32(4)
        p.appendUInt32(1)
        p.appendString("pop"); p.appendInt32(-5)
        let info = MessageParser.parseRecommendations(p)
        #expect(info?.recommendations == [
            .init(item: "ambient", score: 12),
            .init(item: "techno", score: 4)
        ])
        #expect(info?.unrecommendations == [.init(item: "pop", score: -5)])
    }

    @Test("parseRecommendations — unrecommendations section missing returns empty")
    func testRecommendationsNoUnrec() {
        var p = Data()
        p.appendUInt32(1)
        p.appendString("jazz"); p.appendInt32(1)
        // No unrecommendations section.
        let info = MessageParser.parseRecommendations(p)
        #expect(info?.recommendations.count == 1)
        #expect(info?.unrecommendations.isEmpty == true)
    }

    @Test("parseUserInterests")
    func testUserInterests() {
        var p = Data()
        p.appendString("bob")
        p.appendUInt32(2)
        p.appendString("flac"); p.appendString("vinyl")
        p.appendUInt32(1)
        p.appendString("lossy")
        let info = MessageParser.parseUserInterests(p)
        #expect(info == MessageParser.UserInterestsInfo(
            username: "bob", likes: ["flac", "vinyl"], hates: ["lossy"]
        ))
    }

    @Test("parseSimilarUsers")
    func testSimilarUsers() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("twinA"); p.appendUInt32(95)
        p.appendString("twinB"); p.appendUInt32(70)
        let users = MessageParser.parseSimilarUsers(p)
        #expect(users == [
            .init(username: "twinA", rating: 95),
            .init(username: "twinB", rating: 70)
        ])
    }

    @Test("parseRoomTickerState")
    func testRoomTickerState() {
        var p = Data()
        p.appendString("Lounge")
        p.appendUInt32(2)
        p.appendString("alice"); p.appendString("afk")
        p.appendString("bob"); p.appendString("listening")
        let info = MessageParser.parseRoomTickerState(p)
        #expect(info?.room == "Lounge")
        #expect(info?.tickers == [
            .init(username: "alice", ticker: "afk"),
            .init(username: "bob", ticker: "listening")
        ])
    }

    @Test("parseRoomMembers")
    func testRoomMembers() {
        var p = Data()
        p.appendString("friends")
        p.appendUInt32(3)
        p.appendString("alice"); p.appendString("bob"); p.appendString("carol")
        let info = MessageParser.parseRoomMembers(p)
        #expect(info == MessageParser.RoomMembersInfo(
            room: "friends", members: ["alice", "bob", "carol"]
        ))
    }

    @Test("parseExcludedSearchPhrases")
    func testExcludedPhrases() {
        var p = Data()
        p.appendUInt32(2)
        p.appendString("spam1")
        p.appendString("spam2")
        let phrases = MessageParser.parseExcludedSearchPhrases(p)
        #expect(phrases == ["spam1", "spam2"])
    }

    @Test("parseDistributedSearch")
    func testDistributedSearch() {
        var p = Data()
        p.appendUInt32(0)
        p.appendString("searcher")
        p.appendUInt32(0xCAFEBABE)
        p.appendString("pink floyd flac")
        let info = MessageParser.parseDistributedSearch(p)
        #expect(info == MessageParser.DistributedSearchInfo(
            unknown: 0, username: "searcher", token: 0xCAFEBABE, query: "pink floyd flac"
        ))
    }

    // MARK: - Peer messages

    @Test("parseTransferReply — accepted")
    func testTransferReplyAccepted() {
        var p = Data()
        p.appendUInt32(77)        // token
        p.appendBool(true)        // allowed
        p.appendUInt64(1_048_576) // filesize
        let info = MessageParser.parseTransferReply(p)
        #expect(info == MessageParser.TransferReplyInfo(
            token: 77, allowed: true, fileSize: 1_048_576, reason: nil
        ))
    }

    @Test("parseTransferReply — rejected carries reason")
    func testTransferReplyRejected() {
        var p = Data()
        p.appendUInt32(88)
        p.appendBool(false)
        p.appendString("Queued")
        let info = MessageParser.parseTransferReply(p)
        #expect(info == MessageParser.TransferReplyInfo(
            token: 88, allowed: false, fileSize: nil, reason: "Queued"
        ))
    }

    @Test("parseUserInfoReply — full fields + picture")
    func testUserInfoReplyFull() {
        let pic = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00]) // JPEG magic bytes
        var p = Data()
        p.appendString("SeeleSeek user")
        p.appendBool(true)
        p.appendUInt32(UInt32(pic.count))
        p.append(pic)
        p.appendUInt32(42)   // totalUploads
        p.appendUInt32(7)    // queueSize
        p.appendBool(true)   // freeSlots
        let info = MessageParser.parseUserInfoReply(p)
        #expect(info?.description == "SeeleSeek user")
        #expect(info?.hasPicture == true)
        #expect(info?.pictureData == pic)
        #expect(info?.totalUploads == 42)
        #expect(info?.queueSize == 7)
        #expect(info?.hasFreeSlots == true)
    }

    @Test("parseUserInfoReply — no picture")
    func testUserInfoReplyNoPicture() {
        var p = Data()
        p.appendString("")
        p.appendBool(false)
        p.appendUInt32(0)
        p.appendUInt32(0)
        p.appendBool(false)
        let info = MessageParser.parseUserInfoReply(p)
        #expect(info?.hasPicture == false)
        #expect(info?.pictureData == nil)
        #expect(info?.hasFreeSlots == false)
    }

    @Test("parseTransferRequest — upload with file size")
    func testTransferRequestUpload() {
        var p = Data()
        p.appendUInt32(UInt32(FileTransferDirection.upload.rawValue))
        p.appendUInt32(99)
        p.appendString("song.flac")
        p.appendUInt64(12_345_678)
        let info = MessageParser.parseTransferRequest(p)
        #expect(info == MessageParser.TransferRequestInfo(
            direction: .upload, token: 99, filename: "song.flac", fileSize: 12_345_678
        ))
    }

    @Test("parseTransferRequest — download has no trailing size")
    func testTransferRequestDownload() {
        var p = Data()
        p.appendUInt32(UInt32(FileTransferDirection.download.rawValue))
        p.appendUInt32(100)
        p.appendString("song.mp3")
        let info = MessageParser.parseTransferRequest(p)
        #expect(info == MessageParser.TransferRequestInfo(
            direction: .download, token: 100, filename: "song.mp3", fileSize: nil
        ))
    }

    // MARK: - Security limits

    @Test("Security: file counts over maxItemCount rejected")
    func testSecurityLimits() {
        var p = Data()
        p.appendUInt32(MessageParser.maxItemCount + 1) // exceeds limit
        #expect(MessageParser.parsePossibleParents(p) == nil)
        #expect(MessageParser.parseSimilarUsers(p) == nil)
        #expect(MessageParser.parseExcludedSearchPhrases(p) == nil)
    }
}
