import Foundation

/// Commands typed with a leading `/` in the message field. `/me` is special:
/// it is sent over the wire verbatim (Soulseek convention — clients render
/// it as an action line); everything else is handled locally.
enum SlashCommand: Equatable {
    case me
    case join(String)
    case leave
    case clear
    case unknown(String)

    /// nil when the input is not a command (doesn't start with `/`).
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch name {
        case "/me":
            return argument.isEmpty ? .unknown(name) : .me
        case "/join", "/j":
            return argument.isEmpty ? .unknown(name) : .join(argument)
        case "/leave", "/part":
            return .leave
        case "/clear":
            return .clear
        default:
            return .unknown(name)
        }
    }
}
