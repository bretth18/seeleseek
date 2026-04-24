import Testing
import Foundation
@testable import SeeleseekCore

@Suite("Obfuscation Codec")
struct ObfuscationCodecTests {

    // MARK: - Round-trip

    @Test("Empty payload round-trips")
    func emptyRoundTrip() throws {
        let wire = ObfuscationCodec.encodeMessage(payload: Data())
        #expect(wire.count == 8) // 4 key + 4 length, no payload
        let decoded = try ObfuscationCodec.decodeMessage(from: wire)
        try #require(decoded != nil)
        #expect(decoded!.payload == Data())
        #expect(decoded!.bytesConsumed == wire.count)
    }

    @Test("Single-byte payload round-trips")
    func singleByteRoundTrip() throws {
        let payload = Data([0xAB])
        let wire = ObfuscationCodec.encodeMessage(payload: payload)
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: wire))
        #expect(decoded.payload == payload)
        #expect(decoded.bytesConsumed == wire.count)
    }

    @Test("Typical peer-init payload round-trips")
    func peerInitRoundTrip() throws {
        // PeerInit-style body: message code (1) + string + string + uint32
        var payload = Data([0x01])
        payload.appendString("testuser")
        payload.appendString("P")
        payload.appendUInt32(0x12345678)

        let wire = ObfuscationCodec.encodeMessage(payload: payload)
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: wire))
        #expect(decoded.payload == payload)
    }

    @Test("Large payload round-trips")
    func largePayloadRoundTrip() throws {
        let payload = Data((0..<10_000).map { UInt8($0 & 0xff) })
        let wire = ObfuscationCodec.encodeMessage(payload: payload)
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: wire))
        #expect(decoded.payload == payload)
    }

    @Test("Many random round-trips")
    func fuzzRoundTrip() throws {
        for _ in 0..<50 {
            let len = Int.random(in: 0...1024)
            let payload = Data((0..<len).map { _ in UInt8.random(in: 0...255) })
            let wire = ObfuscationCodec.encodeMessage(payload: payload)
            let decoded = try #require(try ObfuscationCodec.decodeMessage(from: wire))
            #expect(decoded.payload == payload)
        }
    }

    // MARK: - Known-answer vectors
    //
    // These are hand-computed from the algorithm spec and lock the wire
    // format. If they break, the cipher has drifted from the Museek+ /
    // SoulseekQt on-the-wire bytes and peers will not be able to decode us.
    //
    // Key rotates LEFT by 1 on a 32-bit value at every 4-byte block boundary,
    // starting BEFORE block 0. Byte i is XORed with key_bytes[i % 4] of the
    // current (already-rotated) key state.

    @Test("Known answer: key=01020304, payload=ABCDEFGH")
    func knownAnswerSequential() throws {
        // Key as uint32 LE: 0x04030201.
        // After first rotl-by-1: 0x08060402 -> bytes [02, 04, 06, 08]
        // Length LE = 08 00 00 00, XORed with [02, 04, 06, 08] = [0A, 04, 06, 08]
        // After second rotl-by-1: 0x100C0804 -> bytes [04, 08, 0C, 10]
        // Payload bytes 0..3 = [41, 42, 43, 44] XOR [04, 08, 0C, 10] = [45, 4A, 4F, 54]
        // After third rotl-by-1: 0x20181008 -> bytes [08, 10, 18, 20]
        // Payload bytes 4..7 = [45, 46, 47, 48] XOR [08, 10, 18, 20] = [4D, 56, 5F, 68]
        let payload = Data("ABCDEFGH".utf8)
        let wire = ObfuscationCodec.encodeMessage(payload: payload, key: [0x01, 0x02, 0x03, 0x04])
        let expected = Data([
            0x01, 0x02, 0x03, 0x04,                         // key raw
            0x0A, 0x04, 0x06, 0x08,                         // encoded length
            0x45, 0x4A, 0x4F, 0x54, 0x4D, 0x56, 0x5F, 0x68  // encoded payload
        ])
        #expect(wire == expected)
    }

    @Test("Known answer: key=FFFFFFFF exercises high-bit wrap")
    func knownAnswerAllOnes() throws {
        // rotl(0xFFFFFFFF, 1) = 0xFFFFFFFF — key stays all-ones every block.
        // Length 1 LE = 01 00 00 00 XOR FF FF FF FF = FE FF FF FF
        // Payload [00] XOR FF = FF
        let wire = ObfuscationCodec.encodeMessage(payload: Data([0x00]), key: [0xFF, 0xFF, 0xFF, 0xFF])
        let expected = Data([
            0xFF, 0xFF, 0xFF, 0xFF,
            0xFE, 0xFF, 0xFF, 0xFF,
            0xFF
        ])
        #expect(wire == expected)
    }

    @Test("Known answer: key=00000080 exercises rotation carry")
    func knownAnswerRotationCarry() throws {
        // Key uint32 LE = 0x80000000. rotl(0x80000000, 1) = 0x00000001 -> [01 00 00 00]
        // Length 4 LE = 04 00 00 00 XOR [01 00 00 00] = [05 00 00 00]
        // Second rotl: 0x00000001 -> 0x00000002 -> [02 00 00 00]
        // Payload [00 00 00 00] XOR [02 00 00 00] = [02 00 00 00]
        let wire = ObfuscationCodec.encodeMessage(payload: Data([0, 0, 0, 0]), key: [0x00, 0x00, 0x00, 0x80])
        let expected = Data([
            0x00, 0x00, 0x00, 0x80,
            0x05, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00
        ])
        #expect(wire == expected)
    }

    // MARK: - Partial / malformed buffers

    @Test("Decode returns nil when fewer than 8 bytes available")
    func decodeNeedsKeyAndLength() throws {
        for len in 0..<8 {
            let buf = Data(repeating: 0, count: len)
            let decoded = try ObfuscationCodec.decodeMessage(from: buf)
            #expect(decoded == nil, "expected nil for \(len)-byte buffer")
        }
    }

    @Test("Decode returns nil when payload bytes haven't arrived yet")
    func decodeWaitsForFullPayload() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let wire = ObfuscationCodec.encodeMessage(payload: payload)
        // Feed every partial length shorter than the full wire.
        for short in 0..<wire.count {
            let partial = wire.prefix(short)
            let decoded = try ObfuscationCodec.decodeMessage(from: Data(partial))
            #expect(decoded == nil, "expected nil for \(short)-byte prefix")
        }
        // Full buffer decodes.
        let decoded = try #require(try ObfuscationCodec.decodeMessage(from: wire))
        #expect(decoded.payload == payload)
    }

    @Test("Decode throws when advertised length exceeds max")
    func decodeRejectsOversizedLength() throws {
        // Craft a wire buffer that advertises a payload larger than the cap.
        // We pick key=[0,0,0,0] so the XOR is identity and the advertised
        // length equals the literal bytes in the length slot.
        var wire = Data([0x00, 0x00, 0x00, 0x00])
        wire.appendUInt32(UInt32(10_000_001))
        // Don't bother padding — the cap check should fire before we look at
        // the payload bytes.
        #expect(throws: ObfuscationCodec.DecodingError.self) {
            _ = try ObfuscationCodec.decodeMessage(from: wire, maxPayloadLength: 10_000_000)
        }
    }

    @Test("Decode returns leftover bytes consumed exactly, leaving trailing bytes untouched")
    func decodeConsumesExactBytes() throws {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let firstWire = ObfuscationCodec.encodeMessage(payload: payload)
        let secondWire = ObfuscationCodec.encodeMessage(payload: Data([0xDD]))
        let combined = firstWire + secondWire

        let firstDecoded = try #require(try ObfuscationCodec.decodeMessage(from: combined))
        #expect(firstDecoded.payload == payload)
        #expect(firstDecoded.bytesConsumed == firstWire.count)

        let remainder = combined.suffix(from: firstDecoded.bytesConsumed)
        let secondDecoded = try #require(try ObfuscationCodec.decodeMessage(from: Data(remainder)))
        #expect(secondDecoded.payload == Data([0xDD]))
    }

    // MARK: - Key generation

    @Test("Generated keys are 4 bytes, all nonzero")
    func generatedKeyShape() {
        for _ in 0..<200 {
            let key = ObfuscationCodec.generateKey()
            #expect(key.count == 4)
            for byte in key {
                #expect(byte != 0, "Museek+ reference generates bytes in 1...255; some peers may assume this")
            }
        }
    }

    @Test("Generated keys have entropy across calls")
    func generatedKeyVaries() {
        var seen = Set<[UInt8]>()
        for _ in 0..<50 { seen.insert(ObfuscationCodec.generateKey()) }
        #expect(seen.count > 40, "50 calls produced \(seen.count) unique keys — RNG looks broken")
    }

    // MARK: - Stream continuity

    @Test("Stream state is continuous across transform calls")
    func streamContinuity() {
        // Encoding the length and payload as one 8-byte call must match
        // encoding them as two 4-byte calls — the cipher rotates at 4-byte
        // block boundaries regardless of call chunking.
        let key: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        let combined = Data([0x04, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0xCC, 0xDD])

        var oneCall = ObfuscationCodec.Stream(key: key)
        let oneShot = oneCall.transform(combined)

        var twoCall = ObfuscationCodec.Stream(key: key)
        var twoShot = twoCall.transform(combined.prefix(4))
        twoShot.append(twoCall.transform(combined.suffix(4)))

        #expect(oneShot == twoShot)
    }
}
