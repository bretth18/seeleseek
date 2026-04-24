import Foundation

// Soulseek peer-protocol "ROTATED" obfuscation — a trivial XOR stream cipher
// used for DPI evasion, not for privacy. Anyone with the client source can
// decode it. See project_obfuscated_protocol.md for the algorithm rationale.
//
// Wire format per message: `key[4] || enc(len_le32[4]) || enc(payload[len])`.
// The 4 key bytes are sent in the clear; the length prefix is inside the
// cipher. A fresh 4-byte key is generated per message.
//
// The cipher itself: the key is a 4-byte register that rotates left by 1
// (== right by 31) at each 4-byte block boundary, starting at block 0. Byte
// `i` of the encoded stream is `plain[i] ^ key[i % 4]`, where `key` has been
// rotated `(i / 4) + 1` times since reset.
/// Obfuscation type codes that appear on the server wire (SetWaitPort,
/// GetPeerAddress reply, ConnectToPeer). Defined in the Soulseek server
/// protocol — `none` = 0, `rotated` = 1.
public enum ObfuscationType: UInt32, Sendable {
    case none = 0
    case rotated = 1
}

public enum ObfuscationCodec {
    static let keyLength = 4

    /// Stateful cipher stream. Instantiate with a 4-byte key and call
    /// `transform` for each contiguous chunk of bytes — the output is the
    /// plaintext/ciphertext (XOR is symmetric). Because the key state is
    /// continuous across chunks, you can feed the 4-byte length and the
    /// payload as two separate `transform` calls, matching the Museek+
    /// reference which encodes them in two steps with shared key state.
    public struct Stream {
        private var key: UInt32
        private var byteIndex: Int = 0

        public init(key: [UInt8]) {
            precondition(key.count == ObfuscationCodec.keyLength, "obfuscation key must be 4 bytes")
            self.key = UInt32(key[0])
                | (UInt32(key[1]) << 8)
                | (UInt32(key[2]) << 16)
                | (UInt32(key[3]) << 24)
        }

        public mutating func transform(_ bytes: Data) -> Data {
            var out = Data(count: bytes.count)
            out.withUnsafeMutableBytes { outBuf in
                bytes.withUnsafeBytes { inBuf in
                    let outPtr = outBuf.bindMemory(to: UInt8.self)
                    let inPtr = inBuf.bindMemory(to: UInt8.self)
                    for i in 0..<bytes.count {
                        if byteIndex % ObfuscationCodec.keyLength == 0 {
                            // rotr(key, 31) == rotl(key, 1) on uint32.
                            // Written as rotl-1 explicitly so we don't depend
                            // on the shift-count UB that makes the Museek+
                            // original work on x86 but not ARM.
                            key = (key &>> 31) | (key &<< 1)
                        }
                        let keyByte = UInt8((key >> (8 * UInt32(byteIndex % ObfuscationCodec.keyLength))) & 0xff)
                        outPtr[i] = inPtr[i] ^ keyByte
                        byteIndex += 1
                    }
                }
            }
            return out
        }
    }

    /// Generate a fresh 4-byte key. Bytes are in `1...255` (never 0) to match
    /// the Museek+ reference behavior — some peers may assume this.
    public static func generateKey() -> [UInt8] {
        var key = [UInt8](repeating: 0, count: keyLength)
        for i in 0..<keyLength {
            key[i] = UInt8.random(in: 1...255)
        }
        return key
    }

    /// Encode a peer-message payload (message code + body, NOT including the
    /// outer length prefix) into the full obfuscated wire bytes:
    /// `key || enc(len_le32) || enc(payload)`.
    public static func encodeMessage(payload: Data, key: [UInt8]? = nil) -> Data {
        let k = key ?? generateKey()
        var stream = Stream(key: k)

        var lenBytes = Data()
        lenBytes.appendUInt32(UInt32(payload.count))

        var wire = Data()
        wire.reserveCapacity(keyLength + 4 + payload.count)
        wire.append(contentsOf: k)
        wire.append(stream.transform(lenBytes))
        wire.append(stream.transform(payload))
        return wire
    }

    /// Try to decode one obfuscated message from the front of `buffer`.
    ///
    /// Returns the decoded payload bytes (message code + body, without the
    /// length prefix or key) and the number of bytes consumed from `buffer`.
    /// Returns nil if the buffer doesn't yet hold a complete message.
    ///
    /// Throws if the advertised length exceeds `maxPayloadLength` (framing
    /// sanity guard — prevents a hostile or desynced peer from making us
    /// allocate arbitrary memory while we wait for bytes that never arrive).
    public static func decodeMessage(
        from buffer: Data,
        maxPayloadLength: Int = 16 * 1024 * 1024
    ) throws -> (payload: Data, bytesConsumed: Int)? {
        guard buffer.count >= keyLength + 4 else { return nil }

        let keyBytes = Array(buffer.prefix(keyLength))
        var stream = Stream(key: keyBytes)

        let encodedLen = buffer.subdata(in: keyLength..<(keyLength + 4))
        let lenBytes = stream.transform(encodedLen)
        let payloadLen = lenBytes.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }

        if payloadLen < 0 || payloadLen > maxPayloadLength {
            throw DecodingError.payloadTooLarge(advertised: payloadLen, max: maxPayloadLength)
        }

        let totalNeeded = keyLength + 4 + payloadLen
        guard buffer.count >= totalNeeded else { return nil }

        let encodedPayload = buffer.subdata(in: (keyLength + 4)..<totalNeeded)
        let payload = stream.transform(encodedPayload)
        return (payload, totalNeeded)
    }

    public enum DecodingError: Error, Equatable {
        case payloadTooLarge(advertised: Int, max: Int)
    }
}
