import Foundation
import Compression

/// Errors thrown by zlib decompression
public enum DecompressionError: Error {
    case dataTooShort
    case decompressionFailed
    case suspiciousCompressionRatio
    case decompressedSizeExceeded
    case presetDictionaryUnsupported
    case checksumMismatch
}

/// Standalone zlib/deflate decompression utility.
/// Mirrors the logic in PeerConnection but is testable in isolation.
public enum ZlibDecompression {
    /// Maximum decompressed output size (50 MB)
    nonisolated static let maxDecompressedSize = 50 * 1024 * 1024
    /// Maximum allowed compression ratio before flagging as suspicious
    nonisolated static let maxCompressionRatio = 1000

    /// Decompress zlib-wrapped data (RFC 1950: 2-byte header + DEFLATE + 4-byte Adler-32).
    /// Falls back to raw DEFLATE if the header doesn't indicate zlib.
    nonisolated static func decompress(_ data: Data) throws -> Data {
        guard data.count > 6 else {
            throw DecompressionError.dataTooShort
        }

        let cmf = data[data.startIndex]
        let compressionMethod = cmf & 0x0F

        if compressionMethod == 8 {
            // FDICT (FLG bit 5) means a 4-byte DICTID follows the header;
            // we don't support preset dictionaries, and feeding the DICTID
            // to the inflater as compressed data fails confusingly.
            let flg = data[data.index(after: data.startIndex)]
            guard flg & 0x20 == 0 else {
                throw DecompressionError.presetDictionaryUnsupported
            }
            // Standard zlib: strip 2-byte header and 4-byte Adler-32 footer
            let deflateData = Data(data.dropFirst(2).dropLast(4))
            let decompressed = try decompressRawDeflate(deflateData)
            // Apple's buffer API can't signal a truncated DEFLATE stream —
            // the Adler-32 trailer is the only integrity signal we have.
            let expectedChecksum = data.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard adler32(decompressed) == expectedChecksum else {
                throw DecompressionError.checksumMismatch
            }
            return decompressed
        } else {
            // Not zlib format — try raw DEFLATE
            return try decompressRawDeflate(data)
        }
    }

    /// RFC 1950 Adler-32, with the standard deferred-modulo chunking so the
    /// hot loop is pure adds (5552 is the largest n with no UInt32 overflow).
    nonisolated static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        var index = data.startIndex
        while index < data.endIndex {
            let chunkEnd = data.index(index, offsetBy: 5552, limitedBy: data.endIndex) ?? data.endIndex
            for byte in data[index..<chunkEnd] {
                a &+= UInt32(byte)
                b &+= a
            }
            a %= 65521
            b %= 65521
            index = chunkEnd
        }
        return (b << 16) | a
    }

    /// Decompress raw DEFLATE data (RFC 1951) using Apple's Compression framework.
    nonisolated static func decompressRawDeflate(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { sourceBuffer -> Data in
            let sourceSize = data.count
            guard let baseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw DecompressionError.decompressionFailed
            }

            // compression_decode_buffer can't distinguish "buffer too small"
            // from success — it fills the buffer and returns destinationSize.
            // Grow and retry until the output no longer fills the buffer;
            // a result that still fills a max-size buffer is truncation, not
            // success, so it must throw rather than return partial data.
            var destinationSize = min(max(sourceSize * 20, 65536), maxDecompressedSize)
            while true {
                var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)
                let decodedSize = compression_decode_buffer(
                    &destinationBuffer, destinationSize,
                    baseAddress, sourceSize,
                    nil, COMPRESSION_ZLIB
                )

                // 0 means error (corrupt/truncated input), NOT buffer-too-
                // small — retrying with a bigger buffer just re-decodes the
                // same hostile bytes at 4x the cost, up to 6 futile passes.
                if decodedSize == 0 {
                    throw DecompressionError.decompressionFailed
                }

                if decodedSize == destinationSize {
                    guard destinationSize < maxDecompressedSize else {
                        throw DecompressionError.decompressedSizeExceeded
                    }
                    destinationSize = min(destinationSize * 4, maxDecompressedSize)
                    continue
                }

                // Security: check compression ratio
                let compressionRatio = decodedSize / max(sourceSize, 1)
                if compressionRatio > maxCompressionRatio {
                    throw DecompressionError.suspiciousCompressionRatio
                }

                return Data(destinationBuffer.prefix(decodedSize))
            }
        }
    }
}
