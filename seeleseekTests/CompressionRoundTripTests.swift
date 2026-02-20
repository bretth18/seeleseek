import Testing
import Foundation
import Compression
@testable import seeleseek

/// Test zlib compression round-trips for the 3 compressed message types:
/// SearchReply (code 9), SharesReply (code 5), FolderContentsResponse (code 37).
///
/// Approach: Build with MessageBuilder (which applies zlib) → strip frame + code →
/// decompress using the same zlib strip logic the app uses → parse decompressed payload.
@Suite("Compression Round-Trip Tests")
struct CompressionRoundTripTests {

    // MARK: - Zlib decompression helper (mirrors PeerConnection.decompressZlib)

    /// Decompress zlib-wrapped data: strip 2-byte header + 4-byte Adler32, then raw DEFLATE.
    private func decompressZlib(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw TestError.tooShort }
        let cmf = data[data.startIndex]
        guard cmf & 0x0F == 8 else { throw TestError.notZlib }

        let deflateData = Data(data.dropFirst(2).dropLast(4))
        return try decompressRawDeflate(deflateData)
    }

    private func decompressRawDeflate(_ data: Data) throws -> Data {
        let maxSize = 50 * 1024 * 1024
        return try data.withUnsafeBytes { sourceBuffer -> Data in
            guard let base = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw TestError.decompressionFailed
            }
            var destSize = min(max(data.count * 20, 65536), maxSize)
            var destBuffer = [UInt8](repeating: 0, count: destSize)
            var decoded = compression_decode_buffer(&destBuffer, destSize, base, data.count, nil, COMPRESSION_ZLIB)

            if decoded == 0 || decoded == destSize {
                destSize = min(destSize * 4, maxSize)
                destBuffer = [UInt8](repeating: 0, count: destSize)
                decoded = compression_decode_buffer(&destBuffer, destSize, base, data.count, nil, COMPRESSION_ZLIB)
            }
            guard decoded > 0 && decoded < destSize else { throw TestError.decompressionFailed }
            return Data(destBuffer.prefix(decoded))
        }
    }

    enum TestError: Error {
        case tooShort, notZlib, decompressionFailed
    }

    /// Extract compressed payload from a built message: skip length(4) + code(4)
    private func extractCompressedPayload(_ message: Data) -> Data {
        message.subdata(in: 8..<message.count)
    }

    // MARK: - SearchReply

    @Test("searchReply - 15 files with attributes")
    func testSearchReply15Files() throws {
        var results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] = []
        for i in 0..<15 {
            results.append((
                filename: "Music\\Artist\\Track\(i).mp3",
                size: UInt64(1_000_000 + i * 100_000),
                extension_: "mp3",
                attributes: [(0, UInt32(320)), (1, UInt32(240 + i))]
            ))
        }
        let msg = MessageBuilder.searchReplyMessage(
            username: "uploader",
            token: 42,
            results: results,
            hasFreeSlots: true,
            uploadSpeed: 500_000,
            queueLength: 10
        )

        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        // Parse decompressed payload
        var o = 0
        let (user, uLen) = decompressed.readString(at: o)!; o += uLen
        #expect(user == "uploader")
        #expect(decompressed.readUInt32(at: o) == 42); o += 4
        let fileCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(fileCount == 15)

        for i in 0..<15 {
            let fileCode = decompressed.readUInt8(at: o)!; o += 1
            #expect(fileCode == 1)
            let (fn, fnLen) = decompressed.readString(at: o)!; o += fnLen
            #expect(fn == "Music\\Artist\\Track\(i).mp3")
            let size = decompressed.readUInt64(at: o)!; o += 8
            #expect(size == UInt64(1_000_000 + i * 100_000))
            let (ext, extLen) = decompressed.readString(at: o)!; o += extLen
            #expect(ext == "mp3")
            let attrCount = decompressed.readUInt32(at: o)!; o += 4
            #expect(attrCount == 2)
            let at0 = decompressed.readUInt32(at: o)!; o += 4
            let av0 = decompressed.readUInt32(at: o)!; o += 4
            #expect(at0 == 0); #expect(av0 == 320)
            let at1 = decompressed.readUInt32(at: o)!; o += 4
            let av1 = decompressed.readUInt32(at: o)!; o += 4
            #expect(at1 == 1); #expect(av1 == UInt32(240 + i))
        }

        #expect(decompressed.readBool(at: o) == true); o += 1
        #expect(decompressed.readUInt32(at: o) == 500_000); o += 4
        #expect(decompressed.readUInt32(at: o) == 10); o += 4
    }

    @Test("searchReply - 0 files")
    func testSearchReplyEmpty() throws {
        let msg = MessageBuilder.searchReplyMessage(
            username: "nobody",
            token: 1,
            results: []
        )
        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        let (user, uLen) = decompressed.readString(at: o)!; o += uLen
        #expect(user == "nobody")
        #expect(decompressed.readUInt32(at: o) == 1); o += 4
        #expect(decompressed.readUInt32(at: o) == 0) // 0 files
    }

    @Test("searchReply - edge values (queueLength=10, freeSlots=false)")
    func testSearchReplyEdgeValues() throws {
        let msg = MessageBuilder.searchReplyMessage(
            username: "u",
            token: UInt32.max,
            results: [("f.mp3", 0, "mp3", [])],
            hasFreeSlots: false,
            uploadSpeed: 0,
            queueLength: 10
        )
        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        let (_, uLen) = decompressed.readString(at: o)!; o += uLen
        let token = decompressed.readUInt32(at: o)!; o += 4
        #expect(token == UInt32.max)
        let fileCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(fileCount == 1)

        // Skip file entry
        o += 1 // code byte
        let (_, fnLen) = decompressed.readString(at: o)!; o += fnLen
        o += 8 // size
        let (_, extLen) = decompressed.readString(at: o)!; o += extLen
        let attrCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(attrCount == 0)

        #expect(decompressed.readBool(at: o) == false); o += 1
        #expect(decompressed.readUInt32(at: o) == 0); o += 4
        #expect(decompressed.readUInt32(at: o) == 10)
    }

    // MARK: - SharesReply

    @Test("sharesReply - 3 dirs x 5 files")
    func testSharesReply3x5() throws {
        var dirs: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])] = []
        for d in 0..<3 {
            var files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)] = []
            for f in 0..<5 {
                files.append(("track\(f).mp3", UInt64(f * 1_000_000 + 500_000), 320, UInt32(180 + f * 10)))
            }
            dirs.append(("Music\\Album\(d)", files))
        }

        let msg = MessageBuilder.sharesReplyMessage(files: dirs)
        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        let dirCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(dirCount == 3)

        for d in 0..<3 {
            let (dirName, dLen) = decompressed.readString(at: o)!; o += dLen
            #expect(dirName == "Music\\Album\(d)")
            let fCount = decompressed.readUInt32(at: o)!; o += 4
            #expect(fCount == 5)

            for f in 0..<5 {
                let code = decompressed.readUInt8(at: o)!; o += 1
                #expect(code == 1)
                let (fn, fnLen) = decompressed.readString(at: o)!; o += fnLen
                #expect(fn == "track\(f).mp3")
                let size = decompressed.readUInt64(at: o)!; o += 8
                #expect(size == UInt64(f * 1_000_000 + 500_000))
                let (ext, extLen) = decompressed.readString(at: o)!; o += extLen
                #expect(ext == "mp3")
                let attrCount = decompressed.readUInt32(at: o)!; o += 4
                #expect(attrCount == 2) // bitrate + duration
                // bitrate
                let aType0 = decompressed.readUInt32(at: o)!; o += 4
                let aVal0 = decompressed.readUInt32(at: o)!; o += 4
                #expect(aType0 == 0); #expect(aVal0 == 320)
                // duration
                let aType1 = decompressed.readUInt32(at: o)!; o += 4
                let aVal1 = decompressed.readUInt32(at: o)!; o += 4
                #expect(aType1 == 1); #expect(aVal1 == UInt32(180 + f * 10))
            }
        }
    }

    @Test("sharesReply - large (10 dirs x 20 files = 200 files)")
    func testSharesReplyLarge() throws {
        var dirs: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])] = []
        for d in 0..<10 {
            var files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)] = []
            for f in 0..<20 {
                files.append(("song\(f).flac", UInt64((d + 1) * (f + 1) * 100_000), nil, nil))
            }
            dirs.append(("Dir\(d)", files))
        }

        let msg = MessageBuilder.sharesReplyMessage(files: dirs)
        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        let dirCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(dirCount == 10)

        // Just verify structure parses without error and counts are right
        for _ in 0..<10 {
            let (_, dLen) = decompressed.readString(at: o)!; o += dLen
            let fCount = decompressed.readUInt32(at: o)!; o += 4
            #expect(fCount == 20)
            for _ in 0..<20 {
                o += 1 // code
                let (_, fnLen) = decompressed.readString(at: o)!; o += fnLen
                o += 8 // size
                let (_, extLen) = decompressed.readString(at: o)!; o += extLen
                let ac = decompressed.readUInt32(at: o)!; o += 4
                #expect(ac == 0) // no bitrate/duration
            }
        }
    }

    @Test("sharesReply - empty (0 dirs)")
    func testSharesReplyEmpty() throws {
        let msg = MessageBuilder.sharesReplyMessage(files: [])
        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        #expect(decompressed.readUInt32(at: o) == 0); o += 4 // 0 dirs
        #expect(decompressed.readUInt32(at: o) == 0); o += 4 // unknown
        #expect(decompressed.readUInt32(at: o) == 0)         // 0 private dirs
    }

    // MARK: - FolderContentsResponse

    @Test("folderContentsResponse - 12 files with attributes")
    func testFolderContentsResponse12Files() throws {
        var files: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] = []
        for i in 0..<12 {
            files.append((
                filename: "track\(i + 1).flac",
                size: UInt64(30_000_000 + i * 2_000_000),
                extension_: "flac",
                attributes: [(0, 1411), (1, UInt32(200 + i * 15))]
            ))
        }

        let msg = MessageBuilder.folderContentsResponseMessage(
            token: 54321,
            folder: "Music\\Artist\\Album",
            files: files
        )

        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        #expect(decompressed.readUInt32(at: o) == 54321); o += 4 // token
        let (folder, fLen) = decompressed.readString(at: o)!; o += fLen
        #expect(folder == "Music\\Artist\\Album")
        let folderCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(folderCount == 1)
        let (dirName, dLen) = decompressed.readString(at: o)!; o += dLen
        #expect(dirName == "Music\\Artist\\Album")
        let fileCount = decompressed.readUInt32(at: o)!; o += 4
        #expect(fileCount == 12)

        for i in 0..<12 {
            let code = decompressed.readUInt8(at: o)!; o += 1
            #expect(code == 1)
            let (fn, fnLen) = decompressed.readString(at: o)!; o += fnLen
            #expect(fn == "track\(i + 1).flac")
            let size = decompressed.readUInt64(at: o)!; o += 8
            #expect(size == UInt64(30_000_000 + i * 2_000_000))
            let (ext, extLen) = decompressed.readString(at: o)!; o += extLen
            #expect(ext == "flac")
            let attrCount = decompressed.readUInt32(at: o)!; o += 4
            #expect(attrCount == 2)
            o += 4 * 4 // skip 2 attr pairs (4 uint32s)
        }
    }

    @Test("folderContentsResponse - empty (0 files)")
    func testFolderContentsResponseEmpty() throws {
        let msg = MessageBuilder.folderContentsResponseMessage(
            token: 11111,
            folder: "Empty\\Folder",
            files: []
        )

        let compressed = extractCompressedPayload(msg)
        let decompressed = try decompressZlib(compressed)

        var o = 0
        #expect(decompressed.readUInt32(at: o) == 11111); o += 4
        let (folder, fLen) = decompressed.readString(at: o)!; o += fLen
        #expect(folder == "Empty\\Folder")
        #expect(decompressed.readUInt32(at: o) == 1); o += 4 // 1 folder entry
        let (dirName, dLen) = decompressed.readString(at: o)!; o += dLen
        #expect(dirName == "Empty\\Folder")
        #expect(decompressed.readUInt32(at: o) == 0) // 0 files
    }

    // MARK: - Error Handling

    @Test("corrupt zlib data rejection")
    func testCorruptZlibRejection() {
        // Valid zlib header but garbage compressed data
        var corrupt = Data([0x78, 0x9C]) // zlib header
        corrupt.append(Data(repeating: 0xFF, count: 50))
        corrupt.append(Data([0x00, 0x00, 0x00, 0x00])) // fake checksum

        do {
            _ = try decompressZlib(corrupt)
            Issue.record("Expected decompression to fail on corrupt data")
        } catch {
            // Expected
        }
    }

    @Test("data too short for zlib")
    func testDataTooShort() {
        let short = Data([0x78, 0x9C, 0x01])
        do {
            _ = try decompressZlib(short)
            Issue.record("Expected failure for data < 6 bytes")
        } catch TestError.tooShort {
            // Expected
        } catch {
            // Also acceptable
        }
    }
}
