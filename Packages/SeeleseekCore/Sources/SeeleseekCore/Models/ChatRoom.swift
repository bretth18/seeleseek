import Foundation

/// A user joining or leaving a room. Kept separate from the message
/// transcript so the UI can surface these in a compact activity pane.
public struct RoomEvent: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case joined
        case left
    }

    public let id: UUID
    public let kind: Kind
    public let username: String
    public let timestamp: Date

    public init(id: UUID = UUID(), kind: Kind, username: String, timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.username = username
        self.timestamp = timestamp
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    public var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }
}

public struct ChatRoom: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var users: [String]
    public var messages: [ChatMessage]
    public var events: [RoomEvent]
    public var unreadCount: Int
    public var isJoined: Bool
    public var isPrivate: Bool
    public var owner: String?
    public var operators: Set<String>
    public var members: [String]
    public var tickers: [String: String]

    public init(
        name: String,
        users: [String] = [],
        messages: [ChatMessage] = [],
        events: [RoomEvent] = [],
        unreadCount: Int = 0,
        isJoined: Bool = false,
        isPrivate: Bool = false,
        owner: String? = nil,
        operators: Set<String> = [],
        members: [String] = [],
        tickers: [String: String] = [:]
    ) {
        self.id = name
        self.name = name
        self.users = users
        self.messages = messages
        self.events = events
        self.unreadCount = unreadCount
        self.isJoined = isJoined
        self.isPrivate = isPrivate
        self.owner = owner
        self.operators = operators
        self.members = members
        self.tickers = tickers
    }

    public var userCount: Int {
        users.count
    }
}
