import Foundation
import os

/// Caches user information like country codes, resolved from IP addresses
@Observable
@MainActor
final class UserInfoCache {
    private let logger = Logger(subsystem: "com.seeleseek", category: "UserInfoCache")

    // Username -> country code
    private(set) var countries: [String: String] = [:]

    // Username -> IP address (for lookups)
    private var ipAddresses: [String: String] = [:]

    // Pending lookups to avoid duplicate requests
    private var pendingLookups: Set<String> = []

    // GeoIP service
    private let geoIP = GeoIPService()

    /// Register an IP address for a user (will trigger async country lookup)
    func registerIP(_ ip: String, for username: String) {
        guard !ip.isEmpty, !username.isEmpty else { return }

        ipAddresses[username] = ip

        // Skip if we already have country for this user
        guard countries[username] == nil else { return }

        // Skip if lookup already pending
        guard !pendingLookups.contains(username) else { return }

        pendingLookups.insert(username)

        // Async lookup
        Task {
            if let countryCode = await geoIP.getCountryCode(for: ip) {
                await MainActor.run {
                    self.countries[username] = countryCode
                    self.pendingLookups.remove(username)
                    self.logger.debug("Resolved country for \(username): \(countryCode)")
                }
            } else {
                _ = await MainActor.run {
                    self.pendingLookups.remove(username)
                }
            }
        }
    }

    /// Get country code for a user (nil if not yet resolved)
    func countryCode(for username: String) -> String? {
        countries[username]
    }

    /// Get flag emoji for a user (empty if not resolved)
    func flag(for username: String) -> String {
        if let code = countries[username] {
            return GeoIPService.flag(for: code)
        }
        return ""
    }

    /// Get IP address for a user (if known)
    func ipAddress(for username: String) -> String? {
        ipAddresses[username]
    }

    /// Clear all cached data
    func clear() {
        countries.removeAll()
        ipAddresses.removeAll()
        pendingLookups.removeAll()
    }
}
