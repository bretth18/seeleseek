import Foundation
import os

/// IP-to-country lookup backed by a bundled MaxMind GeoLite2-Country MMDB.
///
/// The database is loaded lazily on first use and cached for the lifetime of
/// the actor. Lookups are O(log n) bit-walk through the MMDB tree. Results
/// are memoized per-IP to avoid re-walking for repeat queries.
///
/// If the `.mmdb` isn't bundled (e.g. dev setup without a MaxMind license),
/// all lookups return `nil` — callers degrade gracefully, they do not fail.
public actor GeoIPService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "GeoIPService")

    private var reader: MMDBReader?
    private var didAttemptLoad = false
    private var cache: [String: String] = [:]

    public init() {}

    /// ISO 3166-1 alpha-2 country code for an IPv4 or IPv6 address, or `nil`
    /// if the DB is missing / the address is private / no match.
    public func getCountryCode(for ip: String) async -> String? {
        if let cached = cache[ip] { return cached }
        if Self.isPrivateAddress(ip) { return nil }

        await ensureLoaded()
        guard let reader else { return nil }

        do {
            if let code = try reader.lookupCountryCode(for: ip) {
                cache[ip] = code
                return code
            }
        } catch {
            logger.debug("GeoIP lookup failed for \(ip, privacy: .private): \(error.localizedDescription)")
        }
        return nil
    }

    /// Batch version. Returns a dictionary keyed by IP for addresses that
    /// resolved; missing IPs are simply absent.
    public func getCountryCodes(for ips: [String]) async -> [String: String] {
        var results: [String: String] = [:]
        for ip in ips {
            if let code = await getCountryCode(for: ip) {
                results[ip] = code
            }
        }
        return results
    }

    // MARK: - Loading

    private func ensureLoaded() async {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true

        guard let url = Self.bundledDatabaseURL() else {
            logger.info("GeoLite2-Country.mmdb not bundled; GeoIP lookups disabled")
            return
        }

        do {
            let reader = try MMDBReader(contentsOf: url)
            self.reader = reader
            logger.info("""
                GeoIP database loaded: \(reader.metadata.databaseType) \
                (\(reader.metadata.nodeCount) nodes, \
                v\(reader.metadata.binaryFormatMajorVersion).\(reader.metadata.binaryFormatMinorVersion))
                """)
        } catch {
            logger.error("Failed to load GeoIP database: \(error.localizedDescription)")
        }
    }

    /// The app bundle must contain `GeoLite2-Country.mmdb` for lookups to
    /// resolve. See `README.md` ("Setting up GeoIP") for how to obtain it —
    /// MaxMind's EULA prevents us from committing the file ourselves.
    private static func bundledDatabaseURL() -> URL? {
        Bundle.main.url(forResource: "GeoLite2-Country", withExtension: "mmdb")
    }

    // MARK: - Flag rendering (unchanged API for callers)

    /// Converts an ISO 3166-1 alpha-2 country code to a flag emoji.
    /// `"US"` → 🇺🇸. Returns the white flag 🏳️ for bogus input.
    public nonisolated static func flag(for countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2 else { return "🏳️" }

        let base: UInt32 = 0x1F1E6 - 65  // Regional Indicator 'A' minus ASCII 'A'
        var flag = ""
        for scalar in code.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return "🏳️" }
            if let indicator = Unicode.Scalar(base + scalar.value) {
                flag.append(Character(indicator))
            }
        }
        return flag.isEmpty ? "🏳️" : flag
    }

    // MARK: - Private address filtering

    /// Cheap filter that avoids walking the MMDB tree for addresses we know
    /// aren't in it. Not a complete classifier — just the ranges we actually
    /// see from peers that aren't publicly routable.
    private static func isPrivateAddress(_ ip: String) -> Bool {
        if ip.isEmpty { return true }
        // IPv4
        if ip.hasPrefix("10.")
            || ip.hasPrefix("127.")
            || ip.hasPrefix("192.168.")
            || ip == "0.0.0.0" {
            return true
        }
        if ip.hasPrefix("172.") {
            // 172.16.0.0 – 172.31.255.255
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        // IPv4 link-local
        if ip.hasPrefix("169.254.") { return true }
        // IPv6 loopback, link-local, unique-local
        if ip == "::1" || ip == "::" { return true }
        if ip.hasPrefix("fe80:") || ip.hasPrefix("fc") || ip.hasPrefix("fd") {
            return true
        }
        return false
    }
}
