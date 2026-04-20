import Foundation
import os

/// Caches user information like country codes, resolved from IP addresses
@Observable
@MainActor
public final class UserInfoCache {
    private let logger = Logger(subsystem: "com.seeleseek", category: "UserInfoCache")

    // Username -> country code
    private(set) var countries: [String: String] = [:]

    // Username -> IP address (for lookups)
    private var ipAddresses: [String: String] = [:]

    // Pending lookups to avoid duplicate requests
    private var pendingLookups: Set<String> = []

    // GeoIP service
    private let geoIP = GeoIPService()

    /// Fires whenever a country code is newly resolved (or seeded) for a
    /// username. Lets app-layer state (e.g. SocialState) persist the
    /// value alongside the buddy record so it survives a restart instead
    /// of having to re-resolve the IP on every launch.
    public var onCountryResolved: ((String, String) -> Void)?

    /// Register an IP address for a user (will trigger async country lookup)
    public func registerIP(_ ip: String, for username: String) {
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
                    self.onCountryResolved?(username, countryCode)
                }
            } else {
                _ = await MainActor.run {
                    self.pendingLookups.remove(username)
                }
            }
        }
    }

    /// Pre-populate the cache with a country code we already know (e.g.
    /// a buddy's persisted `countryCode` loaded from the DB). No GeoIP
    /// lookup runs and `onCountryResolved` does NOT fire — we already
    /// know the value, no need to round-trip through the persistence
    /// callback.
    public func seedCountry(_ code: String, for username: String) {
        guard !username.isEmpty, !code.isEmpty else { return }
        if countries[username] == nil {
            countries[username] = code
        }
    }

    /// Get country code for a user (nil if not yet resolved)
    public func countryCode(for username: String) -> String? {
        countries[username]
    }

    /// Get flag emoji for a user (empty if not resolved)
    public func flag(for username: String) -> String {
        if let code = countries[username] {
            return GeoIPService.flag(for: code)
        }
        return ""
    }

    /// Get IP address for a user (if known)
    public func ipAddress(for username: String) -> String? {
        ipAddresses[username]
    }

    /// Clear all cached data
    public func clear() {
        countries.removeAll()
        ipAddresses.removeAll()
        pendingLookups.removeAll()
    }
}
