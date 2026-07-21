import Foundation

/// Tab-completion of usernames in the message field. Completes the last
/// token against room users. Repeated Tab selects the next match.
enum UsernameCompletion {
    struct Context: Equatable {
        /// Text before the completed token. Completion does not change it.
        let base: String
        /// The stem the user typed.
        let stem: String
        let matches: [String]
        var index: Int

        var completedText: String { base + matches[index] }
    }

    /// Returns the completion context, or nil if there is no match.
    /// Pass the previous context back in. It is used again only if the
    /// text equals its completion result. If not, a new match starts
    /// from the current text.
    static func complete(
        text: String,
        candidates: [String],
        previous: Context?
    ) -> Context? {
        if var context = previous, context.completedText == text {
            context.index = (context.index + 1) % context.matches.count
            return context
        }

        let tokenStart = text.lastIndex(where: { $0.isWhitespace })
            .map { text.index(after: $0) } ?? text.startIndex
        let stem = String(text[tokenStart...])
        guard !stem.isEmpty else { return nil }

        let matches = candidates
            .filter { $0.lowercased().hasPrefix(stem.lowercased()) }
            .sorted { $0.lowercased() < $1.lowercased() }
        guard !matches.isEmpty else { return nil }

        return Context(
            base: String(text[..<tokenStart]),
            stem: stem,
            matches: matches,
            index: 0
        )
    }
}
