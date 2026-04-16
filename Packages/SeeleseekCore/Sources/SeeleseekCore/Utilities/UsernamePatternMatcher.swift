import Foundation

/// Case-insensitive glob matcher for Soulseek usernames.
///
/// Supported syntax (deliberately minimal):
/// - `*` — matches any (possibly empty) run of characters
/// - everything else is literal
///
/// A pattern containing no `*` is treated as an exact match. This keeps the
/// settings UI "type a pattern" usable without surprises — users who want
/// "starts with" write `slsk_*`, not just `slsk_`.
public enum UsernamePatternMatcher {
    /// True if `username` matches any non-empty pattern in `patterns`.
    /// Empty/whitespace-only patterns are ignored so a blank row in the UI
    /// can't accidentally match everyone.
    public static func matches(_ username: String, anyOf patterns: [String]) -> Bool {
        let normalized = username.lowercased()
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if matches(normalized, pattern: trimmed.lowercased()) {
                return true
            }
        }
        return false
    }

    /// Single-pattern match against an already-lowercased username.
    static func matches(_ username: String, pattern: String) -> Bool {
        let segments = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)

        // No wildcard → literal equality.
        if segments.count == 1 {
            return username == pattern
        }

        // Leading segment must anchor at the start (unless it's empty, meaning "*…").
        var cursor = username.startIndex
        if let first = segments.first, !first.isEmpty {
            guard username.hasPrefix(first) else { return false }
            cursor = username.index(cursor, offsetBy: first.count)
        }

        // Trailing segment must anchor at the end (unless it's empty, meaning "…*").
        if let last = segments.last, !last.isEmpty {
            guard username.hasSuffix(last) else { return false }
            // Nothing else to match if only two segments.
            if segments.count == 2 { return true }
        }

        // Middle segments: consume in order anywhere between cursor and end.
        let middle = segments.dropFirst().dropLast()
        let tailAnchor = segments.last ?? ""
        let endIndex = tailAnchor.isEmpty ? username.endIndex : username.index(username.endIndex, offsetBy: -tailAnchor.count)

        for segment in middle where !segment.isEmpty {
            guard let range = username.range(of: segment, range: cursor..<endIndex) else {
                return false
            }
            cursor = range.upperBound
        }
        return true
    }
}
