import Foundation

struct BlockedUser: Identifiable, Codable, Hashable, Sendable {
    var id: String { username }
    let username: String
    let reason: String?
    let dateBlocked: Date

    init(username: String, reason: String? = nil, dateBlocked: Date = Date()) {
        self.username = username
        self.reason = reason
        self.dateBlocked = dateBlocked
    }
}
