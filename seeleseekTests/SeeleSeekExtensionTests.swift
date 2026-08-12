import Testing
import Foundation
import AppKit
@testable import SeeleseekCore
@testable import seeleseek

// MARK: - Message Builder Tests

@Suite("SeeleSeek Extension Message Builder")
struct SeeleSeekMessageBuilderTests {

    @Test("ExtendedClientInfo message has correct code and parses back")
    func extendedClientInfoMessageFormat() {
        let message = MessageBuilder.extendedClientInfoMessage()

        let length = message.readUInt32(at: 0)
        #expect(length != nil)
        #expect(Int(length!) + 4 == message.count)

        let code = message.readUInt32(at: 4)
        #expect(code == ExtendedClientInfoCode.extendedClientInfo.rawValue)
        #expect(code == 10000)

        // Payload begins after the length prefix and the message code.
        let info = MessageParser.parseExtendedClientInfo(Data(message[8...]))
        #expect(info?.revision == ExtendedClientInfo.currentRevision)
        // Sent by default, so the field is not dead on the wire. The exact
        // string tracks the host bundle version, hence the prefix check.
        #expect(info?.clientInfo == ExtendedClientInfo.localClientInfo)
        #expect(info?.clientInfo.hasPrefix("SeeleSeek/") == true)
        for advertised in ExtendedClientInfoCode.advertised {
            #expect(info?.supports(advertised) == true)
        }
    }

    @Test("Client info string is sent verbatim when provided")
    func extendedClientInfoCarriesClientString() {
        let message = MessageBuilder.extendedClientInfoMessage(clientInfo: "SeeleSeek/1.2")
        let info = MessageParser.parseExtendedClientInfo(Data(message[8...]))
        #expect(info?.clientInfo == "SeeleSeek/1.2")
    }

    @Test("Advertising a subset omits the rest")
    func extendedClientInfoSubset() {
        let message = MessageBuilder.extendedClientInfoMessage(advertising: [.extendedClientInfo])
        let info = MessageParser.parseExtendedClientInfo(Data(message[8...]))
        #expect(info?.supports(.extendedClientInfo) == true)
        #expect(info?.supports(.artworkRequest) == false)
        #expect(info?.supports(.artworkReply) == false)
    }

    @Test("Artwork request message has correct structure")
    func artworkRequestMessageFormat() {
        let token: UInt32 = 42
        let filePath = "Music\\Albums\\Artist - Album\\01 - Track.flac"
        let message = MessageBuilder.artworkRequestMessage(token: token, filePath: filePath)

        // Format: [length][code=10001][token][string filePath]
        let msgLength = message.readUInt32(at: 0)
        #expect(msgLength != nil)
        #expect(Int(msgLength!) + 4 == message.count)

        let code = message.readUInt32(at: 4)
        #expect(code == ExtendedClientInfoCode.artworkRequest.rawValue)
        #expect(code == 10001)

        let parsedToken = message.readUInt32(at: 8)
        #expect(parsedToken == token)

        let parsedPath = message.readString(at: 12)
        #expect(parsedPath?.string == filePath)
    }

    @Test("Artwork reply message with image data")
    func artworkReplyWithData() {
        let token: UInt32 = 99
        // Fake JPEG header (starts with 0xFF 0xD8)
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let message = MessageBuilder.artworkReplyMessage(token: token, imageData: imageData)

        let msgLength = message.readUInt32(at: 0)
        #expect(msgLength != nil)
        #expect(Int(msgLength!) + 4 == message.count)

        let code = message.readUInt32(at: 4)
        #expect(code == ExtendedClientInfoCode.artworkReply.rawValue)
        #expect(code == 10002)

        let parsedToken = message.readUInt32(at: 8)
        #expect(parsedToken == token)

        // Image data starts at offset 12 (after length + code + token)
        let parsedImageData = Data(message[12...])
        #expect(parsedImageData == imageData)
    }

    @Test("Artwork reply message with empty data (no artwork)")
    func artworkReplyEmpty() {
        let token: UInt32 = 100
        let message = MessageBuilder.artworkReplyMessage(token: token, imageData: Data())

        // Format: [length][code=10002][token] — no image bytes
        #expect(message.count == 4 + 4 + 4) // length + code + token

        let code = message.readUInt32(at: 4)
        #expect(code == ExtendedClientInfoCode.artworkReply.rawValue)

        let parsedToken = message.readUInt32(at: 8)
        #expect(parsedToken == token)
    }

