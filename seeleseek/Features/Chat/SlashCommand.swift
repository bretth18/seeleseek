import Foundation

/// Commands that start with `/` in the message field. The client sends
/// `/me` unchanged (Soulseek convention; peers show it as an action
/// line). The client handles all other commands locally.
enum SlashCommand: Equatable {
    case me
    case join(String)
    case leave
    case clear
    case unknown(String)

    /// Returns nil if the input does not start with `/`.
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
