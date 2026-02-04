import Foundation
import os

/// Service for looking up country information from IP addresses
actor GeoIPService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "GeoIPService")

    // Cache IP -> country code lookups
    private var cache: [String: String] = [:]

    // Rate limiting
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 0.5  // Max 2 requests/sec for free API

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

        // Rate limiting
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            try? await Task.sleep(for: .milliseconds(Int((minRequestInterval - elapsed) * 1000)))
        }
        lastRequestTime = Date()

        // Use ipapi.co (free HTTPS, 1000 req/day limit)
        guard let url = URL(string: "https://ipapi.co/\(ip)/country/") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("seeleseek/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)

            // Check for rate limiting
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                logger.warning("GeoIP rate limited")
                return nil
            }

            // Response is just the country code as plain text (e.g., "US")
            if let countryCode = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               countryCode.count == 2 {
                cache[ip] = countryCode
                logger.debug("GeoIP: \(ip) -> \(countryCode)")
                return countryCode
            }
        } catch {
            logger.error("GeoIP lookup failed for \(ip): \(error.localizedDescription)")
        }

        return nil
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

    /// Batch lookup for multiple IPs (with rate limiting)
    func getCountryCodes(for ips: [String]) async -> [String: String] {
        var results: [String: String] = [:]

        for ip in ips {
            if let code = await getCountryCode(for: ip) {
                results[ip] = code
            }
        }

        return results
    }
}