    @Test("Artwork request with unicode file path")
    func artworkRequestUnicode() {
        let filePath = "Музыка\\Артист\\Трек.mp3"
        let message = MessageBuilder.artworkRequestMessage(token: 1, filePath: filePath)

        let parsedPath = message.readString(at: 12)
        #expect(parsedPath?.string == filePath)
    }

    @Test("Artwork request with long file path")
    func artworkRequestLongPath() {
        let filePath = String(repeating: "Music\\", count: 100) + "track.flac"
        let message = MessageBuilder.artworkRequestMessage(token: 1, filePath: filePath)

        let parsedPath = message.readString(at: 12)
        #expect(parsedPath?.string == filePath)
    }
}

// MARK: - Extension Code Enum Tests

@Suite("ExtendedClientInfoCode Enum")
struct SeeleSeekExtendedClientInfoCodeTests {

    @Test("Code values are in 10000+ range")
    func codeValues() {
        #expect(ExtendedClientInfoCode.extendedClientInfo.rawValue == 10000)
        #expect(ExtendedClientInfoCode.artworkRequest.rawValue == 10001)
        #expect(ExtendedClientInfoCode.artworkReply.rawValue == 10002)
    }

    @Test("Codes don't overlap with standard peer codes")
    func noOverlapWithStandardCodes() {
        let standardCodes: [UInt32] = [0, 1, 4, 5, 8, 9, 15, 16, 36, 37, 40, 41, 42, 43, 44, 46, 50, 51, 52]
        for code in ExtendedClientInfoCode.allCases {
            #expect(!standardCodes.contains(code.rawValue),
                    "Extension code \(code.rawValue) overlaps with standard peer code")
        }
    }

    /// Wire names are the identity peers match on, so they are part of the
    /// protocol contract and must not be renamed casually.
    @Test("Wire names match the published spec")
    func wireNames() {
        #expect(ExtendedClientInfoCode.extendedClientInfo.wireName == "ExtendedClientInfo")
        #expect(ExtendedClientInfoCode.artworkRequest.wireName == "ArtworkRequest")
        #expect(ExtendedClientInfoCode.artworkReply.wireName == "ArtworkReply")
    }

    @Test("Init from raw value round-trips")
    func rawValueRoundTrip() {
        for code in ExtendedClientInfoCode.allCases {
            #expect(ExtendedClientInfoCode(rawValue: code.rawValue) == code)
        }
    }

    @Test("Init from unknown raw value returns nil")
    func unknownRawValue() {
        #expect(ExtendedClientInfoCode(rawValue: 9999) == nil)
        #expect(ExtendedClientInfoCode(rawValue: 10003) == nil)
        #expect(ExtendedClientInfoCode(rawValue: 0) == nil)
    }
}

// MARK: - ExtendedClientInfo Parsing

/// The parser is the only thing standing between a hostile peer and our
/// message loop, so the malformed cases matter more than the happy path.
@Suite("ExtendedClientInfo parsing")
struct ExtendedClientInfoParsingTests {

    private func advertisement(
        revision: UInt32 = 1,
        clientInfo: String = "",
        declaredCount: UInt32? = nil,
        entries: [(UInt32, String)]
    ) -> Data {
        var d = Data()
        d.appendUInt32(revision)
        d.appendString(clientInfo)
        d.appendUInt32(declaredCount ?? UInt32(entries.count))
        for (code, name) in entries {
            d.appendUInt32(code)
            d.appendString(name)
            d.appendUInt32(0)
        }
        return d
    }

    @Test("Unknown revision is rejected rather than guessed at")
    func unknownRevisionRejected() {
        let d = advertisement(revision: 2, entries: [(10001, "ArtworkRequest")])
        #expect(MessageParser.parseExtendedClientInfo(d) == nil)
    }

    @Test("Truncated entry is rejected")
    func truncatedRejected() {
        let full = advertisement(entries: [(10001, "ArtworkRequest")])
        let chopped = Data(full.prefix(full.count - 3))
        #expect(MessageParser.parseExtendedClientInfo(chopped) == nil)
    }

    @Test("Count larger than the body is rejected")
    func lyingCountRejected() {
        let d = advertisement(declaredCount: 5, entries: [(10001, "ArtworkRequest")])
        #expect(MessageParser.parseExtendedClientInfo(d) == nil)
    }

    @Test("Count over the cap is rejected before iterating")
    func oversizedCountRejected() {
        let d = advertisement(declaredCount: .max, entries: [])
        #expect(MessageParser.parseExtendedClientInfo(d) == nil)
    }

