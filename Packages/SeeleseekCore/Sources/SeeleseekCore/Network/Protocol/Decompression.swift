import Foundation
import Compression

/// Errors thrown by zlib decompression
public enum DecompressionError: Error {
    case dataTooShort
    case decompressionFailed
    case suspiciousCompressionRatio
    case decompressedSizeExceeded
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
            // Standard zlib: strip 2-byte header and 4-byte Adler-32 footer
            let deflateData = Data(data.dropFirst(2).dropLast(4))
            return try decompressRawDeflate(deflateData)
        } else {
            // Not zlib format — try raw DEFLATE
            return try decompressRawDeflate(data)
        }
    }

    /// Decompress raw DEFLATE data (RFC 1951) using Apple's Compression framework.
    nonisolated static func decompressRawDeflate(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { sourceBuffer -> Data in
            let sourceSize = data.count
            guard let baseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw DecompressionError.decompressionFailed
            }

            var destinationSize = min(max(sourceSize * 20, 65536), maxDecompressedSize)
            var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)

            var decodedSize = compression_decode_buffer(
                &destinationBuffer, destinationSize,
                baseAddress, sourceSize,
                nil, COMPRESSION_ZLIB
            )

            // If output buffer was too small, retry with larger buffer (capped)
            if decodedSize == 0 || decodedSize == destinationSize {
                destinationSize = min(sourceSize * 100, maxDecompressedSize)
                guard destinationSize <= maxDecompressedSize else {
                    throw DecompressionError.decompressedSizeExceeded
                }
                destinationBuffer = [UInt8](repeating: 0, count: destinationSize)
                decodedSize = compression_decode_buffer(
                    &destinationBuffer, destinationSize,
                    baseAddress, sourceSize,
                    nil, COMPRESSION_ZLIB
                )
            }

            guard decodedSize > 0 else {
                throw DecompressionError.decompressionFailed
            }

            // Security: check compression ratio
            let compressionRatio = decodedSize / max(sourceSize, 1)
            if compressionRatio > maxCompressionRatio {
                throw DecompressionError.suspiciousCompressionRatio
            }

            guard decodedSize <= maxDecompressedSize else {
                throw DecompressionError.decompressedSizeExceeded
            }

            return Data(destinationBuffer.prefix(decodedSize))
        }
    }
}
