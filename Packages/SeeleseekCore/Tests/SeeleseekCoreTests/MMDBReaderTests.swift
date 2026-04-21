import Foundation
import Testing
@testable import SeeleseekCore

/// Tests against MaxMind's public `GeoIP2-Country-Test.mmdb` fixture, which
/// ships in `Fixtures/`. The fixture is Apache-2.0 licensed and contains
/// ~345 synthetic records (mostly IPv6, two IPv4 CIDRs). Any assertion that
/// hardcodes an IP must cross-reference `source-data/GeoIP2-Country-Test.json`
/// from the MaxMind-DB repo — changing the fixture can silently break tests.
@Suite("MMDBReader")
struct MMDBReaderTests {

    private static func loadFixture() throws -> MMDBReader {
        guard let url = Bundle.module.url(forResource: "GeoIP2-Country-Test", withExtension: "mmdb") else {
            Issue.record("Fixture not found in test bundle")
            throw MMDBReader.Error.metadataNotFound
        }
        return try MMDBReader(contentsOf: url)
    }

    // MARK: - Metadata

    @Test("Metadata parses expected top-level fields")
    func metadata() throws {
        let reader = try Self.loadFixture()
        let meta = reader.metadata
        #expect(meta.binaryFormatMajorVersion == 2)
        #expect(meta.ipVersion == 6)
        #expect(meta.recordSize == 28 || meta.recordSize == 24 || meta.recordSize == 32)
        #expect(meta.nodeCount > 0)
        #expect(meta.databaseType.contains("Country"))
        #expect(meta.languages.contains("en"))
    }

    // MARK: - IPv4 lookups

    @Test("IPv4 inside a known CIDR resolves to the expected country")
    func ipv4Lookup() throws {
        let reader = try Self.loadFixture()
        // 214.78.120.0/22 → US per source JSON.
        #expect(try reader.lookupCountryCode(for: "214.78.120.1") == "US")
        #expect(try reader.lookupCountryCode(for: "214.78.121.255") == "US")
    }

    @Test("IPv4 outside all known ranges returns nil")
    func ipv4Miss() throws {
        let reader = try Self.loadFixture()
        #expect(try reader.lookupCountryCode(for: "1.1.1.1") == nil)
        #expect(try reader.lookupCountryCode(for: "8.8.8.8") == nil)
    }

    // MARK: - IPv6 lookups

    @Test("IPv6 inside a known CIDR resolves to the expected country")
    func ipv6Lookup() throws {
        let reader = try Self.loadFixture()
        // 2001:218::/32 → JP
        #expect(try reader.lookupCountryCode(for: "2001:218::1") == "JP")
        // 2001:220::1/128 → KR (exact-match singleton)
        #expect(try reader.lookupCountryCode(for: "2001:220::1") == "KR")
        // 2001:220::4/126 includes ::4, ::5, ::6, ::7 → KR
        #expect(try reader.lookupCountryCode(for: "2001:220::5") == "KR")
    }

    @Test("IPv6 outside all known ranges returns nil")
    func ipv6Miss() throws {
        let reader = try Self.loadFixture()
        #expect(try reader.lookupCountryCode(for: "::1") == nil)
        #expect(try reader.lookupCountryCode(for: "2606:4700:4700::1111") == nil)
    }

    // MARK: - Invalid input

    @Test("Malformed address throws invalidAddress")
    func invalidAddress() throws {
        let reader = try Self.loadFixture()
        #expect(throws: MMDBReader.Error.invalidAddress("not-an-ip")) {
            _ = try reader.lookup(address: "not-an-ip")
        }
        #expect(throws: MMDBReader.Error.invalidAddress("999.999.999.999")) {
            _ = try reader.lookup(address: "999.999.999.999")
        }
    }

    // MARK: - Raw value shape

    @Test("Lookup returns a map with expected country keys")
    func rawValueShape() throws {
        let reader = try Self.loadFixture()
        let value = try reader.lookup(address: "214.78.120.1")
        guard case .map(let top) = value else {
            Issue.record("expected top-level map, got \(String(describing: value))")
            return
        }
        guard case .map(let country) = top["country"] else {
            Issue.record("missing country map")
            return
        }
        #expect(country["iso_code"] == .string("US"))
        // country.names.en is typically populated in the test fixture.
        if case .map(let names) = country["names"], case .string(let enName) = names["en"] {
            #expect(enName.contains("United States"))
        }
    }

    // MARK: - Metadata corruption detection

    @Test("Data with no MaxMind marker fails cleanly")
    func missingMarkerFailsCleanly() throws {
        let garbage = Data(repeating: 0x00, count: 4096)
        #expect(throws: MMDBReader.Error.metadataNotFound) {
            _ = try MMDBReader(data: garbage)
        }
    }
}

/// Tests for the flag-rendering helper on `GeoIPService`. This is the part of
/// the old API that survived the MMDB migration unchanged; making sure it
/// still renders correctly so existing call sites don't regress.
@Suite("GeoIPService flag rendering")
struct GeoIPServiceFlagTests {

    @Test("Two-letter uppercase code produces the expected emoji")
    func basicFlags() {
        #expect(GeoIPService.flag(for: "US") == "🇺🇸")
        #expect(GeoIPService.flag(for: "DE") == "🇩🇪")
        #expect(GeoIPService.flag(for: "JP") == "🇯🇵")
    }

    @Test("Lowercase is normalized to uppercase")
    func lowercaseNormalized() {
        #expect(GeoIPService.flag(for: "us") == "🇺🇸")
    }

    @Test("Invalid length returns the white-flag sentinel")
    func invalidLength() {
        #expect(GeoIPService.flag(for: "") == "🏳️")
        #expect(GeoIPService.flag(for: "USA") == "🏳️")
        #expect(GeoIPService.flag(for: "X") == "🏳️")
    }

    @Test("Non-letter characters produce the white flag rather than garbage")
    func nonLetterInput() {
        #expect(GeoIPService.flag(for: "12") == "🏳️")
        #expect(GeoIPService.flag(for: "!!") == "🏳️")
    }
}
