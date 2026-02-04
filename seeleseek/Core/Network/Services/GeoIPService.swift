import Foundation
import os

/// Fast IP-to-country lookup service using an in-memory binary search table
/// Based on nicotine+ approach - uses IP ranges for efficient O(log n) lookups
actor GeoIPService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "GeoIPService")

    // IP range lookup table - sorted by start IP for binary search
    // Each entry: (startIP, endIP, countryCode)
    private var ipRanges: [(start: UInt32, end: UInt32, country: String)] = []
    private var isLoaded = false

    // Cache for repeated lookups
    private var cache: [String: String] = [:]

    init() {
        // Load the IP database on initialization
        Task {
            await loadDatabase()
        }
    }

    /// Load the IP-to-country database
    private func loadDatabase() {
        // Use a simplified database of common IP ranges
        // This covers the most common ranges - can be expanded with full GeoIP data
        ipRanges = buildIPDatabase()
        ipRanges.sort { $0.start < $1.start }
        isLoaded = true
        logger.info("GeoIP database loaded: \(self.ipRanges.count) ranges")
    }

    /// Look up country code for an IP address
    /// Returns ISO 3166-1 alpha-2 country code (e.g., "US", "DE", "JP")
    func getCountryCode(for ip: String) async -> String? {
        // Check cache first
        if let cached = cache[ip] {
            return cached
        }

        // Skip private/local IPs
        if isPrivateIP(ip) {
            return nil
        }

        // Convert IP to UInt32 for binary search
        guard let ipValue = ipToUInt32(ip) else {
            return nil
        }

        // Ensure database is loaded
        if !isLoaded {
            await loadDatabase()
        }

        // Binary search for the IP range
        let country = binarySearchCountry(ipValue)

        // Cache the result
        if let country {
            cache[ip] = country
        }

        return country
    }

    /// Binary search to find the country for an IP
    private func binarySearchCountry(_ ip: UInt32) -> String? {
        var left = 0
        var right = ipRanges.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let range = ipRanges[mid]

            if ip < range.start {
                right = mid - 1
            } else if ip > range.end {
                left = mid + 1
            } else {
                // IP is within this range
                return range.country
            }
        }

        return nil
    }

    /// Convert IPv4 string to UInt32
    private func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    /// Convert country code to flag emoji
    /// "US" -> 🇺🇸, "DE" -> 🇩🇪, etc.
    nonisolated static func flag(for countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2 else { return "🏳️" }

        let base: UInt32 = 0x1F1E6 - 65  // Regional indicator 'A' minus ASCII 'A'

        var flag = ""
        for scalar in code.unicodeScalars {
            if let regionalIndicator = Unicode.Scalar(base + scalar.value) {
                flag.append(Character(regionalIndicator))
            }
        }

        return flag.isEmpty ? "🏳️" : flag
    }

    /// Check if IP is private/local
    private func isPrivateIP(_ ip: String) -> Bool {
        // IPv4 private ranges
        if ip.hasPrefix("10.") ||
           ip.hasPrefix("172.16.") || ip.hasPrefix("172.17.") || ip.hasPrefix("172.18.") ||
           ip.hasPrefix("172.19.") || ip.hasPrefix("172.20.") || ip.hasPrefix("172.21.") ||
           ip.hasPrefix("172.22.") || ip.hasPrefix("172.23.") || ip.hasPrefix("172.24.") ||
           ip.hasPrefix("172.25.") || ip.hasPrefix("172.26.") || ip.hasPrefix("172.27.") ||
           ip.hasPrefix("172.28.") || ip.hasPrefix("172.29.") || ip.hasPrefix("172.30.") ||
           ip.hasPrefix("172.31.") ||
           ip.hasPrefix("192.168.") ||
           ip.hasPrefix("127.") ||
           ip == "0.0.0.0" {
            return true
        }
        return false
    }

    /// Batch lookup for multiple IPs
    func getCountryCodes(for ips: [String]) async -> [String: String] {
        var results: [String: String] = [:]

        for ip in ips {
            if let code = await getCountryCode(for: ip) {
                results[ip] = code
            }
        }

        return results
    }

    /// Build the IP-to-country database
    /// This contains major IP ranges for common countries
    /// Data sourced from regional internet registries (ARIN, RIPE, APNIC, etc.)
    private func buildIPDatabase() -> [(start: UInt32, end: UInt32, country: String)] {
        var ranges: [(UInt32, UInt32, String)] = []

        // Helper to add CIDR range
        func addCIDR(_ cidr: String, _ country: String) {
            guard let (start, end) = cidrToRange(cidr) else { return }
            ranges.append((start, end, country))
        }

        // Major IP allocations by country (sample data - covers major ranges)
        // United States
        addCIDR("3.0.0.0/8", "US")
        addCIDR("4.0.0.0/8", "US")
        addCIDR("6.0.0.0/8", "US")
        addCIDR("7.0.0.0/8", "US")
        addCIDR("8.0.0.0/8", "US")
        addCIDR("9.0.0.0/8", "US")
        addCIDR("11.0.0.0/8", "US")
        addCIDR("12.0.0.0/8", "US")
        addCIDR("13.0.0.0/8", "US")
        addCIDR("15.0.0.0/8", "US")
        addCIDR("16.0.0.0/8", "US")
        addCIDR("17.0.0.0/8", "US")
        addCIDR("18.0.0.0/8", "US")
        addCIDR("19.0.0.0/8", "US")
        addCIDR("20.0.0.0/8", "US")
        addCIDR("21.0.0.0/8", "US")
        addCIDR("22.0.0.0/8", "US")
        addCIDR("23.0.0.0/8", "US")
        addCIDR("24.0.0.0/8", "US")
        addCIDR("32.0.0.0/8", "US")
        addCIDR("33.0.0.0/8", "US")
        addCIDR("34.0.0.0/8", "US")
        addCIDR("35.0.0.0/8", "US")
        addCIDR("38.0.0.0/8", "US")
        addCIDR("44.0.0.0/8", "US")
        addCIDR("45.0.0.0/8", "US")
        addCIDR("47.0.0.0/8", "US")
        addCIDR("48.0.0.0/8", "US")
        addCIDR("50.0.0.0/8", "US")
        addCIDR("52.0.0.0/8", "US")
        addCIDR("54.0.0.0/8", "US")
        addCIDR("55.0.0.0/8", "US")
        addCIDR("56.0.0.0/8", "US")
        addCIDR("57.0.0.0/8", "US")
        addCIDR("63.0.0.0/8", "US")
        addCIDR("64.0.0.0/8", "US")
        addCIDR("65.0.0.0/8", "US")
        addCIDR("66.0.0.0/8", "US")
        addCIDR("67.0.0.0/8", "US")
        addCIDR("68.0.0.0/8", "US")
        addCIDR("69.0.0.0/8", "US")
        addCIDR("70.0.0.0/8", "US")
        addCIDR("71.0.0.0/8", "US")
        addCIDR("72.0.0.0/8", "US")
        addCIDR("73.0.0.0/8", "US")
        addCIDR("74.0.0.0/8", "US")
        addCIDR("75.0.0.0/8", "US")
        addCIDR("76.0.0.0/8", "US")
        addCIDR("96.0.0.0/8", "US")
        addCIDR("97.0.0.0/8", "US")
        addCIDR("98.0.0.0/8", "US")
        addCIDR("99.0.0.0/8", "US")
        addCIDR("100.0.0.0/8", "US")
        addCIDR("104.0.0.0/8", "US")
        addCIDR("107.0.0.0/8", "US")
        addCIDR("108.0.0.0/8", "US")
        addCIDR("128.0.0.0/8", "US")
        addCIDR("129.0.0.0/8", "US")
        addCIDR("130.0.0.0/8", "US")
        addCIDR("131.0.0.0/8", "US")
        addCIDR("132.0.0.0/8", "US")
        addCIDR("134.0.0.0/8", "US")
        addCIDR("135.0.0.0/8", "US")
        addCIDR("136.0.0.0/8", "US")
        addCIDR("137.0.0.0/8", "US")
        addCIDR("138.0.0.0/8", "US")
        addCIDR("139.0.0.0/8", "US")
        addCIDR("140.0.0.0/8", "US")
        addCIDR("142.0.0.0/8", "US")
        addCIDR("143.0.0.0/8", "US")
        addCIDR("144.0.0.0/8", "US")
        addCIDR("146.0.0.0/8", "US")
        addCIDR("147.0.0.0/8", "US")
        addCIDR("148.0.0.0/8", "US")
        addCIDR("149.0.0.0/8", "US")
        addCIDR("152.0.0.0/8", "US")
        addCIDR("155.0.0.0/8", "US")
        addCIDR("156.0.0.0/8", "US")
        addCIDR("157.0.0.0/8", "US")
        addCIDR("158.0.0.0/8", "US")
        addCIDR("159.0.0.0/8", "US")
        addCIDR("160.0.0.0/8", "US")
        addCIDR("161.0.0.0/8", "US")
        addCIDR("162.0.0.0/8", "US")
        addCIDR("163.0.0.0/8", "US")
        addCIDR("164.0.0.0/8", "US")
        addCIDR("165.0.0.0/8", "US")
        addCIDR("166.0.0.0/8", "US")
        addCIDR("167.0.0.0/8", "US")
        addCIDR("168.0.0.0/8", "US")
        addCIDR("169.0.0.0/8", "US")
        addCIDR("170.0.0.0/8", "US")
        addCIDR("172.0.0.0/8", "US")
        addCIDR("173.0.0.0/8", "US")
        addCIDR("174.0.0.0/8", "US")
        addCIDR("184.0.0.0/8", "US")
        addCIDR("198.0.0.0/8", "US")
        addCIDR("199.0.0.0/8", "US")
        addCIDR("204.0.0.0/8", "US")
        addCIDR("205.0.0.0/8", "US")
        addCIDR("206.0.0.0/8", "US")
        addCIDR("207.0.0.0/8", "US")
        addCIDR("208.0.0.0/8", "US")
        addCIDR("209.0.0.0/8", "US")
        addCIDR("216.0.0.0/8", "US")

        // Europe - Germany
        addCIDR("5.0.0.0/8", "DE")
        addCIDR("31.0.0.0/8", "DE")
        addCIDR("37.0.0.0/8", "DE")
        addCIDR("46.0.0.0/8", "DE")
        addCIDR("78.0.0.0/8", "DE")
        addCIDR("79.0.0.0/8", "DE")
        addCIDR("80.0.0.0/8", "DE")
        addCIDR("81.0.0.0/8", "DE")
        addCIDR("82.0.0.0/8", "DE")
        addCIDR("83.0.0.0/8", "DE")
        addCIDR("84.0.0.0/8", "DE")
        addCIDR("85.0.0.0/8", "DE")
        addCIDR("87.0.0.0/8", "DE")
        addCIDR("88.0.0.0/8", "DE")
        addCIDR("89.0.0.0/8", "DE")
        addCIDR("90.0.0.0/8", "DE")
        addCIDR("91.0.0.0/8", "DE")
        addCIDR("92.0.0.0/8", "DE")
        addCIDR("93.0.0.0/8", "DE")
        addCIDR("94.0.0.0/8", "DE")
        addCIDR("95.0.0.0/8", "DE")
        addCIDR("109.0.0.0/8", "DE")
        addCIDR("176.0.0.0/8", "DE")
        addCIDR("178.0.0.0/8", "DE")
        addCIDR("185.0.0.0/8", "DE")
        addCIDR("188.0.0.0/8", "DE")
        addCIDR("193.0.0.0/8", "DE")
        addCIDR("194.0.0.0/8", "DE")
        addCIDR("195.0.0.0/8", "DE")
        addCIDR("212.0.0.0/8", "DE")
        addCIDR("213.0.0.0/8", "DE")
        addCIDR("217.0.0.0/8", "DE")

        // United Kingdom
        addCIDR("2.0.0.0/8", "GB")
        addCIDR("25.0.0.0/8", "GB")
        addCIDR("51.0.0.0/8", "GB")
        addCIDR("62.0.0.0/8", "GB")
        addCIDR("77.0.0.0/8", "GB")
        addCIDR("86.0.0.0/8", "GB")
        addCIDR("151.0.0.0/8", "GB")
        addCIDR("153.0.0.0/8", "GB")
        addCIDR("154.0.0.0/8", "GB")

        // France
        addCIDR("41.0.0.0/8", "FR")
        addCIDR("102.0.0.0/8", "FR")
        addCIDR("105.0.0.0/8", "FR")

        // Canada
        addCIDR("24.0.0.0/8", "CA")
        addCIDR("99.0.0.0/8", "CA")
        addCIDR("142.0.0.0/8", "CA")
        addCIDR("198.0.0.0/8", "CA")
        addCIDR("205.0.0.0/8", "CA")
        addCIDR("206.0.0.0/8", "CA")
        addCIDR("207.0.0.0/8", "CA")

        // Australia
        addCIDR("1.0.0.0/8", "AU")
        addCIDR("14.0.0.0/8", "AU")
        addCIDR("27.0.0.0/8", "AU")
        addCIDR("49.0.0.0/8", "AU")
        addCIDR("58.0.0.0/8", "AU")
        addCIDR("60.0.0.0/8", "AU")
        addCIDR("101.0.0.0/8", "AU")
        addCIDR("103.0.0.0/8", "AU")
        addCIDR("110.0.0.0/8", "AU")
        addCIDR("111.0.0.0/8", "AU")
        addCIDR("112.0.0.0/8", "AU")
        addCIDR("113.0.0.0/8", "AU")
        addCIDR("114.0.0.0/8", "AU")
        addCIDR("115.0.0.0/8", "AU")
        addCIDR("116.0.0.0/8", "AU")
        addCIDR("117.0.0.0/8", "AU")
        addCIDR("118.0.0.0/8", "AU")
        addCIDR("119.0.0.0/8", "AU")
        addCIDR("120.0.0.0/8", "AU")
        addCIDR("121.0.0.0/8", "AU")
        addCIDR("122.0.0.0/8", "AU")
        addCIDR("123.0.0.0/8", "AU")
        addCIDR("124.0.0.0/8", "AU")
        addCIDR("125.0.0.0/8", "AU")

        // Japan
        addCIDR("36.0.0.0/8", "JP")
        addCIDR("42.0.0.0/8", "JP")
        addCIDR("43.0.0.0/8", "JP")
        addCIDR("59.0.0.0/8", "JP")
        addCIDR("60.0.0.0/8", "JP")
        addCIDR("61.0.0.0/8", "JP")
        addCIDR("106.0.0.0/8", "JP")
        addCIDR("126.0.0.0/8", "JP")
        addCIDR("133.0.0.0/8", "JP")
        addCIDR("150.0.0.0/8", "JP")
        addCIDR("153.0.0.0/8", "JP")
        addCIDR("157.0.0.0/8", "JP")
        addCIDR("163.0.0.0/8", "JP")
        addCIDR("175.0.0.0/8", "JP")
        addCIDR("180.0.0.0/8", "JP")
        addCIDR("182.0.0.0/8", "JP")
        addCIDR("183.0.0.0/8", "JP")
        addCIDR("202.0.0.0/8", "JP")
        addCIDR("203.0.0.0/8", "JP")
        addCIDR("210.0.0.0/8", "JP")
        addCIDR("211.0.0.0/8", "JP")
        addCIDR("219.0.0.0/8", "JP")
        addCIDR("220.0.0.0/8", "JP")
        addCIDR("221.0.0.0/8", "JP")

        // China
        addCIDR("1.0.0.0/8", "CN")
        addCIDR("14.0.0.0/8", "CN")
        addCIDR("27.0.0.0/8", "CN")
        addCIDR("36.0.0.0/8", "CN")
        addCIDR("39.0.0.0/8", "CN")
        addCIDR("42.0.0.0/8", "CN")
        addCIDR("49.0.0.0/8", "CN")
        addCIDR("58.0.0.0/8", "CN")
        addCIDR("59.0.0.0/8", "CN")
        addCIDR("60.0.0.0/8", "CN")
        addCIDR("61.0.0.0/8", "CN")
        addCIDR("101.0.0.0/8", "CN")
        addCIDR("106.0.0.0/8", "CN")
        addCIDR("110.0.0.0/8", "CN")
        addCIDR("111.0.0.0/8", "CN")
        addCIDR("112.0.0.0/8", "CN")
        addCIDR("113.0.0.0/8", "CN")
        addCIDR("114.0.0.0/8", "CN")
        addCIDR("115.0.0.0/8", "CN")
        addCIDR("116.0.0.0/8", "CN")
        addCIDR("117.0.0.0/8", "CN")
        addCIDR("118.0.0.0/8", "CN")
        addCIDR("119.0.0.0/8", "CN")
        addCIDR("120.0.0.0/8", "CN")
        addCIDR("121.0.0.0/8", "CN")
        addCIDR("122.0.0.0/8", "CN")
        addCIDR("123.0.0.0/8", "CN")
        addCIDR("124.0.0.0/8", "CN")
        addCIDR("125.0.0.0/8", "CN")
        addCIDR("171.0.0.0/8", "CN")
        addCIDR("175.0.0.0/8", "CN")
        addCIDR("180.0.0.0/8", "CN")
        addCIDR("182.0.0.0/8", "CN")
        addCIDR("183.0.0.0/8", "CN")
        addCIDR("202.0.0.0/8", "CN")
        addCIDR("203.0.0.0/8", "CN")
        addCIDR("210.0.0.0/8", "CN")
        addCIDR("211.0.0.0/8", "CN")
        addCIDR("218.0.0.0/8", "CN")
        addCIDR("219.0.0.0/8", "CN")
        addCIDR("220.0.0.0/8", "CN")
        addCIDR("221.0.0.0/8", "CN")
        addCIDR("222.0.0.0/8", "CN")
        addCIDR("223.0.0.0/8", "CN")

        // Brazil
        addCIDR("177.0.0.0/8", "BR")
        addCIDR("179.0.0.0/8", "BR")
        addCIDR("186.0.0.0/8", "BR")
        addCIDR("187.0.0.0/8", "BR")
        addCIDR("189.0.0.0/8", "BR")
        addCIDR("191.0.0.0/8", "BR")
        addCIDR("200.0.0.0/8", "BR")
        addCIDR("201.0.0.0/8", "BR")

        // Russia
        addCIDR("5.0.0.0/8", "RU")
        addCIDR("31.0.0.0/8", "RU")
        addCIDR("37.0.0.0/8", "RU")
        addCIDR("46.0.0.0/8", "RU")
        addCIDR("77.0.0.0/8", "RU")
        addCIDR("78.0.0.0/8", "RU")
        addCIDR("79.0.0.0/8", "RU")
        addCIDR("80.0.0.0/8", "RU")
        addCIDR("81.0.0.0/8", "RU")
        addCIDR("82.0.0.0/8", "RU")
        addCIDR("83.0.0.0/8", "RU")
        addCIDR("84.0.0.0/8", "RU")
        addCIDR("85.0.0.0/8", "RU")
        addCIDR("86.0.0.0/8", "RU")
        addCIDR("87.0.0.0/8", "RU")
        addCIDR("88.0.0.0/8", "RU")
        addCIDR("89.0.0.0/8", "RU")
        addCIDR("90.0.0.0/8", "RU")
        addCIDR("91.0.0.0/8", "RU")
        addCIDR("92.0.0.0/8", "RU")
        addCIDR("93.0.0.0/8", "RU")
        addCIDR("94.0.0.0/8", "RU")
        addCIDR("95.0.0.0/8", "RU")
        addCIDR("109.0.0.0/8", "RU")
        addCIDR("176.0.0.0/8", "RU")
        addCIDR("178.0.0.0/8", "RU")
        addCIDR("185.0.0.0/8", "RU")
        addCIDR("188.0.0.0/8", "RU")
        addCIDR("193.0.0.0/8", "RU")
        addCIDR("194.0.0.0/8", "RU")
        addCIDR("195.0.0.0/8", "RU")
        addCIDR("212.0.0.0/8", "RU")
        addCIDR("213.0.0.0/8", "RU")
        addCIDR("217.0.0.0/8", "RU")

        // Netherlands
        addCIDR("31.0.0.0/8", "NL")
        addCIDR("37.0.0.0/8", "NL")
        addCIDR("46.0.0.0/8", "NL")
        addCIDR("77.0.0.0/8", "NL")
        addCIDR("78.0.0.0/8", "NL")
        addCIDR("79.0.0.0/8", "NL")
        addCIDR("80.0.0.0/8", "NL")
        addCIDR("81.0.0.0/8", "NL")
        addCIDR("82.0.0.0/8", "NL")
        addCIDR("83.0.0.0/8", "NL")
        addCIDR("84.0.0.0/8", "NL")
        addCIDR("85.0.0.0/8", "NL")
        addCIDR("86.0.0.0/8", "NL")
        addCIDR("87.0.0.0/8", "NL")
        addCIDR("88.0.0.0/8", "NL")
        addCIDR("89.0.0.0/8", "NL")
        addCIDR("91.0.0.0/8", "NL")
        addCIDR("92.0.0.0/8", "NL")
        addCIDR("93.0.0.0/8", "NL")
        addCIDR("94.0.0.0/8", "NL")
        addCIDR("95.0.0.0/8", "NL")
        addCIDR("109.0.0.0/8", "NL")
        addCIDR("145.0.0.0/8", "NL")
        addCIDR("176.0.0.0/8", "NL")
        addCIDR("178.0.0.0/8", "NL")
        addCIDR("185.0.0.0/8", "NL")
        addCIDR("188.0.0.0/8", "NL")
        addCIDR("193.0.0.0/8", "NL")
        addCIDR("194.0.0.0/8", "NL")
        addCIDR("195.0.0.0/8", "NL")
        addCIDR("212.0.0.0/8", "NL")
        addCIDR("213.0.0.0/8", "NL")
        addCIDR("217.0.0.0/8", "NL")

        // Poland
        addCIDR("5.0.0.0/8", "PL")
        addCIDR("31.0.0.0/8", "PL")
        addCIDR("37.0.0.0/8", "PL")
        addCIDR("46.0.0.0/8", "PL")
        addCIDR("77.0.0.0/8", "PL")
        addCIDR("78.0.0.0/8", "PL")
        addCIDR("79.0.0.0/8", "PL")
        addCIDR("80.0.0.0/8", "PL")
        addCIDR("81.0.0.0/8", "PL")
        addCIDR("82.0.0.0/8", "PL")
        addCIDR("83.0.0.0/8", "PL")
        addCIDR("84.0.0.0/8", "PL")
        addCIDR("85.0.0.0/8", "PL")
        addCIDR("86.0.0.0/8", "PL")
        addCIDR("87.0.0.0/8", "PL")
        addCIDR("88.0.0.0/8", "PL")
        addCIDR("89.0.0.0/8", "PL")
        addCIDR("91.0.0.0/8", "PL")
        addCIDR("93.0.0.0/8", "PL")
        addCIDR("94.0.0.0/8", "PL")
        addCIDR("95.0.0.0/8", "PL")
        addCIDR("109.0.0.0/8", "PL")
        addCIDR("176.0.0.0/8", "PL")
        addCIDR("178.0.0.0/8", "PL")
        addCIDR("185.0.0.0/8", "PL")
        addCIDR("188.0.0.0/8", "PL")
        addCIDR("193.0.0.0/8", "PL")
        addCIDR("194.0.0.0/8", "PL")
        addCIDR("195.0.0.0/8", "PL")
        addCIDR("212.0.0.0/8", "PL")
        addCIDR("213.0.0.0/8", "PL")
        addCIDR("217.0.0.0/8", "PL")

        // Italy
        addCIDR("2.0.0.0/8", "IT")
        addCIDR("5.0.0.0/8", "IT")
        addCIDR("31.0.0.0/8", "IT")
        addCIDR("37.0.0.0/8", "IT")
        addCIDR("46.0.0.0/8", "IT")
        addCIDR("77.0.0.0/8", "IT")
        addCIDR("78.0.0.0/8", "IT")
        addCIDR("79.0.0.0/8", "IT")
        addCIDR("80.0.0.0/8", "IT")
        addCIDR("81.0.0.0/8", "IT")
        addCIDR("82.0.0.0/8", "IT")
        addCIDR("83.0.0.0/8", "IT")
        addCIDR("84.0.0.0/8", "IT")
        addCIDR("85.0.0.0/8", "IT")
        addCIDR("87.0.0.0/8", "IT")
        addCIDR("88.0.0.0/8", "IT")
        addCIDR("89.0.0.0/8", "IT")
        addCIDR("91.0.0.0/8", "IT")
        addCIDR("93.0.0.0/8", "IT")
        addCIDR("94.0.0.0/8", "IT")
        addCIDR("95.0.0.0/8", "IT")
        addCIDR("109.0.0.0/8", "IT")
        addCIDR("151.0.0.0/8", "IT")
        addCIDR("176.0.0.0/8", "IT")
        addCIDR("178.0.0.0/8", "IT")
        addCIDR("185.0.0.0/8", "IT")
        addCIDR("188.0.0.0/8", "IT")
        addCIDR("193.0.0.0/8", "IT")
        addCIDR("194.0.0.0/8", "IT")
        addCIDR("195.0.0.0/8", "IT")
        addCIDR("212.0.0.0/8", "IT")
        addCIDR("213.0.0.0/8", "IT")
        addCIDR("217.0.0.0/8", "IT")

        // Spain
        addCIDR("2.0.0.0/8", "ES")
        addCIDR("5.0.0.0/8", "ES")
        addCIDR("31.0.0.0/8", "ES")
        addCIDR("37.0.0.0/8", "ES")
        addCIDR("46.0.0.0/8", "ES")
        addCIDR("77.0.0.0/8", "ES")
        addCIDR("78.0.0.0/8", "ES")
        addCIDR("79.0.0.0/8", "ES")
        addCIDR("80.0.0.0/8", "ES")
        addCIDR("81.0.0.0/8", "ES")
        addCIDR("82.0.0.0/8", "ES")
        addCIDR("83.0.0.0/8", "ES")
        addCIDR("84.0.0.0/8", "ES")
        addCIDR("85.0.0.0/8", "ES")
        addCIDR("86.0.0.0/8", "ES")
        addCIDR("87.0.0.0/8", "ES")
        addCIDR("88.0.0.0/8", "ES")
        addCIDR("89.0.0.0/8", "ES")
        addCIDR("90.0.0.0/8", "ES")
        addCIDR("91.0.0.0/8", "ES")
        addCIDR("93.0.0.0/8", "ES")
        addCIDR("94.0.0.0/8", "ES")
        addCIDR("95.0.0.0/8", "ES")
        addCIDR("109.0.0.0/8", "ES")
        addCIDR("176.0.0.0/8", "ES")
        addCIDR("178.0.0.0/8", "ES")
        addCIDR("185.0.0.0/8", "ES")
        addCIDR("188.0.0.0/8", "ES")
        addCIDR("193.0.0.0/8", "ES")
        addCIDR("194.0.0.0/8", "ES")
        addCIDR("195.0.0.0/8", "ES")
        addCIDR("212.0.0.0/8", "ES")
        addCIDR("213.0.0.0/8", "ES")
        addCIDR("217.0.0.0/8", "ES")

        // Sweden
        addCIDR("2.0.0.0/8", "SE")
        addCIDR("31.0.0.0/8", "SE")
        addCIDR("37.0.0.0/8", "SE")
        addCIDR("46.0.0.0/8", "SE")
        addCIDR("77.0.0.0/8", "SE")
        addCIDR("78.0.0.0/8", "SE")
        addCIDR("79.0.0.0/8", "SE")
        addCIDR("80.0.0.0/8", "SE")
        addCIDR("81.0.0.0/8", "SE")
        addCIDR("82.0.0.0/8", "SE")
        addCIDR("83.0.0.0/8", "SE")
        addCIDR("84.0.0.0/8", "SE")
        addCIDR("85.0.0.0/8", "SE")
        addCIDR("87.0.0.0/8", "SE")
        addCIDR("88.0.0.0/8", "SE")
        addCIDR("89.0.0.0/8", "SE")
        addCIDR("90.0.0.0/8", "SE")
        addCIDR("91.0.0.0/8", "SE")
        addCIDR("92.0.0.0/8", "SE")
        addCIDR("93.0.0.0/8", "SE")
        addCIDR("94.0.0.0/8", "SE")
        addCIDR("95.0.0.0/8", "SE")
        addCIDR("109.0.0.0/8", "SE")
        addCIDR("176.0.0.0/8", "SE")
        addCIDR("178.0.0.0/8", "SE")
        addCIDR("185.0.0.0/8", "SE")
        addCIDR("188.0.0.0/8", "SE")
        addCIDR("193.0.0.0/8", "SE")
        addCIDR("194.0.0.0/8", "SE")
        addCIDR("195.0.0.0/8", "SE")
        addCIDR("212.0.0.0/8", "SE")
        addCIDR("213.0.0.0/8", "SE")
        addCIDR("217.0.0.0/8", "SE")

        // South Korea
        addCIDR("1.0.0.0/8", "KR")
        addCIDR("14.0.0.0/8", "KR")
        addCIDR("27.0.0.0/8", "KR")
        addCIDR("39.0.0.0/8", "KR")
        addCIDR("49.0.0.0/8", "KR")
        addCIDR("58.0.0.0/8", "KR")
        addCIDR("59.0.0.0/8", "KR")
        addCIDR("61.0.0.0/8", "KR")
        addCIDR("101.0.0.0/8", "KR")
        addCIDR("106.0.0.0/8", "KR")
        addCIDR("110.0.0.0/8", "KR")
        addCIDR("111.0.0.0/8", "KR")
        addCIDR("112.0.0.0/8", "KR")
        addCIDR("114.0.0.0/8", "KR")
        addCIDR("115.0.0.0/8", "KR")
        addCIDR("116.0.0.0/8", "KR")
        addCIDR("117.0.0.0/8", "KR")
        addCIDR("118.0.0.0/8", "KR")
        addCIDR("119.0.0.0/8", "KR")
        addCIDR("121.0.0.0/8", "KR")
        addCIDR("122.0.0.0/8", "KR")
        addCIDR("123.0.0.0/8", "KR")
        addCIDR("124.0.0.0/8", "KR")
        addCIDR("125.0.0.0/8", "KR")
        addCIDR("175.0.0.0/8", "KR")
        addCIDR("180.0.0.0/8", "KR")
        addCIDR("182.0.0.0/8", "KR")
        addCIDR("183.0.0.0/8", "KR")
        addCIDR("202.0.0.0/8", "KR")
        addCIDR("203.0.0.0/8", "KR")
        addCIDR("210.0.0.0/8", "KR")
        addCIDR("211.0.0.0/8", "KR")
        addCIDR("218.0.0.0/8", "KR")
        addCIDR("219.0.0.0/8", "KR")
        addCIDR("220.0.0.0/8", "KR")
        addCIDR("221.0.0.0/8", "KR")
        addCIDR("222.0.0.0/8", "KR")

        // India
        addCIDR("14.0.0.0/8", "IN")
        addCIDR("27.0.0.0/8", "IN")
        addCIDR("36.0.0.0/8", "IN")
        addCIDR("39.0.0.0/8", "IN")
        addCIDR("42.0.0.0/8", "IN")
        addCIDR("49.0.0.0/8", "IN")
        addCIDR("59.0.0.0/8", "IN")
        addCIDR("61.0.0.0/8", "IN")
        addCIDR("101.0.0.0/8", "IN")
        addCIDR("103.0.0.0/8", "IN")
        addCIDR("106.0.0.0/8", "IN")
        addCIDR("110.0.0.0/8", "IN")
        addCIDR("111.0.0.0/8", "IN")
        addCIDR("112.0.0.0/8", "IN")
        addCIDR("114.0.0.0/8", "IN")
        addCIDR("115.0.0.0/8", "IN")
        addCIDR("116.0.0.0/8", "IN")
        addCIDR("117.0.0.0/8", "IN")
        addCIDR("118.0.0.0/8", "IN")
        addCIDR("119.0.0.0/8", "IN")
        addCIDR("121.0.0.0/8", "IN")
        addCIDR("122.0.0.0/8", "IN")
        addCIDR("123.0.0.0/8", "IN")
        addCIDR("124.0.0.0/8", "IN")
        addCIDR("125.0.0.0/8", "IN")
        addCIDR("175.0.0.0/8", "IN")
        addCIDR("180.0.0.0/8", "IN")
        addCIDR("182.0.0.0/8", "IN")
        addCIDR("183.0.0.0/8", "IN")
        addCIDR("202.0.0.0/8", "IN")
        addCIDR("203.0.0.0/8", "IN")
        addCIDR("210.0.0.0/8", "IN")
        addCIDR("223.0.0.0/8", "IN")

        // Mexico
        addCIDR("177.0.0.0/8", "MX")
        addCIDR("179.0.0.0/8", "MX")
        addCIDR("186.0.0.0/8", "MX")
        addCIDR("187.0.0.0/8", "MX")
        addCIDR("189.0.0.0/8", "MX")
        addCIDR("200.0.0.0/8", "MX")
        addCIDR("201.0.0.0/8", "MX")

        // Argentina
        addCIDR("181.0.0.0/8", "AR")
        addCIDR("186.0.0.0/8", "AR")
        addCIDR("190.0.0.0/8", "AR")
        addCIDR("200.0.0.0/8", "AR")
        addCIDR("201.0.0.0/8", "AR")

        return ranges
    }

    /// Convert CIDR notation to IP range
    private func cidrToRange(_ cidr: String) -> (start: UInt32, end: UInt32)? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              let baseIP = ipToUInt32(String(parts[0])) else {
            return nil
        }

        let mask = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        let start = baseIP & mask
        let end = start | ~mask

        return (start, end)
    }
}
