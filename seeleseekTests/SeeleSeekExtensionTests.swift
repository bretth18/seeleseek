import Testing
import Foundation
import AppKit
@testable import seeleseek

// MARK: - Message Builder Tests

@Suite("SeeleSeek Extension Message Builder")
struct SeeleSeekMessageBuilderTests {

    @Test("Handshake message has correct code and version")
    func handshakeMessageFormat() {
        let message = MessageBuilder.seeleseekHandshakeMessage()

        // Format: [length uint32][code uint32][version uint8]
        #expect(message.count == 4 + 4 + 1) // length(4) + code(4) + version(1)

        let length = message.readUInt32(at: 0)
        #expect(length == 5) // code(4) + version(1)

        let code = message.readUInt32(at: 4)
        #expect(code == SeeleSeekPeerCode.handshake.rawValue)
        #expect(code == 10000)

        let version = message.readByte(at: 8)
        #expect(version == 1)
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
        #expect(code == SeeleSeekPeerCode.artworkRequest.rawValue)
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
        #expect(code == SeeleSeekPeerCode.artworkReply.rawValue)
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
        #expect(code == SeeleSeekPeerCode.artworkReply.rawValue)

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

// MARK: - SeeleSeekPeerCode Enum Tests

@Suite("SeeleSeekPeerCode Enum")
struct SeeleSeekPeerCodeTests {

    @Test("Code values are in 10000+ range")
    func codeValues() {
        #expect(SeeleSeekPeerCode.handshake.rawValue == 10000)
        #expect(SeeleSeekPeerCode.artworkRequest.rawValue == 10001)
        #expect(SeeleSeekPeerCode.artworkReply.rawValue == 10002)
    }

    @Test("Codes don't overlap with standard peer codes")
    func noOverlapWithStandardCodes() {
        let standardCodes: [UInt32] = [0, 1, 4, 5, 8, 9, 15, 16, 36, 37, 40, 41, 42, 43, 44, 46, 50, 51, 52]
        for code in SeeleSeekPeerCode.allCases {
            #expect(!standardCodes.contains(code.rawValue),
                    "SeeleSeek code \(code.rawValue) overlaps with standard peer code")
        }
    }

    @Test("Code descriptions are meaningful")
    func codeDescriptions() {
        #expect(SeeleSeekPeerCode.handshake.description == "SeeleSeekHandshake")
        #expect(SeeleSeekPeerCode.artworkRequest.description == "ArtworkRequest")
        #expect(SeeleSeekPeerCode.artworkReply.description == "ArtworkReply")
    }

    @Test("Init from raw value round-trips")
    func rawValueRoundTrip() {
        for code in SeeleSeekPeerCode.allCases {
            let fromRaw = SeeleSeekPeerCode(rawValue: code.rawValue)
            #expect(fromRaw == code)
        }
    }

    @Test("Init from unknown raw value returns nil")
    func unknownRawValue() {
        #expect(SeeleSeekPeerCode(rawValue: 9999) == nil)
        #expect(SeeleSeekPeerCode(rawValue: 10003) == nil)
        #expect(SeeleSeekPeerCode(rawValue: 0) == nil)
    }
}

// MARK: - Round-Trip Tests (Build → Parse Payload)

@Suite("SeeleSeek Message Round-Trip")
struct SeeleSeekRoundTripTests {

    @Test("Handshake message payload round-trip")
    func handshakeRoundTrip() {
        let message = MessageBuilder.seeleseekHandshakeMessage()

        // Skip length prefix (4 bytes) and code (4 bytes) to get payload
        let payload = Data(message[8...])

        // Parse: version byte
        #expect(payload.count == 1)
        #expect(payload[payload.startIndex] == 1)
    }

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
