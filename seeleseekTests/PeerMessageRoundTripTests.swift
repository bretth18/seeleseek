import Testing
import Foundation
@testable import seeleseek

/// Round-trip every peer message builder: build → read back code + all fields from wire-format Data.
/// Peer init messages use UInt8 codes; regular peer messages use UInt32 codes.
/// Wire format: [uint32 length][payload...] where payload starts with the code.
@Suite("Peer Message Round-Trip Tests")
struct PeerMessageRoundTripTests {

    // MARK: - Helpers

    /// For peer init messages (UInt8 code): [uint32 length][uint8 code][payload...]
    private func parseInitMessage(_ data: Data) -> (code: UInt8, payloadStart: Int) {
        let code = data.readUInt8(at: 4)!
        return (code, 5)
    }

    /// For regular peer messages (UInt32 code): [uint32 length][uint32 code][payload...]
    private func parsePeerMessage(_ data: Data) -> (code: UInt32, payloadStart: Int) {
        let code = data.readUInt32(at: 4)!
        return (code, 8)
    }

    // MARK: - Init Messages (UInt8 code)

    @Test("peerInit message - type P")
    func testPeerInitP() {
        let msg = MessageBuilder.peerInitMessage(username: "alice", connectionType: "P", token: 12345)
        let (code, off) = parseInitMessage(msg)
        #expect(code == PeerMessageCode.peerInit.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "alice")
        let (connType, ctLen) = msg.readString(at: o)!; o += ctLen
        #expect(connType == "P")
        #expect(msg.readUInt32(at: o) == 12345)
    }

    @Test("peerInit message - type F")
    func testPeerInitF() {
        let msg = MessageBuilder.peerInitMessage(username: "bob", connectionType: "F", token: 9999)
        let (code, off) = parseInitMessage(msg)
        #expect(code == PeerMessageCode.peerInit.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "bob")
        let (connType, ctLen) = msg.readString(at: o)!; o += ctLen
        #expect(connType == "F")
        #expect(msg.readUInt32(at: o) == 9999)
    }

    @Test("peerInit message - type D")
    func testPeerInitD() {
        let msg = MessageBuilder.peerInitMessage(username: "carol", connectionType: "D", token: 0)
        let (code, off) = parseInitMessage(msg)
        #expect(code == PeerMessageCode.peerInit.rawValue)
        var o = off
        let (user, uLen) = msg.readString(at: o)!; o += uLen
        #expect(user == "carol")
        let (connType, ctLen) = msg.readString(at: o)!; o += ctLen
        #expect(connType == "D")
        #expect(msg.readUInt32(at: o) == 0)
    }

    @Test("pierceFirewall message")
    func testPierceFirewall() {
        let msg = MessageBuilder.pierceFirewallMessage(token: 55555)
        let (code, off) = parseInitMessage(msg)
        #expect(code == PeerMessageCode.pierceFirewall.rawValue)
        #expect(msg.readUInt32(at: off) == 55555)
    }

    // MARK: - Regular Peer Messages (UInt32 code)

