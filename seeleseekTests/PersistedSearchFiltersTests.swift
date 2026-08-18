import Foundation
import Testing
@testable import seeleseek

@Suite("Persisted search filters")
struct PersistedSearchFiltersTests {

    @Test("Round-trips with every field populated")
    func roundTripFull() throws {
        let filters = PersistedSearchFilters(
            minBitrate: 320,
            minSampleRate: 44_100,
            minBitDepth: 16,
            minSize: 1_048_576,
            maxSize: 5_000_000_000,
            extensions: ["flac", "mp3"],
            freeSlotOnly: true
        )
        let data = try JSONEncoder().encode(filters)
        let decoded = try JSONDecoder().decode(PersistedSearchFilters.self, from: data)
        #expect(decoded == filters)
    }

    @Test("Round-trips empty (the Clear case)")
    func roundTripEmpty() throws {
        let data = try JSONEncoder().encode(PersistedSearchFilters.empty)
        let decoded = try JSONDecoder().decode(PersistedSearchFilters.self, from: data)
        #expect(decoded == .empty)
        #expect(decoded.minBitrate == nil)
        #expect(decoded.extensions.isEmpty)
        #expect(!decoded.freeSlotOnly)
    }

    @Test("Optional fields tolerate absent keys in stored blobs")
    func decodeMissingOptionalKeys() throws {
        let json = Data(#"{"extensions":[],"freeSlotOnly":false}"#.utf8)
        let decoded = try JSONDecoder().decode(PersistedSearchFilters.self, from: json)
        #expect(decoded == .empty)
    }

    @Test("Missing non-optional key fails to decode")
    func decodeMissingRequiredKeyFails() {
        let json = Data(#"{"extensions":[]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PersistedSearchFilters.self, from: json)
        }
    }
}
