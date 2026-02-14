import Foundation

struct IgnoredUser: Identifiable, Codable, Hashable, Sendable {
    var id: String { username.lowercased() }
    let username: String
    let reason: String?
    let dateIgnored: Date

    init(username: String, reason: String? = nil, dateIgnored: Date = Date()) {
        self.username = username
        self.reason = reason
        self.dateIgnored = dateIgnored
    }
}