    @Test("Empty advertisement parses but supports nothing")
    func emptyAdvertisement() {
        let info = MessageParser.parseExtendedClientInfo(advertisement(entries: []))
        #expect(info != nil)
        #expect(info?.supports(.artworkRequest) == false)
    }

    /// The spec says a mismatched code means we must not send that message,
    /// even when the name is one we know.
    @Test("Known name bound to a different code is not supported")
    func mismatchedCodeNotSupported() {
        let info = MessageParser.parseExtendedClientInfo(
            advertisement(entries: [(10005, "ArtworkRequest")])
        )
        #expect(info != nil)
        #expect(info?.supports(.artworkRequest) == false)
    }

    @Test("Unknown capability names are retained, not dropped")
    func unknownNamesRetained() {
        let info = MessageParser.parseExtendedClientInfo(
            advertisement(entries: [(10042, "SomeOtherFeature")])
        )
        #expect(info?.capabilities["SomeOtherFeature"] == 10042)
    }

    @Test("Client info string round-trips")
    func clientInfoRoundTrip() {
        let info = MessageParser.parseExtendedClientInfo(
            advertisement(clientInfo: "OtherClient/2.1", entries: [])
        )
        #expect(info?.clientInfo == "OtherClient/2.1")
    }

    @Test("Empty payload is rejected")
    func emptyPayloadRejected() {
        #expect(MessageParser.parseExtendedClientInfo(Data()) == nil)
    }

    /// SeeleSeek 1.x sent a bare version byte at code 10000. Rejecting it is
    /// intentional — those peers advertised nothing, so they get nothing.
    @Test("Legacy one-byte handshake is rejected, not special-cased")
    func legacyPayloadRejected() {
        #expect(MessageParser.parseExtendedClientInfo(Data([1])) == nil)
    }
}

// MARK: - Round-Trip Tests (Build → Parse Payload)

@Suite("SeeleSeek Message Round-Trip")
struct SeeleSeekRoundTripTests {

    @Test("Artwork request payload round-trip")
    func artworkRequestRoundTrip() {
        let token: UInt32 = 0x7FFF_FFFF // max positive
        let filePath = "@@music\\Albums\\Pink Floyd\\The Dark Side of the Moon\\03 - Time.flac"

        let message = MessageBuilder.artworkRequestMessage(token: token, filePath: filePath)

        // Skip length (4) and code (4) to get payload
        let payload = Data(message[8...])

        // Parse token
        let parsedToken = payload.readUInt32(at: 0)
        #expect(parsedToken == token)

        // Parse file path
        let parsedPath = payload.readString(at: 4)
        #expect(parsedPath?.string == filePath)
    }

    @Test("Artwork reply payload round-trip with large image")
    func artworkReplyLargeImageRoundTrip() {
        let token: UInt32 = 55555
        // Simulate a 100KB JPEG
        var imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        imageData.append(Data(repeating: 0xAA, count: 100_000))

        let message = MessageBuilder.artworkReplyMessage(token: token, imageData: imageData)

        // Skip length (4) and code (4) to get payload
        let payload = Data(message[8...])

        let parsedToken = payload.readUInt32(at: 0)
        #expect(parsedToken == token)

        // Remaining bytes are the image
        let parsedImage = Data(payload[4...])
        #expect(parsedImage.count == imageData.count)
        #expect(parsedImage == imageData)
    }
}

// MARK: - MetadataReader Tests

@Suite("MetadataReader")
struct MetadataReaderTests {

    @Test("Extract artwork returns nil for non-existent file")
    func extractFromNonExistentFile() async {
        let reader = MetadataReader()
        let url = URL(fileURLWithPath: "/tmp/nonexistent_audio_file.mp3")
        let artwork = await reader.extractArtwork(from: url)
        #expect(artwork == nil)
    }

    @Test("Extract artwork from directory returns nil for empty directory")
    func extractFromEmptyDirectory() async throws {
        let reader = MetadataReader()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeleseek_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artwork = await reader.extractArtworkFromDirectory(tmpDir)
        #expect(artwork == nil)
    }

    @Test("Extract artwork from directory skips non-audio files")
    func extractSkipsNonAudio() async throws {
        let reader = MetadataReader()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeleseek_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a non-audio file
        let textFile = tmpDir.appendingPathComponent("readme.txt")
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)