    @Test("sharesRequest message (code-only)")
    func testSharesRequest() {
        let msg = MessageBuilder.sharesRequestMessage()
        let (code, _) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.sharesRequest.rawValue))
    }

    @Test("userInfoRequest message (code-only)")
    func testUserInfoRequest() {
        let msg = MessageBuilder.userInfoRequestMessage()
        let (code, _) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.userInfoRequest.rawValue))
    }

    @Test("userInfoResponse without picture")
    func testUserInfoResponseNoPicture() {
        let msg = MessageBuilder.userInfoResponseMessage(
            description: "I love music",
            totalUploads: 100,
            queueSize: 5,
            hasFreeSlots: true
        )
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.userInfoReply.rawValue))
        var o = off
        let (desc, dLen) = msg.readString(at: o)!; o += dLen
        #expect(desc == "I love music")
        #expect(msg.readUInt8(at: o) == 0) // no picture
        o += 1
        #expect(msg.readUInt32(at: o) == 100); o += 4
        #expect(msg.readUInt32(at: o) == 5); o += 4
        #expect(msg.readUInt8(at: o) == 1) // hasFreeSlots = true
    }

    @Test("userInfoResponse with picture")
    func testUserInfoResponseWithPicture() {
        let pictureData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header stub
        let msg = MessageBuilder.userInfoResponseMessage(
            description: "Hi",
            picture: pictureData,
            totalUploads: 50,
            queueSize: 2,
            hasFreeSlots: false
        )
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.userInfoReply.rawValue))
        var o = off
        let (desc, dLen) = msg.readString(at: o)!; o += dLen
        #expect(desc == "Hi")
        #expect(msg.readUInt8(at: o) == 1) // has picture
        o += 1
        let picLen = msg.readUInt32(at: o)!; o += 4
        #expect(picLen == 4)
        let picData = msg.safeSubdata(in: o..<(o + Int(picLen)))
        #expect(picData == pictureData)
        o += Int(picLen)
        #expect(msg.readUInt32(at: o) == 50); o += 4
        #expect(msg.readUInt32(at: o) == 2); o += 4
        #expect(msg.readUInt8(at: o) == 0) // hasFreeSlots = false
    }

    @Test("queueDownload message")
    func testQueueDownload() {
        let msg = MessageBuilder.queueDownloadMessage(filename: "Music\\Artist\\Song.mp3")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.queueDownload.rawValue))
        let (filename, _) = msg.readString(at: off)!
        #expect(filename == "Music\\Artist\\Song.mp3")
    }

    @Test("transferRequest - upload with fileSize")
    func testTransferRequestUpload() {
        let msg = MessageBuilder.transferRequestMessage(
            direction: .upload,
            token: 11111,
            filename: "Music\\song.flac",
            fileSize: 50_000_000
        )
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.transferRequest.rawValue))
        var o = off
        #expect(msg.readUInt32(at: o) == 1); o += 4 // upload = 1
        #expect(msg.readUInt32(at: o) == 11111); o += 4
        let (fn, fnLen) = msg.readString(at: o)!; o += fnLen
        #expect(fn == "Music\\song.flac")
        #expect(msg.readUInt64(at: o) == 50_000_000)
    }

    @Test("transferRequest - download (no fileSize)")
    func testTransferRequestDownload() {
        let msg = MessageBuilder.transferRequestMessage(
            direction: .download,
            token: 22222,
            filename: "Music\\other.mp3"
        )
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.transferRequest.rawValue))
        var o = off
        #expect(msg.readUInt32(at: o) == 0); o += 4 // download = 0
        #expect(msg.readUInt32(at: o) == 22222); o += 4
        let (fn, fnLen) = msg.readString(at: o)!; o += fnLen
        #expect(fn == "Music\\other.mp3")
        // No fileSize should follow for download
        let length = msg.readUInt32(at: 0)!
        #expect(Int(length) + 4 == msg.count)
        #expect(o == msg.count) // consumed all bytes
    }

    @Test("transferRequest round-trip via MessageParser.parseTransferRequest")
    func testTransferRequestParse() {
        let msg = MessageBuilder.transferRequestMessage(
            direction: .upload,
            token: 33333,
            filename: "path\\to\\file.wav",
            fileSize: 123456789
        )
        // Skip frame: length(4) + code(4) = 8
        let payload = msg.subdata(in: 8..<msg.count)
        let parsed = MessageParser.parseTransferRequest(payload)
        #expect(parsed != nil)
        #expect(parsed?.direction == .upload)
        #expect(parsed?.token == 33333)
        #expect(parsed?.filename == "path\\to\\file.wav")
        #expect(parsed?.fileSize == 123456789)
    }

    @Test("transferReply - allowed with fileSize")
    func testTransferReplyAllowed() {
        let msg = MessageBuilder.transferReplyMessage(token: 44444, allowed: true, fileSize: 9999999)
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.transferReply.rawValue))
        var o = off
        #expect(msg.readUInt32(at: o) == 44444); o += 4
        #expect(msg.readBool(at: o) == true); o += 1
        #expect(msg.readUInt64(at: o) == 9999999)
    }

    @Test("transferReply - denied with reason")
    func testTransferReplyDenied() {
        let msg = MessageBuilder.transferReplyMessage(token: 55555, allowed: false, reason: "Queued")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.transferReply.rawValue))
        var o = off
        #expect(msg.readUInt32(at: o) == 55555); o += 4
        #expect(msg.readBool(at: o) == false); o += 1
        let (reason, _) = msg.readString(at: o)!
        #expect(reason == "Queued")
    }

    @Test("placeInQueueResponse message")
    func testPlaceInQueueResponse() {
        let msg = MessageBuilder.placeInQueueResponseMessage(filename: "Music\\song.mp3", place: 7)
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.placeInQueueReply.rawValue))
        var o = off
        let (fn, fnLen) = msg.readString(at: o)!; o += fnLen
        #expect(fn == "Music\\song.mp3")
        #expect(msg.readUInt32(at: o) == 7)
    }

    @Test("placeInQueueRequest message")
    func testPlaceInQueueRequest() {
        let msg = MessageBuilder.placeInQueueRequestMessage(filename: "Music\\track.flac")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.placeInQueueRequest.rawValue))
        let (fn, _) = msg.readString(at: off)!
        #expect(fn == "Music\\track.flac")
    }

    @Test("uploadDenied message")
    func testUploadDenied() {
        let msg = MessageBuilder.uploadDeniedMessage(filename: "Music\\file.mp3", reason: "Too many queued")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.uploadDenied.rawValue))
        var o = off
        let (fn, fnLen) = msg.readString(at: o)!; o += fnLen
        #expect(fn == "Music\\file.mp3")
        let (reason, _) = msg.readString(at: o)!
        #expect(reason == "Too many queued")
    }

    @Test("uploadFailed message")
    func testUploadFailed() {
        let msg = MessageBuilder.uploadFailedMessage(filename: "Music\\broken.mp3")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.uploadFailed.rawValue))
        let (fn, _) = msg.readString(at: off)!
        #expect(fn == "Music\\broken.mp3")
    }

    @Test("folderContentsRequest message")
    func testFolderContentsRequest() {
        let msg = MessageBuilder.folderContentsRequestMessage(token: 77777, folder: "Music\\Albums\\Best Of")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == UInt32(PeerMessageCode.folderContentsRequest.rawValue))
        var o = off
        #expect(msg.readUInt32(at: o) == 77777); o += 4
        let (folder, _) = msg.readString(at: o)!
        #expect(folder == "Music\\Albums\\Best Of")
    }

    // MARK: - SeeleSeek Extension Messages

    @Test("seeleseekHandshake message")
    func testSeeleSeekHandshake() {
        let msg = MessageBuilder.seeleseekHandshakeMessage()
        let (code, off) = parsePeerMessage(msg)
        #expect(code == SeeleSeekPeerCode.handshake.rawValue)
        #expect(msg.readUInt8(at: off) == 1) // version
    }

    @Test("artworkRequest message")
    func testArtworkRequest() {
        let msg = MessageBuilder.artworkRequestMessage(token: 88888, filePath: "Music\\artist\\song.mp3")
        let (code, off) = parsePeerMessage(msg)
        #expect(code == SeeleSeekPeerCode.artworkRequest.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 88888); o += 4
        let (path, _) = msg.readString(at: o)!
        #expect(path == "Music\\artist\\song.mp3")
    }

    @Test("artworkReply message")
    func testArtworkReply() {
        let imageData = Data(repeating: 0xAB, count: 256)
        let msg = MessageBuilder.artworkReplyMessage(token: 99999, imageData: imageData)
        let (code, off) = parsePeerMessage(msg)
        #expect(code == SeeleSeekPeerCode.artworkReply.rawValue)
        var o = off
        #expect(msg.readUInt32(at: o) == 99999); o += 4
        // Remaining bytes are image data
        let remaining = msg.subdata(in: o..<msg.count)
        #expect(remaining == imageData)
    }

    // MARK: - Length Consistency

    @Test("all peer messages have consistent length fields")
    func testPeerMessageLengthConsistency() {
        let messages: [Data] = [
            MessageBuilder.sharesRequestMessage(),
            MessageBuilder.userInfoRequestMessage(),
            MessageBuilder.queueDownloadMessage(filename: "test.mp3"),
            MessageBuilder.uploadFailedMessage(filename: "f.mp3"),
            MessageBuilder.placeInQueueRequestMessage(filename: "x"),
            MessageBuilder.pierceFirewallMessage(token: 1),
            MessageBuilder.peerInitMessage(username: "u", connectionType: "P", token: 1),
        ]
        for msg in messages {
            let length = msg.readUInt32(at: 0)!
            #expect(Int(length) + 4 == msg.count)
        }
    }
}
