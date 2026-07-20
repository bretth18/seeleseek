import Foundation

/// Tab-completion of usernames in the message field: completes the last
/// token against room users, cycling through matches on repeated Tab.
enum UsernameCompletion {
    struct Context: Equatable {
        /// Text preceding the completed token, unchanged by completion.
        let base: String
        /// The stem originally typed, kept so cycling re-matches consistently.
        let stem: String
        let matches: [String]
        var index: Int

        var completedText: String { base + matches[index] }
    }

    /// Returns the completed text and cycling context, or nil when nothing
    /// matches. Pass the previous context back in; it is reused only when
    /// the text still equals its completion result (i.e. the user pressed
    /// Tab again without editing), otherwise a fresh match is computed.
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