        let artwork = await reader.extractArtworkFromDirectory(tmpDir)
        #expect(artwork == nil)
    }

    @Test("Set folder icon returns false for invalid image data")
    func setFolderIconInvalidData() async {
        let reader = MetadataReader()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeleseek_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let result = await reader.setFolderIcon(imageData: Data([0x00, 0x01, 0x02]), forDirectory: tmpDir)
        #expect(result == false)
    }

    @Test("Set folder icon succeeds with valid PNG data")
    func setFolderIconValidPNG() async throws {
        let reader = MetadataReader()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeleseek_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a minimal 1x1 red PNG
        let pngData = createMinimalPNG()
        let result = await reader.setFolderIcon(imageData: pngData, forDirectory: tmpDir)
        #expect(result == true)
    }

    @Test("Apply artwork as folder icon returns false when no audio files exist")
    func applyArtworkNoAudioFiles() async throws {
        let reader = MetadataReader()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeleseek_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let result = await reader.applyArtworkAsFolderIcon(for: tmpDir)
        #expect(result == false)
    }
}

// MARK: - Regression: Existing Peer Message Codes Unaffected

@Suite("Regression: Standard Peer Codes")
struct StandardPeerCodeRegressionTests {

    @Test("Standard PeerMessageCode values unchanged")
    func standardCodeValues() {
        // Verify no accidental changes to existing codes
        #expect(PeerMessageCode.pierceFirewall.rawValue == 0)
        #expect(PeerMessageCode.peerInit.rawValue == 1)
        #expect(PeerMessageCode.sharesRequest.rawValue == 4)
        #expect(PeerMessageCode.sharesReply.rawValue == 5)
        #expect(PeerMessageCode.searchRequest.rawValue == 8)
        #expect(PeerMessageCode.searchReply.rawValue == 9)
        #expect(PeerMessageCode.userInfoRequest.rawValue == 15)
        #expect(PeerMessageCode.userInfoReply.rawValue == 16)
        #expect(PeerMessageCode.folderContentsRequest.rawValue == 36)
        #expect(PeerMessageCode.folderContentsReply.rawValue == 37)
        #expect(PeerMessageCode.transferRequest.rawValue == 40)
        #expect(PeerMessageCode.transferReply.rawValue == 41)
        #expect(PeerMessageCode.uploadPlacehold.rawValue == 42)
        #expect(PeerMessageCode.queueDownload.rawValue == 43)
        #expect(PeerMessageCode.placeInQueueReply.rawValue == 44)
        #expect(PeerMessageCode.uploadFailed.rawValue == 46)
        #expect(PeerMessageCode.uploadDenied.rawValue == 50)
        #expect(PeerMessageCode.placeInQueueRequest.rawValue == 51)
        #expect(PeerMessageCode.uploadQueueNotification.rawValue == 52)
    }

    @Test("Standard message builders still produce correct codes")
    func standardBuilderCodes() {
        // Shares request
        let shares = MessageBuilder.sharesRequestMessage()
        #expect(shares.readUInt32(at: 4) == 4)

        // User info request
        let userInfo = MessageBuilder.userInfoRequestMessage()
        #expect(userInfo.readUInt32(at: 4) == 15)

        // PeerInit still uses UInt8 code
        let peerInit = MessageBuilder.peerInitMessage(username: "test", connectionType: "P", token: 0)
        #expect(peerInit.readByte(at: 4) == 1)

        // PierceFirewall still uses UInt8 code
        let pierce = MessageBuilder.pierceFirewallMessage(token: 123)
        #expect(pierce.readByte(at: 4) == 0)
    }

    @Test("Search reply parsing still works")
    func searchReplyStillWorks() {
        var payload = Data()
        payload.appendString("testuser")
        payload.appendUInt32(12345) // token
        payload.appendUInt32(1) // 1 file
        payload.appendUInt8(1) // code
        payload.appendString("Music\\test.mp3")
        payload.appendUInt64(1_000_000)
        payload.appendString("mp3")
        payload.appendUInt32(0) // 0 attributes
        payload.appendBool(true) // free slots
        payload.appendUInt32(500000) // speed
        payload.appendUInt32(0) // queue

        let parsed = MessageParser.parseSearchReply(payload)
        #expect(parsed != nil)
        #expect(parsed?.username == "testuser")
        #expect(parsed?.token == 12345)
        #expect(parsed?.files.count == 1)
    }
}

// MARK: - Test Helpers

/// Create a minimal valid PNG for testing using AppKit
private func createMinimalPNG() -> Data {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 1, height: 1).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        return Data()
    }
    return png
}
