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

    // MARK: - Compiled form

    /// Precompiled pattern. Build once when the user edits the list, then reuse
    /// for every username check — the hot path avoids per-check trim/lowercase/split.
    public struct Compiled: Sendable, Hashable {
        /// Non-nil when the pattern contains no `*`; matched by exact equality.
        let literal: String?
        /// Non-empty when the pattern contains `*`; matched segment-by-segment.
        let segments: [String]

        public init(_ raw: String) {
            let trimmed = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if trimmed.isEmpty {
                literal = nil
                segments = []
            } else if trimmed.contains("*") {
                literal = nil
                segments = trimmed
                    .split(separator: "*", omittingEmptySubsequences: false)
                    .map(String.init)
            } else {
                literal = trimmed
                segments = []
            }
        }

        /// An effectively-empty pattern (whitespace-only in the raw form) that
        /// should never match — callers can filter these out of the active set.
        public var isEmpty: Bool { literal == nil && segments.isEmpty }
    }

    /// Compile an array of raw patterns, dropping whitespace-only entries.
    public static func compile(_ patterns: [String]) -> [Compiled] {
        patterns.map(Compiled.init).filter { !$0.isEmpty }
    }

    // MARK: - Matching

    /// True if `username` matches any non-empty pattern in `patterns`.
    /// Empty/whitespace-only patterns are ignored so a blank row in the UI
    /// can't accidentally match everyone.
    public static func matches(_ username: String, anyOf patterns: [String]) -> Bool {
        matches(username, anyOfCompiled: compile(patterns))
    }

    /// Fast path against a precompiled pattern set. The hot callers (peer
    /// permission check, upload denial) should use this overload.
    public static func matches(_ username: String, anyOfCompiled patterns: [Compiled]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let normalized = username.lowercased()
        for pattern in patterns where matches(normalized, compiled: pattern) {
            return true
        }
        return false
    }

    // MARK: - Single-pattern match (lowercased inputs)

    private static func matches(_ username: String, compiled pattern: Compiled) -> Bool {
        if let literal = pattern.literal {
            return username == literal
        }
        return matchesSegments(username, segments: pattern.segments)
    }

    private static func matchesSegments(_ username: String, segments: [String]) -> Bool {
        guard segments.count > 1 else { return false }

        var cursor = username.startIndex
        if let first = segments.first, !first.isEmpty {
            guard username.hasPrefix(first) else { return false }
            cursor = username.index(cursor, offsetBy: first.count)
        }

        let tailAnchor = segments.last ?? ""
        if !tailAnchor.isEmpty {
            guard username.hasSuffix(tailAnchor) else { return false }
            if segments.count == 2 { return true }
        }

        let endIndex = tailAnchor.isEmpty
            ? username.endIndex
            : username.index(username.endIndex, offsetBy: -tailAnchor.count)

        for segment in segments.dropFirst().dropLast() where !segment.isEmpty {
            guard let range = username.range(of: segment, range: cursor..<endIndex) else {
                return false
            }
            cursor = range.upperBound
        }
        return true
    }
}
