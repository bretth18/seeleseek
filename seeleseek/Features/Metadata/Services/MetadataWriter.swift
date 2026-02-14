import Foundation
import os

/// Off-main-thread actor that handles all metadata writing to audio files.
/// Supports MP3 (ID3v2.4), FLAC (Vorbis Comment + PICTURE), and AIF/AIFF (IFF + ID3v2.4).
actor MetadataWriter {
    private let logger = Logger(subsystem: "com.seeleseek", category: "MetadataWriter")

    struct Metadata {
        let title: String
        let artist: String
        let album: String
        let year: String
        let trackNumber: Int?
        let genre: String
        let coverArt: Data?
    }

    enum WriterError: LocalizedError {
        case unsupportedFormat(String)
        case fileReadFailed
        case invalidID3Size
        case invalidFLACFile
        case invalidAIFFFile

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file format: .\(ext)"
            case .fileReadFailed:
                return "Could not read audio file."
            case .invalidID3Size:
                return "Existing ID3 tag appears corrupted."
            case .invalidFLACFile:
                return "Not a valid FLAC file."
            case .invalidAIFFFile:
                return "Not a valid AIFF file."
            }
        }
    }

    // MARK: - Public Entry Point

    func write(_ metadata: Metadata, to fileURL: URL) throws {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "mp3":
            try writeMP3(metadata, to: fileURL)
        case "flac":
            try writeFLAC(metadata, to: fileURL)
        case "aif", "aiff":
            try writeAIFF(metadata, to: fileURL)
        default:
            throw WriterError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
        }
    }

    // MARK: - MP3 (ID3v2.4)

    private func writeMP3(_ metadata: Metadata, to fileURL: URL) throws {
        let originalData = try Data(contentsOf: fileURL)
        guard !originalData.isEmpty else { throw WriterError.fileReadFailed }

        let withoutID3v2 = try Self.stripExistingID3v2(from: originalData)
        let audioData = Self.stripID3v1Footer(from: withoutID3v2)
        let newTag = Self.buildID3v24Tag(for: metadata)
        let finalData = newTag + audioData

        try finalData.write(to: fileURL, options: .atomic)
        logger.info("Wrote ID3 metadata to \(fileURL.lastPathComponent)")
    }

    // MARK: - FLAC (Vorbis Comment + PICTURE)

    private func writeFLAC(_ metadata: Metadata, to fileURL: URL) throws {
        let originalData = try Data(contentsOf: fileURL)
        guard originalData.count >= 4 else { throw WriterError.fileReadFailed }

        // Verify "fLaC" magic
        guard originalData[0] == 0x66, originalData[1] == 0x4C,
              originalData[2] == 0x61, originalData[3] == 0x43 else {
            throw WriterError.invalidFLACFile
        }

        // Parse existing metadata blocks
        var offset = 4
        var preservedBlocks: [(type: UInt8, data: Data)] = []
        var isLast = false

        while !isLast && offset + 4 <= originalData.count {
            let headerByte = originalData[offset]
            isLast = (headerByte & 0x80) != 0
            let blockType = headerByte & 0x7F
            let blockLength = Int(originalData[offset + 1]) << 16
                | Int(originalData[offset + 2]) << 8
                | Int(originalData[offset + 3])
            offset += 4

            guard offset + blockLength <= originalData.count else {
                throw WriterError.invalidFLACFile
            }

            let blockData = originalData[offset..<(offset + blockLength)]
            offset += blockLength

            // Preserve everything except VORBIS_COMMENT (4), PICTURE (6), and PADDING (1)
            switch blockType {
            case 4, 6, 1:
                break // Drop — we'll write new ones
            default:
                preservedBlocks.append((type: blockType, data: Data(blockData)))
            }
        }

        let audioFrames = originalData[offset...]

        // Build new Vorbis Comment block
        let vorbisCommentData = buildVorbisComment(for: metadata)

        // Build new PICTURE block (if cover art provided)
        let pictureData: Data? = metadata.coverArt.map { buildFLACPictureBlock(imageData: $0) }

        // Reassemble file
        var result = Data()
        result.append(contentsOf: [0x66, 0x4C, 0x61, 0x43]) // "fLaC"

        // Write preserved blocks (none are last)
        for block in preservedBlocks {
            result.append(block.type & 0x7F) // not last
            result.append(contentsOf: beBytes(for: block.data.count, width: 3))
            result.append(block.data)
        }

        // Write Vorbis Comment
        if let pictureData {
            // Not last — PICTURE follows
            result.append(4) // type 4, not last
            result.append(contentsOf: beBytes(for: vorbisCommentData.count, width: 3))
            result.append(vorbisCommentData)

            // PICTURE is last
            result.append(6 | 0x80) // type 6, last
            result.append(contentsOf: beBytes(for: pictureData.count, width: 3))
            result.append(pictureData)
        } else {
            // Vorbis Comment is last
            result.append(4 | 0x80) // type 4, last
            result.append(contentsOf: beBytes(for: vorbisCommentData.count, width: 3))
            result.append(vorbisCommentData)
        }

        result.append(audioFrames)

        try result.write(to: fileURL, options: .atomic)
        logger.info("Wrote FLAC metadata to \(fileURL.lastPathComponent)")
    }

    /// Build Vorbis Comment block data (without the metadata block header).
    /// Format: vendor string (LE32 len + UTF-8) + comment count (LE32) + comments (LE32 len + "KEY=value")
    private func buildVorbisComment(for metadata: Metadata) -> Data {
        let vendor = "SeeleSeek"
        let vendorBytes = vendor.utf8

        var comments: [(String, String)] = []
        func add(_ key: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { comments.append((key, trimmed)) }
        }

        add("TITLE", metadata.title)
        add("ARTIST", metadata.artist)
        add("ALBUM", metadata.album)
        add("DATE", metadata.year)
        add("GENRE", metadata.genre)
        if let track = metadata.trackNumber, track > 0 {
            add("TRACKNUMBER", String(track))
        }

        var data = Data()
        // Vendor string
        data.append(contentsOf: leBytes(for: vendorBytes.count, width: 4))
        data.append(contentsOf: vendorBytes)
        // Comment count
        data.append(contentsOf: leBytes(for: comments.count, width: 4))
        // Comments
        for (key, value) in comments {
            let entry = "\(key)=\(value)"
            let entryBytes = Array(entry.utf8)
            data.append(contentsOf: leBytes(for: entryBytes.count, width: 4))
            data.append(contentsOf: entryBytes)
        }

        return data
    }

    /// Build FLAC PICTURE block data (type 6 payload, without the metadata block header).
    /// Spec: picture type (BE32) + MIME len (BE32) + MIME + desc len (BE32) + desc
    ///       + width (BE32) + height (BE32) + depth (BE32) + colors (BE32) + data len (BE32) + data
    private func buildFLACPictureBlock(imageData: Data) -> Data {
        let mimeType: String
        if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
        } else {
            mimeType = "image/jpeg"
        }

        let mimeBytes = Array(mimeType.utf8)

        var data = Data()
        data.append(contentsOf: beBytes(for: 3, width: 4)) // picture type: front cover
        data.append(contentsOf: beBytes(for: mimeBytes.count, width: 4))
        data.append(contentsOf: mimeBytes)
        data.append(contentsOf: beBytes(for: 0, width: 4)) // description length
        // no description bytes
        data.append(contentsOf: beBytes(for: 0, width: 4)) // width (0 = unknown)
        data.append(contentsOf: beBytes(for: 0, width: 4)) // height
        data.append(contentsOf: beBytes(for: 0, width: 4)) // color depth
        data.append(contentsOf: beBytes(for: 0, width: 4)) // colors used
        data.append(contentsOf: beBytes(for: imageData.count, width: 4))
        data.append(imageData)

        return data
    }

    // MARK: - AIF/AIFF (IFF Container + ID3v2.4)

    private func writeAIFF(_ metadata: Metadata, to fileURL: URL) throws {
        let originalData = try Data(contentsOf: fileURL)
        guard originalData.count >= 12 else { throw WriterError.fileReadFailed }

        // Verify FORM header
        guard originalData[0] == 0x46, originalData[1] == 0x4F,
              originalData[2] == 0x52, originalData[3] == 0x4D else {
            throw WriterError.invalidAIFFFile
        }

        // Read form type (AIFF or AIFC) at offset 8
        let formType = Data(originalData[8..<12])
        let formTypeStr = String(data: formType, encoding: .ascii) ?? ""
        guard formTypeStr == "AIFF" || formTypeStr == "AIFC" else {
            throw WriterError.invalidAIFFFile
        }

        // Parse chunks, preserving all except "ID3 "
        var chunks: [(id: String, data: Data)] = []
        var offset = 12

        while offset + 8 <= originalData.count {
            let chunkIDData = originalData[offset..<(offset + 4)]
            let chunkID = String(data: Data(chunkIDData), encoding: .ascii) ?? "????"
            let chunkSize = Int(originalData[offset + 4]) << 24
                | Int(originalData[offset + 5]) << 16
                | Int(originalData[offset + 6]) << 8
                | Int(originalData[offset + 7])
            offset += 8

            let safeSize = min(chunkSize, originalData.count - offset)
            let chunkData = Data(originalData[offset..<(offset + safeSize)])
            offset += safeSize

            // IFF chunks are even-padded
            if safeSize % 2 != 0 && offset < originalData.count {
                offset += 1
            }

            if chunkID != "ID3 " {
                chunks.append((id: chunkID, data: chunkData))
            }
        }

        // Build new ID3 tag
        let id3Tag = Self.buildID3v24Tag(for: metadata)

        // Reassemble FORM container
        var body = Data()
        body.append(formType) // AIFF or AIFC

        for chunk in chunks {
            body.append(chunk.id.data(using: .ascii)!)
            body.append(contentsOf: beBytes(for: chunk.data.count, width: 4))
            body.append(chunk.data)
            // Even-pad
            if chunk.data.count % 2 != 0 {
                body.append(0x00)
            }
        }

        // Append ID3 chunk
        body.append("ID3 ".data(using: .ascii)!)
        body.append(contentsOf: beBytes(for: id3Tag.count, width: 4))
        body.append(id3Tag)
        if id3Tag.count % 2 != 0 {
            body.append(0x00)
        }

        // Build final file: "FORM" + BE32 size + body
        var result = Data()
        result.append("FORM".data(using: .ascii)!)
        result.append(contentsOf: beBytes(for: body.count, width: 4))
        result.append(body)

        try result.write(to: fileURL, options: .atomic)
        logger.info("Wrote AIFF ID3 metadata to \(fileURL.lastPathComponent)")
    }

    // MARK: - ID3v2.4 Tag Building (shared by MP3 and AIFF)

    nonisolated static func buildID3v24Tag(for metadata: Metadata) -> Data {
        var frames = Data()
        frames.append(textFrame(id: "TIT2", value: metadata.title))
        frames.append(textFrame(id: "TPE1", value: metadata.artist))
        frames.append(textFrame(id: "TALB", value: metadata.album))
        frames.append(textFrame(id: "TCON", value: metadata.genre))

        if let track = metadata.trackNumber, track > 0 {
            frames.append(textFrame(id: "TRCK", value: String(track)))
        }

        if !metadata.year.isEmpty {
            frames.append(textFrame(id: "TDRC", value: metadata.year))
        }

        if let art = metadata.coverArt {
            frames.append(apicFrame(imageData: art))
        }

        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(0x04) // v2.4
        header.append(0x00) // revision
        header.append(0x00) // flags
        header.append(contentsOf: synchsafeBytes(for: frames.count))

        return header + frames
    }

    nonisolated static func textFrame(id: String, value: String) -> Data {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Data() }

        var payload = Data()
        payload.append(0x03) // UTF-8 encoding
        payload.append(trimmed.data(using: .utf8) ?? Data())

        var frame = Data()
        frame.append(id.data(using: .ascii) ?? Data())
        frame.append(contentsOf: synchsafeBytes(for: payload.count))
        frame.append(contentsOf: [0x00, 0x00]) // flags
        frame.append(payload)
        return frame
    }

    nonisolated static func apicFrame(imageData: Data) -> Data {
        guard !imageData.isEmpty else { return Data() }

        var payload = Data()
        payload.append(0x03) // UTF-8 encoding

        let mimeType: String
        if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
        } else {
            mimeType = "image/jpeg"
        }

        payload.append(mimeType.data(using: .ascii) ?? Data())
        payload.append(0x00) // null terminator
        payload.append(0x03) // front cover
        payload.append(0x00) // empty description
        payload.append(imageData)

        var frame = Data()
        frame.append("APIC".data(using: .ascii)!)
        frame.append(contentsOf: synchsafeBytes(for: payload.count))
        frame.append(contentsOf: [0x00, 0x00]) // flags
        frame.append(payload)
        return frame
    }

    nonisolated static func synchsafeBytes(for value: Int) -> [UInt8] {
        let safeValue = max(0, value)
        return [
            UInt8((safeValue >> 21) & 0x7F),
            UInt8((safeValue >> 14) & 0x7F),
            UInt8((safeValue >> 7) & 0x7F),
            UInt8(safeValue & 0x7F)
        ]
    }

    nonisolated static func decodeSynchsafeInt(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Int {
        (Int(b0 & 0x7F) << 21)
            | (Int(b1 & 0x7F) << 14)
            | (Int(b2 & 0x7F) << 7)
            | Int(b3 & 0x7F)
    }

    // MARK: - ID3 Stripping (MP3)

    private static func stripExistingID3v2(from data: Data) throws -> Data {
        guard data.count >= 10 else { return data }
        guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { // "ID3"
            return data
        }

        let tagSize = decodeSynchsafeInt(data[6], data[7], data[8], data[9])
        let totalSize = 10 + tagSize
        guard totalSize <= data.count else {
            throw WriterError.invalidID3Size
        }
        return data.subdata(in: totalSize..<data.count)
    }

    private static func stripID3v1Footer(from data: Data) -> Data {
        guard data.count >= 128 else { return data }
        let footerStart = data.count - 128
        if data[footerStart] == 0x54, data[footerStart + 1] == 0x41, data[footerStart + 2] == 0x47 { // "TAG"
            return data.subdata(in: 0..<footerStart)
        }
        return data
    }

    // MARK: - Byte Helpers

    /// Big-endian bytes for an integer, truncated to `width` bytes.
    private func beBytes(for value: Int, width: Int) -> [UInt8] {
        (0..<width).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    /// Little-endian bytes for an integer, truncated to `width` bytes.
    private func leBytes(for value: Int, width: Int) -> [UInt8] {
        (0..<width).map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }
}
